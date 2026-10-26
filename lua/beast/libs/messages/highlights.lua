local M = {}

function M.get()
	-- ui2 windows map Normal to MsgArea; unset, they fall back to the terminal's default colors.
	return Util.colors.build("", {
		MsgArea = { link = "Normal" },
	})
end

return M
