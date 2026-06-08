---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "RecordingEnter", "RecordingLeave" },
	scope = "global",
	priority = 95,
	provider = function()
		local reg = vim.fn.reg_recording()
		if reg == "" then
			return {}
		end
		return {
			{ text = "● REC ", hl = { fg = "accent1", bold = true } },
			{ text = "@" .. reg, hl = { fg = "accent2", bold = true } },
			{ text = " ", hl = { fg = "text" } },
		}
	end,
}
