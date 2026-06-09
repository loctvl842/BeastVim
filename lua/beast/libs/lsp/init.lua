-- BeastVim LSP infrastructure library.
--
-- Thin wrapper over Neovim 0.12's `vim.lsp.config` + `vim.lsp.enable` +
-- `LspAttach`. The lib owns POLICY (diagnostics, capabilities, keymap
-- dispatch); it does NOT own per-server knowledge — server configs are
-- registered by callers (typically future `BeastVim/<Lang>` extensions)
-- via `M.register(name, cfg)`.
--
-- See docs/dev-specs/lsp-library.md for the design rationale.

local config = require("beast.libs.lsp.config")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "lsp", description = "LSP configuration and lifecycle infrastructure" }

M._initialized = false

-- BeastVim-specific fields that are NOT part of vim.lsp.Config and must be
-- stripped before passing to `vim.lsp.config()`. They are forwarded to the
-- attach dispatcher instead.
local BEAST_FIELDS = { keys = true, on_attach = true }

---Split a registration spec into the native `vim.lsp.Config` fields and the
---BeastVim extension fields (`keys`, `on_attach`).
---@param cfg table
---@return table lsp_cfg
---@return table extras
local function split_spec(cfg)
	local lsp_cfg, extras = {}, {}
	for k, v in pairs(cfg) do
		if BEAST_FIELDS[k] then
			extras[k] = v
		else
			lsp_cfg[k] = v
		end
	end
	return lsp_cfg, extras
end

---Build a multi-line summary of LSP state focused on the current buffer.
---@return string
local function build_info()
	local buf = vim.api.nvim_get_current_buf()
	local disp = require("beast.libs.lsp.attach")
	local caps = require("beast.libs.lsp.capabilities")
	local lines = {}

	local servers = vim.tbl_keys(disp.servers)
	table.sort(servers)
	table.insert(lines, string.format("Registered servers (%d): %s", #servers, table.concat(servers, ", ")))
	table.insert(lines, string.format("Global subscribers: %d", #disp.subscribers))
	table.insert(lines, string.format("Capability contributors: %d", #caps.contributors))
	table.insert(lines, "")

	local clients = vim.lsp.get_clients({ bufnr = buf })
	if #clients == 0 then
		table.insert(lines, string.format("No clients attached to buffer %d", buf))
	else
		table.insert(lines, string.format("Clients attached to buffer %d:", buf))
		for _, c in ipairs(clients) do
			local root = c.root_dir or "(none)"
			table.insert(lines, string.format("  • %s (id=%d) root=%s", c.name, c.id, root))
		end
	end

	return table.concat(lines, "\n")
end

local function install_commands()
	vim.api.nvim_create_user_command("BeastLspInfo", function()
		vim.notify(build_info(), vim.log.levels.INFO, { title = "BeastVim LSP" })
	end, { desc = "Show BeastVim LSP state for current buffer" })
end

---Initialize the LSP lib. Idempotent.
---@param opts? Beast.LSP.Config
function M.setup(opts)
	if M._initialized then
		return
	end
	M._initialized = true

	config.setup(opts)
	require("beast.libs.lsp.diagnostics").setup()
	require("beast.libs.lsp.attach").setup()
	install_commands()
end

---Register an LSP server. Merges the spec into `vim.lsp.config(name, ...)`
---and enables it via `vim.lsp.enable(name)`.
---
---Accepts the full `vim.lsp.Config` shape plus BeastVim extensions:
---  - `keys`      — buffer-local keymaps bound on LspAttach (see keys.lua)
---  - `on_attach` — per-server hook, runs before global subscribers
---
---If `capabilities` is omitted, the merged result of `M.capabilities()` is used.
---@param name string
---@param cfg table
function M.register(name, cfg)
	local lsp_cfg, extras = split_spec(cfg or {})

	if lsp_cfg.capabilities == nil then
		lsp_cfg.capabilities = M.capabilities()
	end

	vim.lsp.config(name, lsp_cfg)
	vim.lsp.enable(name)

	require("beast.libs.lsp.attach").register_server(name, extras)
end

---Merged client capabilities (base + all contributors).
---@return table
function M.capabilities()
	return require("beast.libs.lsp.capabilities").get()
end

---Register an additional capabilities contribution. Accepts a table or a
---function returning a table.
---@param contrib table|fun(): table
function M.add_capabilities(contrib)
	require("beast.libs.lsp.capabilities").add(contrib)
end

---Subscribe to LspAttach. The callback runs after per-server handlers.
---@param fn fun(client: vim.lsp.Client, bufnr: integer)
function M.on_attach(fn)
	require("beast.libs.lsp.attach").subscribe(fn)
end

return M
