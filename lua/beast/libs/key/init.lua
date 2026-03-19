local ui = require("beast.libs.key.ui")
local api = require("beast.libs.key.api")

---@class Beast.Key.UI.Segment
---@field text string
---@field hl? string

---@alias Beast.Key.UI.Line Beast.Key.UI.Segment[]

local M = {}

M.managed = require("beast.libs.key.core").managed

---@param view Beast.Key.UI.MainView
---@param lines_segments Beast.Key.UI.Line[]
local function render(view, lines_segments)
  -- stylua: ignore
  if not view:is_valid() then return end

	local lines = {}
	local marks = {}
	local ns = view.ns
	local buf = view.buf
	for i, segs in ipairs(lines_segments) do
		local s, col = "", 0
		for _, seg in ipairs(segs) do
			if seg.hl then
				marks[#marks + 1] = { i - 1, col, col + #seg.text, seg.hl }
			end
			s = s .. seg.text
			col = col + #seg.text
		end
		lines[i] = s
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
	end
end

---@param view Beast.Key.UI.MainView
function M.cycle_mode(view)
	render(view, api.cycle_mode())
end

function M.toggle_beast(view)
	render(view, api.toggle_beast_only())
end

M.close = ui.close

---@class Beast.Key.Config
local cfg = {
	ui = {
		actions = {
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
	cfg.ui.hooks = {
		main = {
			render = function(main)
				render(main, api.default())
			end,
		},
	}
	require("beast.libs.key.ui").setup(cfg.ui)
end

return M
