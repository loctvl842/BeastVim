local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastSelect", {
		Backdrop = { bg = "#000000" },
		-- List panel is darker than the prompt panel (editor > prompt > list)
		Normal = { bg = p.dark2, fg = p.text },
		Border = { fg = p.dark2, bg = p.dark2 },
		InputNormal = { bg = p.dark1, fg = p.text },
		InputTitle = { bg = p.dark1, fg = p.accent3, bold = true },
		ListSelected = { fg = p.accent5, bold = true },
		ListSelectedLine = { fg = p.accent5 },
		ListPointer = { fg = p.accent5 },
		ListSeparator = { fg = p.dimmed4 },
		ListTag = { fg = p.dimmed3 },
		ListEmpty = { fg = p.dimmed3, italic = true },
		Footer = { bg = p.dark2, fg = p.dimmed3 },
	})
end

return M
