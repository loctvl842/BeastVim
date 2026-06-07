-- :checkhealth for the LSP lib.
-- Reports Neovim version, registered servers, attached clients on the
-- current buffer, and capability contributor count.

local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.lsp")

	-- Neovim version
	if vim.fn.has("nvim-0.12") == 1 then
		health.ok("Neovim >= 0.12")
	elseif vim.fn.has("nvim-0.11") == 1 then
		health.warn("Neovim 0.11 detected (>= 0.12 recommended for vim.lsp.enable improvements)")
	else
		health.error("Neovim 0.11+ required for vim.lsp.config / vim.lsp.enable")
		return
	end

	-- Lib initialized?
	local ok_init, lsp = pcall(require, "beast.libs.lsp")
	if not (ok_init and lsp._initialized) then
		health.warn("LSP lib not initialized (call require('beast.libs.lsp').setup())")
		return
	end
	health.ok("LSP lib initialized")

	-- Registered servers
	local ok_disp, disp = pcall(require, "beast.libs.lsp.attach")
	if not ok_disp then
		health.error("Failed to load LspAttach dispatcher")
		return
	end

	local names = vim.tbl_keys(disp.servers)
	table.sort(names)

	if #names == 0 then
		health.info("No servers registered yet (call Lsp.register(name, cfg))")
	else
		health.info(string.format("Registered servers (%d):", #names))
		for _, name in ipairs(names) do
			local cfg = vim.lsp.config[name]
			local cmd = cfg and cfg.cmd
			local exe = type(cmd) == "table" and cmd[1] or nil
			if exe and vim.fn.executable(exe) == 1 then
				health.ok(string.format("  %s — cmd[1]=%q on $PATH", name, exe))
			elseif exe then
				health.warn(string.format("  %s — cmd[1]=%q not found on $PATH", name, exe))
			else
				health.info(string.format("  %s — non-executable cmd (function?)", name))
			end
		end
	end

	-- Subscriber count
	health.info(string.format("Global LspAttach subscribers: %d", #disp.subscribers))

	-- Capability contributors
	local ok_caps, caps = pcall(require, "beast.libs.lsp.capabilities")
	if ok_caps then
		health.info(string.format("Capability contributors: %d", #caps.contributors))
	end

	-- Attached clients on current buffer
	local buf = vim.api.nvim_get_current_buf()
	local clients = vim.lsp.get_clients({ bufnr = buf })
	if #clients == 0 then
		health.info(string.format("No clients attached to current buffer (buf=%d)", buf))
	else
		health.ok(string.format("Clients attached to current buffer (buf=%d):", buf))
		for _, c in ipairs(clients) do
			health.info(string.format("  %s (id=%d)", c.name, c.id))
		end
	end
end

return M
