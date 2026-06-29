-- Bigram inverted index over file contents.
--
-- Each distinct 2-byte sequence (bigram) gets one column. A column is a bitset
-- with one bit per file: bit i is set when file i contains that bigram. A query
-- ANDs the columns of its bigrams, producing the small set of files that could
-- match. The set only ever shrinks the candidate pool — `rg` still verifies, so
-- a missing/capped column never drops a real match (no false negatives).
--
-- Storage is a flat uint32 matrix (max_cols * words). 32-bit words keep the bit
-- math inside LuaJIT's `bit` library. ~56 MB for 90k files at 5000 columns.

local ok_ffi, ffi = pcall(require, "ffi")
local ok_bit, bit = pcall(require, "bit")

local M = {}

local WORD_BITS = 32
local DEFAULT_MAX_COLS = 5000

---@class Beast.Finder.Bigram
---@field words integer uint32 words per column (ceil(max_files / 32))
---@field max_cols integer hard cap on distinct bigram columns
---@field ncols integer columns allocated so far
---@field nfiles integer highest file id added + 1
---@field col_for table<integer, integer> bigram key (0..65535) -> column index
---@field matrix ffi.cdata* uint32_t[max_cols * words], zeroed
local Bigram = {}
Bigram.__index = Bigram

--- Bigram key for two bytes (0..65535).
---@param b1 integer
---@param b2 integer
---@return integer
local function key_of(b1, b2)
	return b1 * 256 + b2
end

M.key_of = key_of

--- Decompose a literal string into its bigram keys (deduplicated). Lowercased
--- so the index is case-insensitive — a superset for smart-case queries, which
--- only ever over-includes candidates (rg verifies; no false negatives).
---@param s string
---@return integer[]
function M.keys_of(s)
	s = s:lower()
	local seen, keys = {}, {}
	for i = 1, #s - 1 do
		local k = key_of(s:byte(i), s:byte(i + 1))
		if not seen[k] then
			seen[k] = true
			keys[#keys + 1] = k
		end
	end
	return keys
end

--- Whether the FFI backend is available (LuaJIT). Pure-Lua hosts get nil.
---@return boolean
function M.available()
	return ok_ffi and ok_bit
end

--- Create an index sized for `max_files`.
---@param max_files integer
---@param max_cols? integer default 5000
---@return Beast.Finder.Bigram?
function M.new(max_files, max_cols)
	if not (ok_ffi and ok_bit) then
		return nil
	end
	max_cols = max_cols or DEFAULT_MAX_COLS
	local words = math.ceil(math.max(max_files, 1) / WORD_BITS)
	return setmetatable({
		words = words,
		max_cols = max_cols,
		ncols = 0,
		nfiles = 0,
		col_for = {},
		matrix = ffi.new("uint32_t[?]", max_cols * words), -- zero-filled
	}, Bigram)
end

--- Column index for a bigram key, allocating on first sight. nil once capped.
---@param key integer
---@return integer?
function Bigram:column(key)
	local col = self.col_for[key]
	if col then
		return col
	end
	if self.ncols >= self.max_cols then
		return nil
	end
	col = self.ncols
	self.col_for[key] = col
	self.ncols = col + 1
	return col
end

--- Record every bigram of `bytes` against file id (0-based). Bytes are
--- lowercased so the index is case-insensitive (matches keys_of).
---@param id integer
---@param bytes string
function Bigram:add(id, bytes)
	bytes = bytes:lower()
	if id + 1 > self.nfiles then
		self.nfiles = id + 1
	end
	local word = math.floor(id / WORD_BITS)
	local mask = bit.lshift(1, id % WORD_BITS)
	local words = self.words
	local m = self.matrix
	local prev = bytes:byte(1)
	for i = 2, #bytes do
		local b = bytes:byte(i)
		local col = self:column(key_of(prev, b))
		if col then
			local idx = col * words + word
			m[idx] = bit.bor(m[idx], mask)
		end
		prev = b
	end
end

--- AND the columns of `keys`; keys with no column don't prune. Returns 0-based
--- file ids that have every recognized bigram, or nil when nothing prunes.
---@param keys integer[]
---@return integer[]?
function Bigram:query(keys)
	local words = self.words
	local acc = ffi.new("uint32_t[?]", words)
	local started = false
	for _, key in ipairs(keys) do
		local col = self.col_for[key]
		if col then
			local base = col * words
			if not started then
				for w = 0, words - 1 do
					acc[w] = self.matrix[base + w]
				end
				started = true
			else
				for w = 0, words - 1 do
					acc[w] = bit.band(acc[w], self.matrix[base + w])
				end
			end
		end
	end
	if not started then
		return nil
	end
	local ids = {}
	for w = 0, words - 1 do
		local cell = acc[w]
		if cell ~= 0 then
			local base = w * WORD_BITS
			for b = 0, WORD_BITS - 1 do
				if bit.band(cell, bit.lshift(1, b)) ~= 0 then
					local id = base + b
					if id < self.nfiles then
						ids[#ids + 1] = id
					end
				end
			end
		end
	end
	return ids
end

--- Stats for `:checkhealth`.
---@return { files: integer, columns: integer, words: integer, bytes: integer }
function Bigram:stats()
	return {
		files = self.nfiles,
		columns = self.ncols,
		words = self.words,
		bytes = self.max_cols * self.words * 4,
	}
end

return M
