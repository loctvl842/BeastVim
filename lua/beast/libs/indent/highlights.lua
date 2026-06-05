local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastIndent", {
		Guide = { fg = p.dimmed5 },
		Scope = { fg = p.dimmed3 },
		ScopeUnderline = { sp = p.dimmed3, underline = true },
	})
end

return M
