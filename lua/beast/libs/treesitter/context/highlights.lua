-- Sticky-context highlight groups.
--
--   BeastTreesitterContext                 -> background of the content float;
--                                             matches the editor so the overlay
--                                             reads as a seamless extension of
--                                             the buffer.
--   BeastTreesitterContextBottom           -> underline on the content float's
--                                             last row, marking the boundary
--                                             between sticky context and code.
--   BeastTreesitterContextLineNumber       -> recolours the line-number column
--                                             rendered in the gutter float.
--   BeastTreesitterContextLineNumberBottom -> underline on the gutter float's
--                                             last row (lines up with Bottom).
local M = {}

function M.get()
	local p = Theme.get()
	return {
		BeastTreesitterContext = { bg = p.background },
		BeastTreesitterContextBottom = { sp = Util.colors.darken(p.dimmed4, 10), underline = true },
		BeastTreesitterContextLineNumber = { fg = p.dimmed3, bg = p.background },
		BeastTreesitterContextLineNumberBottom = { sp = Util.colors.darken(p.dimmed4, 10), underline = true },
	}
end

return M
