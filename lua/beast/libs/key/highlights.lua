local p = Palette.get()

Util.colors.set_hl("BeastKey", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Normal = { bg = p.dark1, fg = p.dimmed1 },
	Border = { fg = p.dark1, bg = p.dark1 },
	WinBar = { bg = p.dark1 },
	Title = { fg = p.accent3, bold = true },
	H2 = { fg = p.dimmed1, bold = true },
	Comment = { fg = p.dimmed3 },
	Keys = { fg = p.accent6 },
})
