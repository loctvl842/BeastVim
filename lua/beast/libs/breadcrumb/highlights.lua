local M = {}

function M.get()
	local p = Palette.get()
	local out = Util.colors.build("BeastBc", {
		Dir = { fg = p.dimmed3 },
		Sep = { fg = p.dimmed3 },
		File = { fg = p.dimmed2 },
		Modified = { fg = p.accent3 },
	})
	out.WinBar = { bg = p.background }
	out.WinBarNC = { bg = p.background }
	return out
end

--- Side effect: redraw winbar so the new highlights are visible immediately.
function M.post_apply()
	vim.cmd("redrawstatus")
end

return M
