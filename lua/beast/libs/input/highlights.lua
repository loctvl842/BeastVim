local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastInput", {
		Normal = { bg = p.background, fg = p.text },
		Border = { fg = p.dimmed3, bg = p.background },
		Title = { bg = p.background, fg = p.accent3, bold = true },
	})
end

return M
