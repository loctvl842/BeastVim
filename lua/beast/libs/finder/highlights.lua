local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastFinder", {
		-- Shared
		Backdrop = { bg = "#000000" },
		Border = { fg = p.dimmed3, bg = p.dark1 },
		Normal = { bg = p.dark1, fg = p.text },
		-- Input
		InputNormal = { bg = p.dark1, fg = p.text },
		InputPromptPrefix = { bg = p.dark1, fg = p.accent2 },
		InputTitle = { bg = p.dark1, fg = p.accent3, bold = true },
		Spinner = { bg = p.dark1, fg = p.accent2 },
		-- List
		ListCursorLine = { bg = Util.colors.blend(p.dimmed3, 0.3, p.dark1), bold = true },
		ListSelectionPrefix = { fg = p.accent2 },
		ListMatch = { bg = Util.colors.blend(p.text, 0.15, p.dark1), bold = true },
		ListFile = { fg = p.text },
		ListDir = { fg = p.dimmed3 },
		ListCursor = { blend = 100, nocombine = true },
		-- Preview
		PreviewBorder = { fg = p.dimmed3, bg = p.dark1 },
		PreviewTitle = { bg = p.dark1, fg = p.accent3, bold = true },
		PreviewMatch = { bg = Util.colors.blend(p.text, 0.15, p.dark1), bold = true, underline = true },
		PreviewCurrentMatch = { reverse = true, bold = true },
	})
end

return M
