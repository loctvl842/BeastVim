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
