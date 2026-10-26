local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastSearchCount", {
		-- End-of-line label: subtle bg so it stays readable over any text.
		Float = { fg = p.yellow, bg = p.dark2, bold = true },
	})
end

return M
