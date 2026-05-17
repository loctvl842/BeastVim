local p = Palette.get()

Util.colors.set_hl("BeastToast", {
	Normal = { bg = nil, fg = p.text },
	Body = { fg = p.dimmed2 },
	TitleERROR = { fg = p.accent1 },
	TitleDEBUG = { fg = p.accent2 },
	TitleWARN = { fg = p.accent3 },
	TitleHINT = { fg = p.accent4 },
	TitleINFO = { fg = p.accent5 },
	TitleTRACE = { fg = p.accent6 },
})
