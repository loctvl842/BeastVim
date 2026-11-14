local M = {}

function M.get()
	local p = Theme.get()
	-- ui2 windows map Normal to MsgArea; unset, they fall back to the terminal's default colors.
	return vim.tbl_extend(
		"error",
		Util.colors.build("", {
			MsgArea = { link = "Normal" },
		}),
		Util.colors.build("BeastMessages", {
			-- ui2 message window: same look as a toast body (no float background).
			Msg = { fg = p.dimmed2 },
		})
	)
end

return M
