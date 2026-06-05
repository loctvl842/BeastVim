local M = {}

function M.get()
	local p = Palette.get()
	local blend = Util.colors.blend
	return Util.colors.build("BeastStc", {
		DiagError = { link = "DiagnosticSignError" },
		DiagWarn = { link = "DiagnosticSignWarn" },
		DiagInfo = { link = "DiagnosticSignInfo" },
		DiagHint = { link = "DiagnosticSignHint" },

		GitAdd = { fg = p.accent3 },
		GitChange = { fg = p.accent2 },
		GitDelete = { fg = p.accent1 },

		-- Staged tier — desaturated blends against background so the gutter
		-- whispers "this is staged" without competing with live edits.
		GitStagedAdd = { fg = blend(p.accent3, 0.45, p.background) },
		GitStagedChange = { fg = blend(p.accent2, 0.45, p.background) },
		GitStagedDelete = { fg = blend(p.accent1, 0.45, p.background) },

		Fold = { fg = p.dimmed1 },
	})
end

return M
