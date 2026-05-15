---@class Beast.Packer.UI.Action
---@field keys string[]|string
---@field label string
---@field key_hl string
---@field label_hl string
---@field on_press string
---@field views string[] View modes where this action is visible (e.g. {"main", "profile"})

---@class Beast.Packer.Colorscheme
---@field name string Colorscheme name passed to `:colorscheme <name>`
---@field plugin? string Plugin directory name (matches spec.name). Omit for builtin colorschemes.

---@class Beast.Packer.Config
---@field spec? Beast.Packer.PluginSpec[] List of plugin specs
---@field colorscheme? Beast.Packer.Colorscheme Eagerly load this colorscheme at start of setup() if its plugin is already installed
---@field ui table
local defaults = {
	spec = {},
	colorscheme = nil,
	ui = {
		width = 0.7,
		height = 0.7,
		backdrop = 60,
		icons = {
			loaded = " ", -- check / success
			pending = " ", -- hollow circle
			event = " ", -- lightning / event

			keys = " ", -- keyboard
			cmd = " ", -- terminal / command
			module = "󰆧 ", -- package / module
			filetype = "", -- filetype / document
			lazy = "󰒲 ", -- sleep / idle
			eager = " ", -- eager / immediate
			dependencies = " ", -- dependency icon

			path = "󰉓 ", -- folder/path icon

			-- Operation status icons
			success = "✓",
			error = "✗",
		},
		actions = {
			{
				keys = { "S" },
				label = "Sort",
				key_hl = "DiagnosticInfo",
				label_hl = "Comment",
				on_press = "sort",
				views = { "main", "profile" },
			},
			{
				keys = { "F" },
				label = "Filter",
				key_hl = "DiagnosticHint",
				label_hl = "Comment",
				on_press = "filter_cycle",
				views = { "profile" },
			},
			{
				keys = { "G" },
				label = "Group",
				key_hl = "DiagnosticHint",
				label_hl = "Comment",
				on_press = "group_toggle",
				views = { "profile" },
			},
			{
				keys = { "P" },
				label = "Profile",
				key_hl = "DiagnosticWarn",
				label_hl = "Comment",
				on_press = "view_profile",
				views = { "main", "profile", "help" },
			},
			{
				keys = { "?", "H" },
				label = "Help",
				key_hl = "DiagnosticOk",
				label_hl = "Comment",
				on_press = "view_help",
				views = { "main", "profile" },
			},
			{
				keys = { "q", "<Esc>" },
				label = "Close",
				key_hl = "DiagnosticError",
				label_hl = "Comment",
				on_press = "close",
				views = { "main", "profile", "help" },
			},
		},
	},
}

---@type Beast.Packer.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Packer.Config
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
		error(string.format("beast.packer.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
