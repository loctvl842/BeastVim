---@class Beast.Util
---@field root beast.util.root
---@field colors beast.util.colors
---@field debounce fun(ms: integer, fn: function): Beast.Util.Debouncer
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.util." .. k)
		return mod
	end,
})

-- Resolve the lua/ root from this file's own source so Util.mod can
-- loadfile() absolute paths instead of scanning package.path.
-- debug.getinfo(1,"S").source -> "@/abs/path/lua/beast/util/init.lua"
local lua_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

--- Fast module loader: bypasses `package.path` scan by `loadfile`-ing
--- an absolute path computed from `lua_root`. Behaves like `require`
--- (caches in `package.loaded`, tries both `<mod>.lua` and `<mod>/init.lua`)
--- for modules that live under `lua/`.
---@param modname string e.g. "beast.libs.statusline.components"
---@return any
function M.mod(modname)
	local cached = package.loaded[modname]
	if cached then
		return cached
	end
	local base = lua_root .. "/" .. modname:gsub("%.", "/")
	local chunk = loadfile(base .. ".lua") or loadfile(base .. "/init.lua")
	if not chunk then
		error("Util.mod: cannot load " .. modname .. " from " .. base .. "{.lua,/init.lua}", 2)
	end
	local ret = chunk()
	package.loaded[modname] = ret
	return ret
end

-- High-resolution timer helper
---@return integer ns Nanoseconds
function M.hrtime()
	local uv = vim.uv or vim.loop
	if uv and uv.hrtime then
		return uv.hrtime()
	end
	-- Fallback using reltime (seconds as float)
	return math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e9)
end

return M
