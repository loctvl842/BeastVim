local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastReview", {
		-- Same visual language as a merge conflict: red Current, green Incoming.
		Current = { bg = Util.colors.blend(p.red, 0.18, p.dark1) },
		Incoming = { bg = Util.colors.blend(p.green, 0.18, p.dark1) },
		Label = { fg = Util.colors.blend(p.dimmed1, 0.65, p.dark1), italic = true },
	})
end

return M
