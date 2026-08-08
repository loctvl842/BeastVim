local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastInput", {
		Normal = { bg = p.dark1, fg = p.text },
		Border = { fg = p.dimmed3, bg = p.dark1 },
		Title = { bg = p.dark1, fg = p.accent3, bold = true },
	})
end

return M
