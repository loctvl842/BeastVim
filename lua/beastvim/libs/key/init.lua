local ui = require("beastvim.libs.key.ui")

local M = {}

M.managed = require("beastvim.libs.key.core").managed

---@class Beast.Key.Config
local cfg = {
	ui = {
		actions = {
			{
				keys = "M",
				label = "Cycle mode",
				key_hl = "DiagnosticWarn",
				label_hl = "Comment",
				action = function() end,
			},
			-- { key = "B",   label = "Toggle beast", key_hl = "DiagnosticInfo",  label_hl = "Comment" },
			{
				keys = { "q", "<Esc>" },
				label = "Close",
				key_hl = "DiagnosticError",
				label_hl = "Comment",
				action = ui.close,
			},
		},
	},
}

---@param opts? Beast.Key.Config
function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", cfg, opts or {})
	require("beastvim.libs.key.builtin")
	require("beastvim.libs.key.ui").setup(cfg.ui)
end

return M
