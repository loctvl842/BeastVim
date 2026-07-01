-- Binary serialization for the bigram content index.
--
-- The writer (a headless builder subprocess) and the reader (the editor) are
-- both us, on the same machine, so the file is a near memory-dump — no JSON,
-- MessagePack, or SQLite. It matches the in-memory `Bigram` layout so loading is
-- almost transformation-free: parse a fixed header, rebuild the tiny `col_for`
-- map, then `ffi.copy` the raw `uint32` matrix straight into a fresh bitset.
--
-- Layout (all counts little-endian uint32; matrix is native-endian, same host):
--   magic         "BEASTIDX" (8 bytes)
--   version       uint32
--   words         uint32   uint32 words per column (ceil(max_files/32))
--   max_cols      uint32   column cap
--   ncols         uint32   columns actually used
--   nfiles        uint32   highest file id + 1
--   matrix_words  uint32   uint32 elements dumped (= ncols * words)
--   file_count    uint32   number of NUL-separated paths
--   root_hash     uint32   FNV-1a of the root path (fingerprint)
--   -- col_for: ncols pairs of (uint16 key, uint16 col)
--   -- matrix:  matrix_words * uint32 (raw bytes, exactly as `add` wrote them)
--   -- paths:   file_count NUL-terminated absolute paths
--
-- Correctness rests on the reader rejecting any file whose magic, version, or
-- root_hash doesn't match, or whose declared sizes overrun the bytes on disk —
-- a bad/foreign/truncated file yields nil and the caller falls back to a full scan.

local ok_ffi, ffi = pcall(require, "ffi")
local ok_bit, bit = pcall(require, "bit")
local bigram = require("beast.libs.finder.source.live_grep.engine.bigram")

local M = {}

local MAGIC = "BEASTIDX"
local VERSION = 1
local HEADER_SIZE = 40 -- 8 magic + 8 * uint32

-- FNV-1a (32-bit), returned unsigned so writer and reader agree bit-for-bit.
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

-- (a * FNV_PRIME) mod 2^32 via 16-bit halves — a plain `a * prime` would exceed
-- 2^53 and lose precision in Lua's double arithmetic.
local function mul_prime(a)
	local a_lo = a % 65536
	local a_hi = math.floor(a / 65536) % 65536
	local hi = (a_hi * FNV_PRIME) % 65536
	return (a_lo * FNV_PRIME + hi * 65536) % 4294967296
end

---@param s string
---@return integer unsigned 32-bit hash
local function fnv1a(s)
	local h = FNV_OFFSET
	for i = 1, #s do
		h = bit.bxor(h, s:byte(i))
		if h < 0 then
			h = h + 4294967296
		end
		h = mul_prime(h)
	end
	return h
end

M.fnv1a = fnv1a

-- Little-endian encoders.
local function p16(n)
	return string.char(n % 256, math.floor(n / 256) % 256)
end

local function p32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

-- Little-endian decoders (0-based offset into the string).
local function u16(s, off)
	local a, b = s:byte(off + 1, off + 2)
	return a + b * 256
end

local function u32(s, off)
	local a, b, c, d = s:byte(off + 1, off + 4)
	return a + b * 256 + c * 65536 + d * 16777216
end

--- Serialize an index to `path` atomically (write temp, rename).
---@param index { root: string, files: string[], bigram: Beast.Finder.Bigram }
---@param path string
---@return boolean ok, string? err
function M.write(index, path)
	if not (ok_ffi and ok_bit) then
		return false, "no ffi/bit"
	end
	local bg = index.bigram
	local matrix_words = bg.ncols * bg.words

	local parts = {
		MAGIC,
		p32(VERSION),
		p32(bg.words),
		p32(bg.max_cols),
		p32(bg.ncols),
		p32(bg.nfiles),
		p32(matrix_words),
		p32(#index.files),
		p32(fnv1a(index.root)),
	}

	-- col_for pairs (key <= 65535, col < max_cols <= 65535 both fit uint16).
	for key, col in pairs(bg.col_for) do
		parts[#parts + 1] = p16(key)
		parts[#parts + 1] = p16(col)
	end

	-- Raw matrix bytes — the used prefix is exactly the first matrix_words uint32.
	if matrix_words > 0 then
		parts[#parts + 1] = ffi.string(bg.matrix, matrix_words * 4)
	end

	-- NUL-separated absolute paths.
	for _, p in ipairs(index.files) do
		parts[#parts + 1] = p
		parts[#parts + 1] = "\0"
	end

	local data = table.concat(parts)
	local tmp = path .. ".tmp"
	local fh, oerr = io.open(tmp, "wb")
	if not fh then
		return false, oerr or "open failed"
	end
	fh:write(data)
	fh:close()
	local ok, rerr = os.rename(tmp, path)
	if not ok then
		os.remove(tmp)
		return false, rerr or "rename failed"
	end
	return true
end

--- Read + validate an index file. Returns a reconstructed bigram and file list,
--- or nil when the file is missing, foreign, wrong-version, wrong-root, or short.
---@param path string
---@param expect_root string root the caller expects (fingerprint check)
---@return { bigram: Beast.Finder.Bigram, files: string[] }?
function M.read(path, expect_root)
	if not (ok_ffi and ok_bit) then
		return nil
	end
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local data = fh:read("*a")
	fh:close()
	if not data or #data < HEADER_SIZE then
		return nil
	end
	if data:sub(1, 8) ~= MAGIC or u32(data, 8) ~= VERSION then
		return nil
	end

	local words = u32(data, 12)
	local max_cols = u32(data, 16)
	local ncols = u32(data, 20)
	local nfiles = u32(data, 24)
	local matrix_words = u32(data, 28)
	local file_count = u32(data, 32)
	local root_hash = u32(data, 36)
	if root_hash ~= fnv1a(expect_root) then
		return nil
	end
	if ncols > max_cols or ncols * words ~= matrix_words then
		return nil
	end

	local matrix_off = HEADER_SIZE + ncols * 4
	local paths_off = matrix_off + matrix_words * 4
	if #data < paths_off then
		return nil
	end

	local col_for = {}
	for i = 0, ncols - 1 do
		local o = HEADER_SIZE + i * 4
		col_for[u16(data, o)] = u16(data, o + 2)
	end

	-- `data` stays referenced here, so the pointer is valid until bigram.load's
	-- ffi.copy (below) completes.
	local matrix_ptr = ffi.cast("const uint8_t*", data) + matrix_off
	local bg = bigram.load({
		words = words,
		max_cols = max_cols,
		ncols = ncols,
		nfiles = nfiles,
		col_for = col_for,
		matrix_ptr = matrix_ptr,
		matrix_words = matrix_words,
	})
	if not bg then
		return nil
	end

	local files = {}
	if paths_off < #data then
		local blob = data:sub(paths_off + 1)
		for p in (blob .. "\0"):gmatch("(.-)%z") do
			if p ~= "" then
				files[#files + 1] = p
			end
		end
	end
	if #files ~= file_count then
		return nil
	end

	return { bigram = bg, files = files }
end

return M
