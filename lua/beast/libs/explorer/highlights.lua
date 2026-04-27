local M = {}

Util.set_hl("BeastExplorer", {
	Normal = { link = "Directory" },
	Title = { link = "@punctuation.special" },
	Dir = { link = "Directory" },
	File = { link = "@punctuation.special" },
	Indent = { link = "Whitespace" },
	Comment = { link = "Comment" },
	Clip = { link = "@punctuation.special" },
})

return M
