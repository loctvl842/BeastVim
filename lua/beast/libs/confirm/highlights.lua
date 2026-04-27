local M = {}

Util.set_hl("BeastConfirm", {
	Backdrop = { bg = "#000000", fg = "#000000" },
	Normal = { link = "NormalFloat" },
	Border = { link = "FloatBorder" },
	Button = { link = "Normal" },
	ButtonActive = { link = "PmenuSel" },
})

return M
