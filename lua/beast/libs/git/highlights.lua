local p = Palette.get()

Util.colors.set_hl("BeastGit", {
	PreviewNormal = { bg = p.dark1, fg = p.dimmed1 },
	PreviewBorder = { fg = p.dark1, bg = p.dark1 },
	PreviewAdd = { bg = Util.colors.blend(p.accent3, 0.2, p.dark1), fg = p.accent3 },
	PreviewDelete = { bg = Util.colors.blend(p.accent1, 0.2, p.dark1), fg = p.accent1 },
})
