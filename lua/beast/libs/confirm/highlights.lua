local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastConfirm", {
		Backdrop = { bg = "#000000" },
		Normal = { bg = p.dark1, fg = p.dimmed1 },
		Border = { fg = p.dark1, bg = p.dark1 },
		Button = { bg = Util.colors.lighten(p.dark1, 20), fg = p.dimmed2, bold = true },
		ButtonActive = { bg = p.accent5, fg = p.dark1, bold = true },
		Description = { bg = p.dark1, fg = p.dimmed4, italic = true },
	})
end

return M
