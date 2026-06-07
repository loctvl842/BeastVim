local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastKey", {
		Backdrop = { bg = "#000000" },
		Normal = { bg = p.dark1, fg = p.dimmed1 },
		Border = { fg = p.dark1, bg = p.dark1 },
		WinBar = { bg = p.dark1 },
		Title = { fg = p.accent3, bold = true },
		H2 = { fg = p.dimmed1, bold = true },
		Comment = { fg = p.dimmed3 },
		Keys = { fg = p.accent6 },
		-- Hint (press-and-wait)
		HintNormal = { bg = p.dark1, fg = p.dimmed1 },
		HintBorder = { fg = p.dark1, bg = p.background },
		HintTitle = { fg = p.accent3, bg = p.dark1, bold = true },
		HintBreadcrumb = { fg = p.dimmed3, bg = p.dark1, italic = true },
		HintKey = { fg = p.accent6, bg = p.dark1, bold = true },
		HintDesc = { fg = p.dimmed1, bg = p.dark1 },
		HintGroup = { fg = p.accent3, bg = p.dark1 },
		HintSeparator = { fg = p.dimmed3, bg = p.dark1 },
		HintHeader = { fg = p.dimmed3, bg = p.dark1, italic = true },
	})
end

return M
