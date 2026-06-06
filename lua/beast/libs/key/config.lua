---@class Beast.Key.Cheatsheet.Action
---@field keys string[]|string
---@field label string
---@field key_hl string
---@field label_hl string
---@field on_press string

---@class Beast.Key.HintWinConfig
---@field width { min: integer, max: integer }
---@field height { min: integer, max: number } -- max is integer rows or 0<n<=1 ratio of editor height
---@field border string|string[]
---@field anchor "NW"|"NE"|"SW"|"SE"
---@field padding [integer, integer] -- {row, col}
---@field title_pos "left"|"center"|"right"

---@class Beast.Key.HintConfig
---@field enabled boolean
---@field triggers string[]
---@field modes string[]
---@field delay integer -- ms before hint appears (0 = Helix-style immediate)
---@field win Beast.Key.HintWinConfig

---@class Beast.Key.Config
---@field mappings? (Beast.KeymapSpec|Beast.KeymapSpec[]|string|string[])[]
---@field hint? Beast.Key.HintConfig
local defaults = {
	mappings = {},
	hint = {
		enabled = true,
		triggers = { "<leader>", "<localleader>", "]", "[", "f", "<leader>z", "<leader>g" },
		modes = { "n", "x" },
		delay = 0,
		win = {
			width = { min = 30, max = 60 },
			height = { min = 4, max = 0.6 },
			border = "rounded",
			anchor = "SE",
			padding = { 0, 1 },
			title_pos = "left",
		},
	},
	cheatsheet = {
		width = 0.7,
		height = 0.7,
		backdrop = 60,
		---@type Beast.Key.Cheatsheet.Action[]
		actions = {
			{
				keys = "<CR>",
				label = "Expand",
				key_hl = "DiagnosticOk",
				label_hl = "Comment",
				on_press = "expand_at_cursor",
			},
			{
				keys = "M",
				label = "Cycle mode",
				key_hl = "DiagnosticWarn",
				label_hl = "Comment",
				on_press = "cycle_mode",
			},
			{
				keys = "B",
				label = "Toggle beast",
				key_hl = "DiagnosticInfo",
				label_hl = "Comment",
				on_press = "toggle_beast",
			},
			{
				keys = { "q", "<Esc>" },
				label = "Close",
				key_hl = "DiagnosticError",
				label_hl = "Comment",
				on_press = "close",
			},
		},
	},
}

---@type Beast.Key.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Key.Config
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
		error(string.format("beast.key.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
