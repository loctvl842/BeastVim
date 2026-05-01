local p = Palette.get()

Util.colors.set_hl("BeastConfirm", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Normal = { bg = p.dark1, fg = p.dimmed1 },
	Border = { fg = p.dark1, bg = p.dark1 },
	Button = { bg = Util.colors.lighten(p.dark1, 20), fg = p.dimmed2 },
	ButtonActive = { bg = p.accent5, fg = p.dark1, bold = true },
})
