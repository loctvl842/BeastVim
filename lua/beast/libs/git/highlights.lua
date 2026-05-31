local p = Palette.get()

Util.colors.set_hl("BeastGit", {
	PreviewNormal = { bg = p.dark1, fg = p.dimmed1 },
	PreviewBorder = { fg = p.dark1, bg = p.dark1 },

	-- Full-line backgrounds for changed rows (used via line_hl_group).
	PreviewAdd = { bg = Util.colors.blend(p.accent3, 0.15, p.dark1) },
	PreviewDelete = { bg = Util.colors.blend(p.accent1, 0.15, p.dark1) },

	-- Gutter foregrounds (line number + +/- marker). bg inherits the line bg
	-- so the tint stays continuous across the gutter.
	PreviewAddSign = { fg = Util.colors.blend(p.accent3, 0.6, p.dark1), bg = Util.colors.blend(p.accent3, 0.15, p.dark1), bold = true },
	PreviewDeleteSign = { fg = Util.colors.blend(p.accent1, 0.6, p.dark1), bg = Util.colors.blend(p.accent1, 0.15, p.dark1), bold = true },
})
