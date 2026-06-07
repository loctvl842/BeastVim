-- Diagnostics configuration for the LSP lib.
--
-- Applied once at `lsp.setup()` time. Reads `cfg.diagnostics` from
-- `beast.libs.lsp.config` and forwards it to `vim.diagnostic.config()`.
-- Diagnostics are a global Neovim concern, so no per-buffer logic here.

local config = require("beast.libs.lsp.config")

local M = {}

function M.setup()
	vim.diagnostic.config(config.diagnostics)
end

return M
