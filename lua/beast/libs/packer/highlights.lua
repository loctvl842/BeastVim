local M = {}

Util.colors.set_hl("BeastPacker", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Normal = { link = "@markup.raw.block.markdown" },
	Title = { link = "Title" },
  FloatBorder = { link = "@markup.raw.delimiter.markdown" },
	H1 = { link = "IncSearch" },
	H2 = { link = "Bold" },
	Comment = { link = "Comment" },
	Special = { link = "@character.special" },
	Event = { link = "Constant" },
	Keys = { link = "Statement" },
	Cmd = { link = "Operator" },
	Module = { link = "Identifier" },
	Filetype = { link = "Type" },
	Path = { link = "Directory" },
	Plugin = { link = "Function" },
	Button = { link = "CursorLine" },
	ButtonActive = { link = "Visual" },
	Warning = { link = "WarningMsg" },
	Spinner = { link = "DiagnosticWarn" },
	Success = { link = "DiagnosticOk" },
	Error = { link = "DiagnosticError" },
})

return M
