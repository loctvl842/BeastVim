-- Beast.Statuscolumn highlight definitions.
-- Re-executed on every ColorScheme change via M.highlight_modules.
--
-- All groups link to existing colorscheme groups by default — no palette
-- dependency. Users can override post-setup via vim.api.nvim_set_hl().

Util.colors.set_hl("BeastStc", {
	Number = { link = "LineNr" },
	NumberCurrent = { link = "CursorLineNr" },

	DiagError = { link = "DiagnosticSignError" },
	DiagWarn = { link = "DiagnosticSignWarn" },
	DiagInfo = { link = "DiagnosticSignInfo" },
	DiagHint = { link = "DiagnosticSignHint" },

	GitAdd = { link = "GitSignsAdd" },
	GitChange = { link = "GitSignsChange" },
	GitDelete = { link = "GitSignsDelete" },

	Fold = { link = "FoldColumn" },
	FoldCurrent = { link = "CursorLineFold" },
})
