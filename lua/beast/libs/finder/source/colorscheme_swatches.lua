--- Per-colorscheme swatch colors, read by a headless child so the user's editor is never repainted.
--- Results are cached on disk, keyed by theme name and the theme file's mtime.
local M = {}

---@alias Beast.Finder.Swatches (string|false)[] ten hex colors in role order, false when unset

---@class Beast.Finder.SwatchCache
---@field mtime integer
---@field colors Beast.Finder.Swatches

local COUNT = 10

---@type table<string, Beast.Finder.SwatchCache>|nil
local cache
local running = false

local function cache_path()
	return vim.fn.stdpath("cache") .. "/beast-finder-colorscheme-swatches.json"
end

local function worker_path()
	return vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "colorscheme_swatches_worker.lua")
end

---@return table<string, Beast.Finder.SwatchCache>
local function load()
	if cache then
		return cache
	end
	cache = {}
	local f = io.open(cache_path(), "r")
	if f then
		local ok, decoded = pcall(vim.json.decode, f:read("*a"))
		f:close()
		if ok and type(decoded) == "table" then
			cache = decoded
		end
	end
	return cache
end

---@param path string
---@return integer|nil
local function mtime_of(path)
	local stat = vim.uv.fs_stat(path)
	return stat and stat.mtime.sec or nil
end

---Cached swatches for a theme, nil when missing or the theme file changed.
---@param name string
---@param path string colorscheme file
---@return Beast.Finder.Swatches|nil
function M.get(name, path)
	local entry = load()[name]
	if entry and entry.mtime == mtime_of(path) then
		return entry.colors
	end
	return nil
end

---Compute swatches for every stale/missing theme in one headless child, then call `on_done`.
---A call while a previous run is still in flight is ignored.
---@param themes { name: string, path: string }[]
---@param on_done fun()
function M.ensure(themes, on_done)
	if running then
		return
	end
	local stale, mtimes = {}, {}
	for _, t in ipairs(themes) do
		if not M.get(t.name, t.path) then
			stale[#stale + 1] = t.name
			mtimes[t.name] = mtime_of(t.path)
		end
	end
	if #stale == 0 then
		return
	end

	running = true
	local cmd = { vim.v.progpath, "--headless", "-u", "NONE", "-l", worker_path(), vim.o.runtimepath }
	vim.list_extend(cmd, stale)
	vim.system(cmd, { text = true }, function(res)
		vim.schedule(function()
			running = false
			local ok, decoded = pcall(vim.json.decode, res.stdout or "")
			if not ok or type(decoded) ~= "table" then
				return
			end
			local entries = load()
			for name, colors in pairs(decoded) do
				if #colors == COUNT then
					entries[name] = { mtime = mtimes[name] or 0, colors = colors }
				end
			end
			pcall(function()
				local f = assert(io.open(cache_path(), "w"))
				f:write(vim.json.encode(entries))
				f:close()
			end)
			on_done()
		end)
	end)
end

return M
