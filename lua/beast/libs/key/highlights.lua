local p = Palette.get()

Util.colors.set_hl("BeastKey", {
	Backdrop = { bg = "#000000", underline = true, sp = p.dimmed3 },
	Normal = { bg = p.dark1, fg = p.dimmed1 },
	Border = { fg = p.dark1, bg = p.dark1 },
	WinBar = { bg = p.dark1 },
	Title = { fg = p.accent3, bold = true },
	H2 = { fg = p.dimmed1, bold = true },
	Comment = { fg = p.dimmed3 },
	Keys = { fg = p.accent6 },
	-- Popup (press-and-wait)
	PopupNormal = { bg = p.dark1, fg = p.dimmed1 },
	PopupBorder = { fg = p.dark1, bg = p.dark1 },
	PopupTitle = { fg = p.accent3, bg = p.dark1, bold = true },
	PopupBreadcrumb = { fg = p.dimmed3, bg = p.dark1, italic = true },
	PopupKey = { fg = p.accent6, bg = p.dark1, bold = true },
	PopupDesc = { fg = p.dimmed1, bg = p.dark1 },
	PopupGroup = { fg = p.accent3, bg = p.dark1 },
	PopupSeparator = { fg = p.dimmed3, bg = p.dark1 },
})
