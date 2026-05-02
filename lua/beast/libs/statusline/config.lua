---@class Beast.Statusline.Config
local defaults = {
	-- Layout: lists of component specs per region. Populated by user via setup().
	left = {},
	center = {},
	right = {},

	-- Default separator inserted between adjacent visible components in a section.
	separator = "   ",

	-- Default priority used for components that don't declare one.
	default_priority = 50,

	-- Truncation indicator placed at the cut point. Set to "" to disable.
	truncate_marker = "%<",
}

---@type Beast.Statusline.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Statusline.Config
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
		error(string.format("beast.libs.statusline.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
