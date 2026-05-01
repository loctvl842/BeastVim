local M = {}
local p = Palette.get()

Util.colors.set_hl("BeastPacker", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Normal = { bg = p.dark1, fg = p.dimmed1 },
	Border = { fg = p.dark1, bg = p.dark1 },
	WinBar = { bg = p.dark1 },
	Title = { link = "Title" },
	Subtitle = { fg = p.dimmed2, bg = p.dark1 },
	H1 = { link = "IncSearch" },
	H2 = { link = "Bold" },
	Comment = { link = "Comment" },
	TriggerEager = { link = "@character.special" },
	TriggerEvent = { link = "Constant" },
	TriggerKeys = { link = "Statement" },
	TriggerCmd = { link = "Operator" },
	TriggerModule = { link = "Identifier" },
	TriggerFiletype = { link = "Type" },
	TriggerPath = { link = "Directory" },
	Plugin = { link = "Function" },
	Button = { link = "CursorLine" },
	ButtonActive = { link = "Visual" },
	Warning = { link = "WarningMsg" },
	Spinner = { link = "DiagnosticWarn" },
	Success = { link = "DiagnosticOk" },
	Error = { link = "DiagnosticError" },
})

return M
