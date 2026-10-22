local M = {}

function M.check()
	local health = vim.health
	health.start("beast.libs.review")

	if vim.fn.has("nvim-0.11") == 1 then
		health.ok("Neovim >= 0.11")
	else
		health.error("Neovim >= 0.11 is required")
	end

	if pcall(require, "bit") then
		health.ok("LuaJIT `bit` library available (WebSocket handshake needs SHA-1)")
	else
		health.error("LuaJIT `bit` library missing")
	end

	local lockfile = require("beast.libs.review.server.lockfile")
	local dir = lockfile.dir()
	if vim.fn.isdirectory(dir) == 0 then
		health.info("Lock directory will be created on start: " .. dir)
	elseif vim.fn.filewritable(dir) == 2 then
		health.ok("Lock directory writable: " .. dir)
	else
		health.error("Lock directory not writable: " .. dir)
	end

	if lockfile.token() then
		health.ok("Secure random source available")
	else
		health.error("No secure random source: the server refuses to start without one")
	end

	local status = require("beast.libs.review").status()
	if status.running then
		health.ok(("Listening on 127.0.0.1:%d (%d client%s)"):format(status.port, status.clients, status.clients == 1 and "" or "s"))
	else
		health.info("Server not running (`:Review start`, or set `enabled = true`)")
	end
end

return M
