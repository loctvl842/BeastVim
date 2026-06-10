local M = {}

function M.get()
	local p = Theme.get()
	return Util.colors.build("BeastNotify", {
		Border = { bg = p.dimmed5, fg = p.background },
		Normal = { bg = p.dimmed5, fg = p.dimmed2 },

		ERROR = { link = "DiagnosticError" },
		WARN = { link = "DiagnosticWarn" },
		INFO = { link = "DiagnosticInfo" },
		DEBUG = { link = "DiagnosticHint" },
		TRACE = { link = "Comment" },
	})
end

return M
