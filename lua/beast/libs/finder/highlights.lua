local M = {}

function M.get()
	local p = Theme.get()
  local bg = Util.colors.lighten(p.dark1, 10)
	return Util.colors.build("BeastFinder", {
		-- Shared
		Backdrop = { bg = "#000000" },
		Border = { fg = p.dimmed3, bg = bg },
		Normal = { bg = bg, fg = p.text },
		-- Input
		InputNormal = { bg = bg, fg = p.text },
		InputPromptPrefix = { bg = bg, fg = p.accent2 },
		InputTitle = { bg = bg, fg = p.accent3, bold = true },
		Spinner = { bg = bg, fg = p.accent2 },
		-- List
		ListCursorLine = { bg = Util.colors.blend(p.dimmed3, 0.3, bg), bold = true },
		ListSelectionPrefix = { fg = p.accent2 },
		ListMatch = { bg = Util.colors.blend(p.text, 0.15, bg), bold = true },
		ListFile = { fg = p.text },
		ListDir = { fg = p.dimmed3 },
		ListCursor = { blend = 100, nocombine = true },
		-- Preview
		PreviewBorder = { fg = p.dimmed3, bg = bg },
		PreviewTitle = { bg = bg, fg = p.accent3, bold = true },
		PreviewMatch = { bg = Util.colors.blend(p.accent4, 0.1, bg), bold = true, underline = true },
		PreviewCurrentMatch = { bg = Util.colors.blend(p.accent4, 0.25, bg), bold = true },
	})
end

return M
