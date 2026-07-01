-- Persistent content index for live_grep prefiltering.
--
-- Enumerates the repo once (via `rg --files`, so .gitignore is honored) and
-- reads every file's bigrams into a bitset matrix — but that heavy scan runs in
-- a *separate headless `nvim` process* (see scripts/build-finder-index.lua),
-- which serializes the finished index to a binary cache file. The editor spawns
-- that builder, and on exit loads the file with one `ffi.copy` (a fast memcpy),
-- so the main loop is never blocked no matter how large the repo (2.1 GB / 90k+
-- files). A query maps to bigram keys, ANDs columns, and returns absolute
-- candidate paths — or nil when nothing prunes (full scan).
--
-- The cache file is a per-session IPC handoff, rebuilt every launch (never
-- reused across sessions), so the index always reflects current content and the
-- no-false-negative guarantee holds without stale-cache revalidation.
--
-- One index per root. Rebuilds when the cwd changes. Freshness within a session
-- is layered on via an fs_event watcher (refresh/tombstone).

local uv = vim.uv or vim.loop
local extract = require("beast.libs.finder.engine.extract")
local serialize = require("beast.libs.finder.engine.serialize")

local M = {}

---@class Beast.Finder.Index
---@field root string
---@field files string[] absolute paths, id = position - 1
---@field bigram Beast.Finder.Bigram
---@field ready boolean true once the content scan finished
---@field skipped integer oversize files skipped during refresh (build-time skips happen in the child)
---@field max_file_size integer
---@field build_ms number
---@field id_of table<string, integer> abs path -> 0-based file id
---@field dead table<integer, boolean> tombstoned ids (deleted on disk)
---@field watcher uv.uv_fs_event_t? recursive root watcher
local Index = {}
Index.__index = Index

---@type Beast.Finder.Index?
local current = nil

-- Resolve the plugin's lua/ root and its sibling scripts/ dir from this file's
-- own path, so the builder child (which runs `--clean`, i.e. no runtimepath) can
-- set package.path and locate its entry script regardless of where BeastVim is
-- installed. .../lua/beast/libs/finder/engine/index.lua -> .../lua
local SELF = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local LUA_ROOT = vim.fn.fnamemodify(SELF, ":h:h:h:h:h")
local BUILDER_SCRIPT = vim.fn.fnamemodify(LUA_ROOT, ":h") .. "/scripts/build-finder-index.lua"

--- Per-root binary cache file (overwritten each build). Named `<basename>-<hash>`
--- so it's identifiable at a glance while staying filesystem-safe. Two roots that
--- collide on the hash just trigger a rebuild — serialize.read rejects a file
--- whose stored root_hash doesn't match, so a collision is safe (never loaded).
---@param root string
---@return string
local function cache_path(root)
	local dir = vim.fn.stdpath("cache") .. "/beast/finder"
	vim.fn.mkdir(dir, "p")
	local name = vim.fn.fnamemodify(root, ":t"):gsub("[^%w%-_.]", "_")
	if name == "" then
		name = "root"
	end
	return string.format("%s/%s-%08x.idx", dir, name, serialize.fnv1a(root))
end

-- The in-flight builder subprocess (module-local). A superseding build (e.g. a
-- cwd switch) kills the previous one so a stale child can't race the new index.
---@type uv.uv_process_t?
local inflight = nil

local function kill_inflight()
	if inflight then
		pcall(function()
			inflight:kill("sigterm")
			if not inflight:is_closing() then
				inflight:close()
			end
		end)
		inflight = nil
	end
end

--- Wrap a loaded index as the current singleton and start watching for changes.
---@param root string
---@param loaded { bigram: Beast.Finder.Bigram, files: string[] }
---@param opts { max_file_size: integer }
---@param build_ms number
---@return Beast.Finder.Index
local function install(root, loaded, opts, build_ms)
	local self = setmetatable({
		root = root,
		files = loaded.files,
		bigram = loaded.bigram,
		ready = true,
		skipped = 0,
		max_file_size = opts.max_file_size,
		build_ms = build_ms,
		id_of = {},
		dead = {},
		watcher = nil,
	}, Index)
	for i, path in ipairs(loaded.files) do
		self.id_of[path] = i - 1
	end
	if current then
		current:stop()
	end
	current = self
	self:watch()
	return self
end

--- Build an index for root in a separate process, then load it. on_done fires on
--- the main loop with the ready index, or nil when the build/load fails (caller
--- falls back to a full rg scan). The heavy content scan runs in a headless
--- child, so the editor's loop is never blocked by it.
---@param root string
---@param opts { max_files: integer, max_file_size: integer, max_cols?: integer }
---@param on_done fun(index: Beast.Finder.Index?)
function M.build(root, opts, on_done)
	kill_inflight()
	local out = cache_path(root)
	local t0 = uv.hrtime()

	-- uv.spawn replaces (not augments) the child's env, so pass the current
	-- environment through explicitly — otherwise the child loses PATH and can't
	-- find `rg`.
	local environ = vim.fn.environ()
	environ.BEAST_FINDER_LUA_ROOT = LUA_ROOT
	environ.BEAST_FINDER_ROOT = root
	environ.BEAST_FINDER_OUT = out
	environ.BEAST_FINDER_MAX_FILES = tostring(opts.max_files)
	environ.BEAST_FINDER_MAX_FILE_SIZE = tostring(opts.max_file_size)
	if opts.max_cols then
		environ.BEAST_FINDER_MAX_COLS = tostring(opts.max_cols)
	end
	local env = {}
	for k, v in pairs(environ) do
		env[#env + 1] = k .. "=" .. v
	end

	local handle
	handle = uv.spawn(vim.v.progpath, {
		args = { "--headless", "--clean", "-l", BUILDER_SCRIPT },
		env = env,
		stdio = { nil, nil, nil },
		hide = true,
	}, function(code)
		inflight = nil
		if handle and not handle:is_closing() then
			handle:close()
		end
		vim.schedule(function()
			local loaded = code == 0 and serialize.read(out, root) or nil
			if not loaded then
				on_done(nil)
				return
			end
			local self = install(root, loaded, opts, (uv.hrtime() - t0) / 1e6)
			Toast(string.format("beast.finder: bigram index ready — %d files in %.0fms", #self.files, self.build_ms), vim.log.levels.INFO)
			on_done(self)
		end)
	end)

	if not handle then
		on_done(nil)
		return
	end
	inflight = handle
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
