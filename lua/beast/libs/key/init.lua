local config = require("beast.libs.key.config")

local M = setmetatable({}, {
	__index = function(_, key)
		return require("beast.libs.key.core")[key]
	end,
})

M.safe_set = require("beast.libs.key.core").safe_set

M.managed = require("beast.libs.key.core").managed

---@param opts? Beast.Key.Config
function M.setup(opts)
	require("beast.libs.key.builtin")
	config.setup(opts)
end

return M
