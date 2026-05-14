---@class Beast.Finder.Config
---@field width number fraction of editor width (0–1)
---@field height number fraction of editor height (0–1)
---@field preview_ratio number fraction of list+preview width given to preview (0–1)
---@field backdrop boolean whether to show a dark backdrop behind the picker
---@field prompt_prefix string prefix shown in the input prompt (e.g. "> ")
---@field selection_prefix string prefix shown on the selected item in the list
---@field debounce { normal_ms: number, live_ms: number, preview_ms: number }
---@field matcher { smartcase: boolean, ignorecase: boolean }
---@field actions table<string, fun(picker: table, items: Beast.Finder.Item[])>
---@field zindex number

local defaults = {
	width = 0.8,
	height = 0.8,
	preview_ratio = 0.55,
	backdrop = true,
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
	zindex = 50,
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
