local M = {}

function M.setup()
	vim.api.nvim_set_hl(0, "BeastInputBorder", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "BeastInputTitle", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "BeastInputNormal", { link = "Normal", default = true })
	vim.api.nvim_set_hl(0, "BeastInputIcon", { link = "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "BeastInputPrompt", { link = "BeastInputTitle", default = true })
end

return M
