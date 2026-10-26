local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.searchcount")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for ephemeral end-of-line virtual text")
		return
	end

	if vim.fn.exists("*searchcount") == 1 then
		health.ok("searchcount() available")
	else
		health.error("searchcount() missing")
	end

	local sm = vim.o.shortmess
	if sm:find("S", 1, true) and sm:find("s", 1, true) then
		health.ok("shortmess has S and s (native count and wrap messages silenced)")
	else
		health.warn("shortmess lacks S and/or s: native `[n/m]` / wrap messages will duplicate the count and toast")
	end

	if _G.Toast then
		health.ok("Toast available")
	else
		health.warn("Toast not loaded: not-found and wrap messages will not show")
	end
end

return M
