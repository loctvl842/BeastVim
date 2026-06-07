-- Per-server buffer-local keymap binding.
--
-- Called by the LspAttach dispatcher when a server with `keys = {...}`
-- attaches to a buffer. Each entry is bound via `Key.safe_set` so it shows
-- up in the cheatsheet.
--
-- Entry shape: { lhs, rhs, desc?, mode?, group?, cond? }
--   - cond: optional string (LSP method name). If set, the keymap is
--     only bound when `client:supports_method(cond)` returns true.
--     This prevents binding `gd` when the server lacks `textDocument/definition`.

local M = {}

---@class Beast.LSP.KeySpec
---@field [1] string       Left-hand side
---@field [2] string|function Right-hand side
---@field desc? string
---@field mode? string|string[]
---@field group? string
---@field cond? string LSP method name; skip binding if unsupported

---@param keys Beast.LSP.KeySpec[]
---@param client vim.lsp.Client
---@param bufnr integer
function M.bind(keys, client, bufnr)
	for _, spec in ipairs(keys) do
		if not spec.cond or client:supports_method(spec.cond) then
			Key.safe_set(spec.mode or "n", spec[1], spec[2], {
				buffer = bufnr,
				desc = spec.desc,
				group = spec.group or "LSP",
			})
		end
	end
end

return M
