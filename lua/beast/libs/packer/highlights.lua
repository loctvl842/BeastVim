local M = {}

Util.set_hl("BeastPacker", {
	Normal = { link = "NormalFloat" },
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
})

return M
