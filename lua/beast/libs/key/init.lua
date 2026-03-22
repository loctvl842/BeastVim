local state = require("beast.libs.key.state")
local ui = require("beast.libs.key.ui")
local api = require("beast.libs.key.api")

local M = setmetatable({}, {
	__index = function(_, key)
		return require("beast.libs.key.core")[key]
	end,
})

M.safe_set = require("beast.libs.key.core").safe_set

M.managed = require("beast.libs.key.core").managed

function M.cycle_mode()
  state.lines = api.cycle_mode()
  ui.refresh()
end

function M.toggle_beast()
  state.lines = api.toggle_beast_only()
  ui.refresh()
end

function M.expand_at_cursor()
	local line = vim.api.nvim_get_current_line()
	local id = line:match("%[.+%] (%S+)")
	if not id then
		return
	end
  state.lines = api.toggle_expand(id)
  ui.refresh()
end

function M.close()
	ui.close()
end

---@class Beast.Key.Config
local cfg = {
	ui = {
		actions = {
			{
				keys = "<CR>",
				label = "Expand",
				key_hl = "DiagnosticOk",
				label_hl = "Comment",
				on_press = M.expand_at_cursor,
			},
			{
				keys = "M",
				label = "Cycle mode",
				key_hl = "DiagnosticWarn",
				label_hl = "Comment",
				on_press = M.cycle_mode,
			},
			{
				keys = "B",
				label = "Toggle beast",
				key_hl = "DiagnosticInfo",
				label_hl = "Comment",
				on_press = M.toggle_beast,
			},
			{
				keys = { "q", "<Esc>" },
				label = "Close",
				key_hl = "DiagnosticError",
				label_hl = "Comment",
				on_press = M.close,
			},
		},
	},
}

---@param opts? Beast.Key.Config
function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", cfg, opts or {})
	require("beast.libs.key.builtin")
  state.lines = api.default()
	require("beast.libs.key.ui").setup(cfg.ui)
end

return M
