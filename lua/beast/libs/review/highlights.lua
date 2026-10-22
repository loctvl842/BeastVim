local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastReview", {
		-- Same visual language as a merge conflict: red Current, green Incoming.
		Current = { bg = Util.colors.blend(p.accent1, 0.18, p.dark1) },
		Incoming = { bg = Util.colors.blend(p.accent3, 0.18, p.dark1) },
		Label = { fg = Util.colors.blend(p.dimmed1, 0.65, p.dark1), italic = true },
	})
end

return M
