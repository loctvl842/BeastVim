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
	require("beast.libs.key.highlights")
	config.setup(opts)
	for _, spec in ipairs(config.mappings or {}) do
		M.safe_set(spec.mode or "n", spec[1], spec[2], spec)
	end
	if config.popup and config.popup.enabled then
		require("beast.libs.key.popup").setup(config.popup)
	end
end

return M
