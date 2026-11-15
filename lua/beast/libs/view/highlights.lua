local M = {}

--- Shared diff colors: the git hunk preview and the finder both draw their diffs with these.
function M.get()
	local p = Theme.get()
	local bg = p.dark1
	return Util.colors.build("BeastView", {
		-- Full-line backgrounds for changed rows.
		DiffAdd = { bg = Util.colors.blend(p.green, 0.15, bg) },
		DiffDelete = { bg = Util.colors.blend(p.red, 0.15, bg) },

		-- Stronger backgrounds for the words that changed inside a modified line
		-- (bg only, so syntax foreground colors stay intact).
		DiffAddWord = { bg = Util.colors.blend(p.green, 0.35, bg) },
		DiffDeleteWord = { bg = Util.colors.blend(p.red, 0.35, bg) },

		-- Gutter foregrounds (line number + +/- marker). bg inherits the line bg
		-- so the tint stays continuous across the gutter.
		DiffAddSign = { fg = Util.colors.blend(p.green, 0.6, bg), bg = Util.colors.blend(p.green, 0.15, bg), bold = true },
		DiffDeleteSign = { fg = Util.colors.blend(p.red, 0.6, bg), bg = Util.colors.blend(p.red, 0.15, bg), bold = true },
	})
end

return M
