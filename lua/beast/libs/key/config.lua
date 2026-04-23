---@class Beast.Key.UI.Action
---@field keys string[]|string
---@field label string
---@field key_hl string
---@field label_hl string
---@field on_press string

---@class Beast.Key.Config
local defaults = {
	ui = {
		width = 0.7,
		height = 0.7,
		backdrop = 30,
		---@type Beast.Key.UI.Action[]
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
		error(
			string.format(
				"beast.key.config is read-only; cannot assign '%s' directly. Use setup() instead.",
				tostring(key)
			),
			2
		)
	end,
})

return M
