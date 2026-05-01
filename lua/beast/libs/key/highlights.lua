local M = {}

local p = Palette.get()

Util.colors.set_hl("BeastKey", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Border = { fg = p.dark1, bg = p.dark1 },
	WinBar = { bg = p.dark1 },
	Normal = { bg = p.dark1, fg = p.dimmed1 },
	Title = { link = "Title" },
	H2 = { link = "Bold" },
	Comment = { link = "Comment" },
	Keys = { link = "Statement" },
})

return M
