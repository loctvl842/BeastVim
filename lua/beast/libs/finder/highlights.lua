local M = {}

function M.setup()
	local p = Palette.get()

	Util.colors.set_hl("BeastFinder", {
		Backdrop = { bg = "#000000" },
		Border = { fg = p.dimmed3, bg = p.dark1 },
		Normal = { bg = p.dark1, fg = p.text },
		Prompt = { bg = p.dark1, fg = p.text },
		Match = { fg = p.accent3, bold = true },
		File = { fg = p.text },
		Dir = { fg = p.dimmed3 },
		Selected = { bg = p.dark2, fg = p.text, bold = true },
		PreviewBorder = { fg = p.dimmed3, bg = p.dark1 },
	})
end

return M
