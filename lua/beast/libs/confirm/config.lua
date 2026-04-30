---@class Beast.Confirm.Config
local defaults = {
	disabled = false,
	ui = {
		backdrop = 60,
	},
}

---@type Beast.Confirm.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Confirm.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,
	__newindex = function(_, key, _)
		error(string.format("beast.confirm.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
