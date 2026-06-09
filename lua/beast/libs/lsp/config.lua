---@class Beast.LSP.Diagnostics.Signs
---@field text? table<integer, string>

---@class Beast.LSP.Diagnostics
---@field virtual_text? boolean|table
---@field severity_sort? boolean
---@field update_in_insert? boolean
---@field underline? boolean
---@field float? table
---@field signs? Beast.LSP.Diagnostics.Signs

---@class Beast.LSP.InlayHints
---@field enabled? boolean

---@class Beast.LSP.Codelens
---@field enabled? boolean
---@field events? string[]  Autocmd events that trigger `vim.lsp.codelens.refresh()`; defaults to BufEnter/CursorHold/InsertLeave when omitted.

---@class Beast.LSP.Fold
---@field enabled? boolean

---@class Beast.LSP.Config
---@field diagnostics? Beast.LSP.Diagnostics
---@field inlay_hints? Beast.LSP.InlayHints
---@field codelens? Beast.LSP.Codelens
---@field fold? Beast.LSP.Fold
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
				[vim.diagnostic.severity.ERROR] = Icon.diagnostics.error,
				[vim.diagnostic.severity.WARN] = Icon.diagnostics.warn,
				[vim.diagnostic.severity.HINT] = Icon.diagnostics.hint,
				[vim.diagnostic.severity.INFO] = Icon.diagnostics.info,
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

---@type Beast.LSP.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.LSP.Config
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
