-- LspAttach dispatcher for the LSP lib.
--
-- Owns the `BeastVim-lsp` augroup (intentionally separate from
-- `BeastVim-root_cache` in beast/util/root.lua so the two LspAttach
-- listeners don't trample each other).
--
-- Single autocmd dispatches to:
--   1. Per-server `keys` (buffer-local, capability-gated) — registered via `lsp.register`
--   2. Per-server `on_attach(client, bufnr)` — registered via `lsp.register`
--   3. Global subscribers — registered via `lsp.on_attach(fn)`, in registration order
--
-- Order matters: per-server runs first so subscribers observe a fully
-- initialized server state.

local M = {}

local View = require("beast.libs.view")

---@class Beast.LSP.Registered
---@field keys? table[] Buffer-local keymap specs (see keys.lua)
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer)

---@type table<string, Beast.LSP.Registered>
M.servers = {}

---@type fun(client: vim.lsp.Client, bufnr: integer)[]
M.subscribers = {}

local augroup

---Store the BeastVim-extension fields for a server. The native LSP fields
---are handled by `vim.lsp.config()` directly; this table only holds what
---the dispatcher needs at attach time.
---@param name string
---@param extras Beast.LSP.Registered
function M.register_server(name, extras)
	M.servers[name] = extras
end

---Add a global LspAttach subscriber. Runs after per-server handlers.
---@param fn fun(client: vim.lsp.Client, bufnr: integer)
function M.subscribe(fn)
	table.insert(M.subscribers, fn)
end

---Apply LSP foldexpr to all windows currently showing `buf` if the client
---supports `textDocument/foldingRange`. No-op if disabled in config or
---unsupported by the server. Fires from `LspAttach`, so it overrides
---whatever foldexpr was set earlier on `FileType` (e.g. treesitter's).
---@param client vim.lsp.Client
---@param buf integer
local function apply_fold(client, buf)
	local cfg = require("beast.libs.lsp.config")
	if not (cfg.fold and cfg.fold.enabled) then
		return
	end
	if not client:supports_method("textDocument/foldingRange") then
		return
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			View.win.wo(win, "foldmethod", "expr")
			View.win.wo(win, "foldexpr", "v:lua.vim.lsp.foldexpr()")
		end
	end
end

---Install the single dispatching autocmd. Idempotent — re-creates the
---augroup with `clear = true` on each call.
function M.setup()
	augroup = vim.api.nvim_create_augroup("BeastVim-lsp", { clear = true })

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if not client then
				return
			end

			local server = M.servers[client.name]
			if server then
				if server.keys then
					require("beast.libs.lsp.keys").bind(server.keys, client, ev.buf)
				end
				if server.on_attach then
					server.on_attach(client, ev.buf)
				end
			end

			apply_fold(client, ev.buf)

			for _, fn in ipairs(M.subscribers) do
				fn(client, ev.buf)
			end
		end,
	})
end

return M
