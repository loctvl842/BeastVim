local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastGit", {
		PreviewNormal = { bg = p.dark1, fg = p.dimmed1 },
		PreviewBorder = { fg = p.dark1, bg = p.dark1 },

		-- Full-line backgrounds for changed rows (used via line_hl_group).
		PreviewAdd = { bg = Util.colors.blend(p.accent3, 0.15, p.dark1) },
		PreviewDelete = { bg = Util.colors.blend(p.accent1, 0.15, p.dark1) },

		-- Gutter foregrounds (line number + +/- marker). bg inherits the line bg
		-- so the tint stays continuous across the gutter.
		PreviewAddSign = { fg = Util.colors.blend(p.accent3, 0.6, p.dark1), bg = Util.colors.blend(p.accent3, 0.15, p.dark1), bold = true },
		PreviewDeleteSign = { fg = Util.colors.blend(p.accent1, 0.6, p.dark1), bg = Util.colors.blend(p.accent1, 0.15, p.dark1), bold = true },

		-- "Staged" badge in the float's top-right border.
		PreviewStagedTitle = { fg = p.dark1, bg = Util.colors.blend(p.accent4, 0.7, p.dark1), bold = true },

		-- Current-line blame virt_text. Foreground only — a background tint
		-- would fight the cursorline.
		CurrentLineBlame = { fg = Util.colors.blend(p.dimmed1, 0.55, p.dark1), italic = true },

		-- Full-file blame side window: three-tone hierarchy so the column
		-- reads cleanly without distracting from the source code on the right.
		BlameViewSha = { fg = Util.colors.blend(p.accent4, 0.75, p.dark1) },
		BlameViewAuthor = { fg = Util.colors.blend(p.dimmed1, 0.85, p.dark1) },
		BlameViewDate = { fg = Util.colors.blend(p.dimmed1, 0.55, p.dark1), italic = true },
	})
end

return M
