local M = {}

function M.get()
	local p = Theme.get()
	-- What the dimming backdrop leaves visible around the card: the editor background
	-- blended with the black backdrop at the configured window blend.
	local editor_bg = Util.colors.inspect("Normal").bg or p.background
	local behind = Util.colors.blend(editor_bg, require("beast.libs.select.config").ui.backdrop / 100, "#000000")
	return Util.colors.build("BeastSelect", {
		Backdrop = { bg = "#000000" },
		-- List panel is darker than the prompt panel (editor > prompt > list)
		Normal = { bg = p.dark2, fg = p.text },
		Border = { fg = p.dark2, bg = p.dark2 },
		InputNormal = { bg = p.dark1, fg = p.text },
		InputTitle = { bg = p.dark1, fg = p.accent3, bold = true },
		-- "▄" row on top of the prompt panel: lower half in the panel colour, upper half
		-- in the backdrop colour, i.e. a half-row top edge.
		InputTopEdge = { fg = p.dark1, bg = behind },
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
