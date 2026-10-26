local M = {}

function M.check()
	local health = vim.health
	local messages = require("beast.libs.messages")

	health.start("beast.libs.messages")

	if vim.fn.has("nvim-0.12") == 1 then
		health.ok("Neovim >= 0.12")
	else
		health.warn("Neovim 0.12+ required for ui2: messages use the legacy hit-enter UI")
		return
	end

	if messages.available() then
		health.ok("vim._core.ui2 available")
	else
		health.warn("vim._core.ui2 missing (experimental API changed?): messages use the legacy UI")
		return
	end

	if messages.is_routing() then
		health.ok("Message router installed")
	else
		health.warn("Message router not installed (setup() not called, or no UI attached)")
	end

	if _G.Toast then
		health.ok("Toast available")
	else
		health.warn("Toast not loaded: routed messages are not shown")
	end

	health.info("cmdheight = " .. vim.o.cmdheight)
end

return M
