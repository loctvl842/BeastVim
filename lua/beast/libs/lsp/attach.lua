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

---@type table<string, Beast.Lsp.Registered>
M.servers = {}

---@type fun(client: vim.lsp.Client, bufnr: integer)[]
M.subscribers = {}

local augroup
-- Reference to the wrapped registerCapability handler so re-running setup()
-- (after `package.loaded[...] = nil`) doesn't chain wrappers on top of an
-- already-wrapped handler. Compared by identity.
local register_capability_handler

---@class Beast.Lsp.KeySpec : Beast.KeymapSpec
---@field cond? string LSP method (e.g. "textDocument/definition") gating bind

---@class Beast.Lsp.Registered
---@field keys? Beast.Lsp.KeySpec[]|Beast.Lsp.KeySpec Buffer-local keymap specs; single spec or array
---@field on_attach? fun(client: vim.lsp.Client, bufnr: integer)

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

---Enable buffer-scoped inlay hints when the client supports them.
---@param client vim.lsp.Client
---@param buf integer
local function apply_inlay_hints(client, buf)
	local cfg = require("beast.libs.lsp.config")
	if not (cfg.inlay_hints and cfg.inlay_hints.enabled) then
		return
	end
	if not client:supports_method("textDocument/inlayHint") then
		return
	end
	vim.lsp.inlay_hint.enable(true, { bufnr = buf })
end

---Enable buffer-scoped code lens when the client supports it.
---`vim.lsp.codelens.enable` wires up auto-refresh internally and is
---idempotent per (buffer, client), so no arming flag is needed.
---@param client vim.lsp.Client
---@param buf integer
local function apply_codelens(client, buf)
	local cfg = require("beast.libs.lsp.config")
	if not (cfg.codelens and cfg.codelens.enabled) then
		return
	end
	if not client:supports_method("textDocument/codeLens") then
		return
	end
	vim.lsp.codelens.enable(true, { bufnr = buf })
end

---Run the per-attach side-effects (fold/inlay/codelens) for a given
---(client, buffer). Extracted so we can re-apply on dynamic capability
---registration as well as on LspAttach.
---@param client vim.lsp.Client
---@param buf integer
local function apply_capabilities(client, buf)
	apply_fold(client, buf)
	apply_inlay_hints(client, buf)
	apply_codelens(client, buf)
end

---Store the BeastVim-extension fields for a server. The native LSP fields
---are handled by `vim.lsp.config()` directly; this table only holds what
---the dispatcher needs at attach time.
---@param name string
---@param extras Beast.Lsp.Registered
function M.register_server(name, extras)
	M.servers[name] = extras
end

---Add a global LspAttach subscriber. Runs after per-server handlers.
---@param fn fun(client: vim.lsp.Client, bufnr: integer)
function M.subscribe(fn)
	table.insert(M.subscribers, fn)
end

---Install the single dispatching autocmd. Idempotent — re-creates the
---augroup with `clear = true` on each call, and wraps the
---`client/registerCapability` handler exactly once across the process.
function M.setup()
	augroup = vim.api.nvim_create_augroup("BeastVim-lsp", { clear = true })

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if not client then
				return
			end

			require("beast.libs.lsp.capabilities").first_client_seen = true

			local server = M.servers[client.name]
			if server then
				if server.keys then
					-- Normalize to an array: callers may pass a single spec.
					---@type Beast.Lsp.KeySpec[]
					local specs = (type(server.keys[1]) == "table") and server.keys or { server.keys }
					for _, spec in ipairs(specs) do
						if not spec.cond or client:supports_method(spec.cond) then
							Key.safe_set(spec.mode or "n", spec[1], spec[2], {
								buffer = ev.buf,
								desc = spec.desc,
								group = spec.group or "LSP",
							})
						end
					end
				end
				if server.on_attach then
					server.on_attach(client, ev.buf)
				end
			end

			apply_capabilities(client, ev.buf)

			for _, fn in ipairs(M.subscribers) do
				fn(client, ev.buf)
			end
		end,
	})

	-- Some servers (tsserver/vtsls, denols, eslint, …) announce capabilities
	-- like codeLens or inlayHint *after* the initial handshake via
	-- `client/registerCapability`. Re-apply the capability-gated side-effects
	-- so those features aren't silently missed.
	--
	-- Reload-safe: if the currently-installed handler is the one we wrapped
	-- last time, don't wrap it again (avoids stacked wrappers on reload).
	if vim.lsp.handlers["client/registerCapability"] ~= register_capability_handler then
		local default_register = vim.lsp.handlers["client/registerCapability"]
		register_capability_handler = function(err, res, ctx)
			local ret = default_register(err, res, ctx)
			local client = vim.lsp.get_client_by_id(ctx.client_id)
			if client then
				for buf in pairs(client.attached_buffers) do
					apply_capabilities(client, buf)
				end
			end
			return ret
		end
		vim.lsp.handlers["client/registerCapability"] = register_capability_handler
	end
end

return M
