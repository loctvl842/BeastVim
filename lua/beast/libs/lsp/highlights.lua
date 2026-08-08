-- Highlight groups consumed by `vim.lsp.buf.document_highlight()`. Neovim
-- does not skip drawing these when unstyled, so they must be defined or the
-- highlight is invisible.

local M = {}

function M.get()
	local p = Theme.get()
	return {
		LspReferenceText = { bg = p.dark2 },
		LspReferenceRead = { bg = p.dark2 },
		LspReferenceWrite = { bg = p.dark2, underline = true },
	}
end

return M
