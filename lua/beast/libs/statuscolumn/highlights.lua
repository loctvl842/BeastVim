local M = {}

function M.get()
	local p = Theme.get()
	local blend = Util.colors.blend
	return Util.colors.build("BeastStc", {
		DiagError = { link = "DiagnosticSignError" },
		DiagWarn = { link = "DiagnosticSignWarn" },
		DiagInfo = { link = "DiagnosticSignInfo" },
		DiagHint = { link = "DiagnosticSignHint" },

		GitAdd = { fg = p.green },
		GitChange = { fg = p.yellow },
		GitDelete = { fg = p.red },

		-- Staged tier — desaturated blends against background so the gutter
		-- whispers "this is staged" without competing with live edits.
		GitStagedAdd = { fg = blend(p.green, 0.45, p.background) },
		GitStagedChange = { fg = blend(p.yellow, 0.45, p.background) },
		GitStagedDelete = { fg = blend(p.red, 0.45, p.background) },

		Fold = { fg = p.dimmed1 },
	})
end

return M
