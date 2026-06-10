local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastToast", {
		Normal = { bg = nil, fg = p.text },
		Body = { fg = p.dimmed2 },
		TitleERROR = { fg = p.accent1 },
		TitleDEBUG = { fg = p.accent2 },
		TitleWARN = { fg = p.accent3 },
		TitleHINT = { fg = p.accent4 },
		TitleINFO = { fg = p.accent5 },
		TitleTRACE = { fg = p.accent6 },
		ProgressTitle = { fg = p.accent5, bold = true },
		ProgressSpinner = { fg = p.accent4 },
		ProgressBarDone = { fg = p.accent3 },
		ProgressBarTodo = { fg = p.dimmed4 },
		ProgressBracket = { fg = p.dimmed3 },
		ProgressPercent = { fg = p.accent2 },
		ProgressMessage = { fg = p.dimmed1 },
		ProgressDone = { fg = p.accent3, bold = true },
	})
end

return M
