-- Persistent content index for live_grep prefiltering.
--
-- Walks the repo once (via `rg --files`, so .gitignore is honored), then reads
-- files in time-budgeted slices across libuv timer ticks — each tick processes
-- files only until ~BUILD_BUDGET_MS elapses, then yields so the editor redraws
-- and stays responsive even on huge repos (2.1 GB / 90k files). Every file's
-- bigrams go into the bitset matrix; oversize files are skipped (tracked, still
-- searched directly by rg). A query maps to bigram keys, ANDs columns, and
-- returns absolute candidate paths — or nil when nothing prunes (full scan).
--
-- One index per root. Rebuilds when the cwd changes. Freshness (fs_event) is
-- layered on later; build correctness only needs prune-or-fallback semantics.

local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.engine.bigram")
local extract = require("beast.libs.finder.engine.extract")

local M = {}

-- Max wall time a build tick may hold the main loop before yielding. Small so
-- typing/redraw never stalls; the build just spans more ticks.
local BUILD_BUDGET_MS = 3
-- Files between budget checks (hrtime isn't free; batch a few reads per check).
local CHECK_EVERY = 16

---@class Beast.Finder.Index
---@field root string
---@field files string[] absolute paths, id = position - 1
---@field bigram Beast.Finder.Bigram
---@field ready boolean true once the content scan finished
---@field skipped integer oversize files not indexed
---@field max_file_size integer
---@field build_ms number
---@field id_of table<string, integer> abs path -> 0-based file id
---@field dead table<integer, boolean> tombstoned ids (deleted on disk)
---@field watcher uv.uv_fs_event_t? recursive root watcher
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
	local idx = bigram.new(opts.max_files)
	if not idx or #files == 0 then
		on_done(nil)
		return
	end
	if current then
		current:stop()
	end

	local self = setmetatable({
		root = root,
		files = files,
		bigram = idx,
		ready = false,
		skipped = 0,
		max_file_size = opts.max_file_size,
		build_ms = 0,
		id_of = {},
		dead = {},
		watcher = nil,
	}, Index)
	for i, path in ipairs(files) do
		self.id_of[path] = i - 1
	end

	local t0 = uv.hrtime()
	local cursor = 1
	-- Timer yield (vs vim.schedule) lets the editor redraw/handle keys between
	-- slices; chained schedules can starve the UI when there's no input gap.
	local timer = uv.new_timer()
	local function tick()
		local deadline = uv.hrtime() + BUILD_BUDGET_MS * 1e6
		while cursor <= #files do
			self:scan_file(cursor)
			cursor = cursor + 1
			if cursor % CHECK_EVERY == 0 and uv.hrtime() >= deadline then
				break
			end
		end
		if cursor > #files then
			timer:stop()
			timer:close()
			self.ready = true
			self.build_ms = (uv.hrtime() - t0) / 1e6
			current = self
			self:watch()
			Toast(string.format("beast.finder: bigram index ready — %d files in %.0fms", #files, self.build_ms), vim.log.levels.INFO)
			on_done(self)
		else
			timer:start(1, 0, vim.schedule_wrap(tick))
		end
	end
	timer:start(1, 0, vim.schedule_wrap(tick))
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
		if not self.dead[id] then
			paths[#paths + 1] = self.files[id + 1]
		end
	end
	return paths
end

--- Re-index a changed/new file; tombstone a deleted one. Re-adding only sets
--- more bits (a superset — rg still verifies), so freshness never drops a
--- match. New files get a fresh id; deletes are filtered out at query time.
---@param abs string absolute path
function Index:refresh(abs)
	local exists = uv.fs_stat(abs) ~= nil
	local id = self.id_of[abs]
	if not exists then
		if id then
			self.dead[id] = true
		end
		return
	end
	if not id then
		if #self.files >= self.bigram.words * 32 then
			return -- index full; new file searched only by rg's full-scan fallback
		end
		self.files[#self.files + 1] = abs
		id = #self.files - 1
		self.id_of[abs] = id
	end
	self.dead[id] = nil
	self:scan_file(id + 1)
end

--- Watch the root recursively; debounce bursts and refresh changed paths.
function Index:watch()
	local w = uv.new_fs_event()
	if not w then
		return
	end
	self.watcher = w
	local pending = {}
	w:start(self.root, { recursive = true }, function(err, fname)
		if err or not fname then
			return
		end
		local abs = fname:sub(1, 1) == "/" and fname or (self.root .. "/" .. fname)
		if pending[abs] then
			return
		end
		pending[abs] = true
		vim.defer_fn(function()
			pending[abs] = nil
			self:refresh(abs)
		end, 200)
	end)
end

--- Stop watching and forget the singleton.
function Index:stop()
	if self.watcher then
		pcall(function()
			self.watcher:stop()
			self.watcher:close()
		end)
		self.watcher = nil
	end
	if current == self then
		current = nil
	end
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
