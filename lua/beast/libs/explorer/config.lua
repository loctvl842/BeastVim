---@class Beast.Explorer.Config
---@field width         integer        panel width in columns
---@field side          "left"|"right" which side to open the split
---@field show_hidden   boolean        show dot-files
---@field icons         boolean        nerd-font glyphs (requires nvim-web-devicons)
---@field git           boolean        git-status indicators
---@field indent        string         per-depth indent string
---@field icon_dir_open   string       glyph for an open directory
---@field icon_dir_closed string       glyph for a closed directory
---@field icon_file       string       fallback glyph for files without a devicon
---@field icon_git  table<string, {[1]:string,[2]:string}> xy-code → {glyph, hl-group}

local defaults = {
	width = 30,
	side = "left",
	show_hidden = false,
	icons = true,
	git = true,
	indent = "  ",
	icon_dir_open = "",
	icon_dir_closed = "",
	icon_file = "󰈙 ",
	icon_git = {
		["M "] = { "●", "DiagnosticOk" }, -- staged
		[" M"] = { "●", "DiagnosticWarn" }, -- unstaged
		["MM"] = { "●", "DiagnosticWarn" }, -- both
		["A "] = { "+", "DiagnosticOk" }, -- added
		["??"] = { "?", "DiagnosticHint" }, -- untracked
		["!!"] = { "", "Comment" }, -- ignored
		[" D"] = { "✗", "DiagnosticError" }, -- deleted
		["D "] = { "✗", "DiagnosticError" },
	},
}

local cfg = vim.deepcopy(defaults)

local M = {}
M.cfg = cfg -- live reference — other modules read M.cfg directly

function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	M.cfg = cfg -- update the reference so callers that cached the module still see it
end

return M
