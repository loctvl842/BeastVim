-- Persistent content index for live_grep prefiltering.
--
-- Walks the repo once (via `rg --files`, so .gitignore is honored), then reads
-- each file in chunks across `vim.uv` ticks — the editor never blocks. Every
-- file's bigrams go into the bitset matrix; oversize files are skipped (tracked,
-- still searched directly by rg). A query maps to bigram keys, ANDs columns, and
-- returns absolute candidate paths — or nil when nothing prunes (full scan).
--
-- One index per root. Rebuilds when the cwd changes. Freshness (fs_event) is
-- layered on later; build correctness only needs prune-or-fallback semantics.

local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.engine.bigram")
local extract = require("beast.libs.finder.engine.extract")

local M = {}

local FILES_PER_TICK = 256

---@class Beast.Finder.Index
---@field root string
---@field files string[] absolute paths, id = position - 1
---@field bigram Beast.Finder.Bigram
---@field ready boolean true once the content scan finished
---@field skipped integer oversize files not indexed
---@field max_file_size integer
---@field build_ms number
local Index = {}
Index.__index = Index

---@type Beast.Finder.Index?
local current = nil

--- List files under root (rg honors .gitignore). Caps at max_files.
---@param root string
---@param max_files integer
---@return string[]
local function list_files(root, max_files)
	local out = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob=!.git", root })
	if #out > max_files then
		for i = #out, max_files + 1, -1 do
			out[i] = nil
		end
	end
	return out
end

--- Build an index for root, scanning content in chunks. on_done fires on the
--- main loop with the ready index, or nil when FFI/rg are unavailable.
---@param root string
---@param opts { max_files: integer, max_file_size: integer }
---@param on_done fun(index: Beast.Finder.Index?)
function M.build(root, opts, on_done)
	local files = list_files(root, opts.max_files)
	local idx = bigram.new(#files)
	if not idx or #files == 0 then
		on_done(nil)
		return
	end

	local self = setmetatable({
		root = root,
		files = files,
		bigram = idx,
		ready = false,
		skipped = 0,
		max_file_size = opts.max_file_size,
		build_ms = 0,
	}, Index)

	local t0 = uv.hrtime()
	local cursor = 1
	local function tick()
		local stop = math.min(cursor + FILES_PER_TICK - 1, #files)
		for id = cursor, stop do
			self:scan_file(id)
		end
		cursor = stop + 1
		if cursor > #files then
			self.ready = true
			self.build_ms = (uv.hrtime() - t0) / 1e6
			current = self
			on_done(self)
		else
			vim.schedule(tick)
		end
	end
	vim.schedule(tick)
end

--- Read one file (1-based) and feed its bigrams. Oversize files are skipped.
---@param id integer
function Index:scan_file(id)
	local fd = uv.fs_open(self.files[id], "r", 420)
	if not fd then
		return
	end
	local st = uv.fs_fstat(fd)
	if st and st.size <= self.max_file_size then
		local data = uv.fs_read(fd, st.size, 0)
		if data then
			self.bigram:add(id - 1, data)
		end
	else
		self.skipped = self.skipped + 1
	end
	uv.fs_close(fd)
end

--- Candidate absolute paths for a query, or nil to fall back to a full scan.
---@param query string
---@return string[]?
function Index:query(query)
	local keys = extract.keys(query)
	if #keys == 0 then
		return nil
	end
	local ids = self.bigram:query(keys)
	if not ids then
		return nil
	end
	local paths = {}
	for _, id in ipairs(ids) do
		paths[#paths + 1] = self.files[id + 1]
	end
	return paths
end

--- The ready index for root, or nil if none/cwd changed.
---@param root string
---@return Beast.Finder.Index?
function M.get(root)
	if current and current.ready and current.root == root then
		return current
	end
	return nil
end

--- Stats for `:checkhealth`.
---@return { files: integer, skipped: integer, columns: integer, bytes: integer, build_ms: number }?
function M.report()
	if not current then
		return nil
	end
	local s = current.bigram:stats()
	return {
		files = #current.files,
		skipped = current.skipped,
		columns = s.columns,
		bytes = s.bytes,
		build_ms = current.build_ms,
	}
end

return M
