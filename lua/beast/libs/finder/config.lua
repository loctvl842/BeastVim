---@class Beast.Finder.Config
local defaults = {
	width = 0.8,
	height = 0.8,
	preview_ratio = 0.45,
	backdrop = 60,
	prompt_prefix = " ",
	selection_prefix = "▌",
	debounce = {
		normal_ms = 30,
		live_ms = 200,
		preview_ms = 60,
	},
	matcher = {
		smartcase = true,
		ignorecase = true,
	},
	actions = {},
}

---@type Beast.Finder.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Finder.Config
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
		error(string.format("beast.finder.config is read-only; cannot assign '%s'. Use setup().", tostring(key)), 2)
	end,
})

return M
