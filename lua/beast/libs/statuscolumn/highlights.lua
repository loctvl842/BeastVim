local p = Palette.get()

Util.colors.set_hl("BeastStc", {
	DiagError = { link = "DiagnosticSignError" },
	DiagWarn = { link = "DiagnosticSignWarn" },
	DiagInfo = { link = "DiagnosticSignInfo" },
	DiagHint = { link = "DiagnosticSignHint" },

	GitAdd = { fg = p.accent3 },
	GitChange = { fg = p.accent2 },
	GitDelete = { fg = p.accent1 },

	Fold = { fg = p.dimmed1 },
})
