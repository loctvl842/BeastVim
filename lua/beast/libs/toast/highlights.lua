local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastToast", {
		Normal = { bg = nil, fg = p.text },
		Body = { fg = p.dimmed2 },
		TitleERROR = { fg = p.accent1 },
		TitleDEBUG = { fg = p.accent2 },
		TitleWARN = { fg = p.accent3 },
		TitleHINT = { fg = p.accent4 },
		TitleINFO = { fg = p.accent5 },
		TitleTRACE = { fg = p.accent6 },
	})
end

return M
