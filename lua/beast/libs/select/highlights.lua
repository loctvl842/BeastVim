local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastSelect", {
		Backdrop = { bg = "#000000" },
		Normal = { bg = p.dark1, fg = p.text },
		Border = { fg = p.dark1, bg = p.dark1 },
		InputNormal = { bg = p.dark1, fg = p.text },
		InputTitle = { bg = p.dark1, fg = p.accent3, bold = true },
		ListCursorLine = { bg = Util.colors.blend(p.dimmed3, 0.3, p.dark1), bold = true },
		ListBullet = { fg = p.accent2 },
		ListTag = { fg = p.dimmed3 },
		ListEmpty = { fg = p.dimmed3, italic = true },
		Footer = { bg = p.dark1, fg = p.dimmed3 },
	})
end

return M
