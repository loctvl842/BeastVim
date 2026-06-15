---@class Beast.Lsp.Config
local defaults = {
	diagnostics = {
		virtual_text = {
			source = "if_many",
			prefix = "●",
			spacing = 4,
		},
		severity_sort = true,
		update_in_insert = false,
		underline = true,
		float = {
			border = "rounded",
			source = "if_many",
		},
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = (Icon and Icon.diagnostics and Icon.diagnostics.error) or "E",
				[vim.diagnostic.severity.WARN] = (Icon and Icon.diagnostics and Icon.diagnostics.warn) or "W",
				[vim.diagnostic.severity.INFO] = (Icon and Icon.diagnostics and Icon.diagnostics.info) or "I",
				[vim.diagnostic.severity.HINT] = (Icon and Icon.diagnostics and Icon.diagnostics.hint) or "H",
			},
		},
	},
	inlay_hints = {
		enabled = false,
	},
	codelens = {
		enabled = false,
	},
	fold = {
		-- When the attached client supports textDocument/foldingRange, set
		-- foldexpr=v:lua.vim.lsp.foldexpr() on the buffer's windows. Fires
		-- after FileType so it overrides treesitter's foldexpr when both
		-- are configured. Treesitter remains the fallback for buffers
		-- without an LSP server (or without foldingRange support).
		enabled = true,
	},
}

---@type Beast.Lsp.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Lsp.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.lsp.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
