-- Highlight groups consumed by `vim.lsp.buf.document_highlight()`. Neovim
-- does not skip drawing these when unstyled, so they must be defined or the
-- highlight is invisible.

local M = {}

function M.get()
	local p = Theme.get()
	if Theme.kind() == "plugin" then return end
	local blend = Util.colors.blend
  local bg = blend(p.text, 0.2, p.background)

	return {
		LspReferenceText = { bg = bg },
		LspReferenceRead = { bg = bg },
		LspReferenceWrite = { bg = bg },
	}
end

return M
