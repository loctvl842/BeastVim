---@class Beast.Input.Config
local defaults = {
	disabled = false,
}

---@type Beast.Input.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Input.Config
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
		error(string.format("beast.input.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
