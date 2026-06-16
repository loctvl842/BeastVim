local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.treesitter")

	-- Check Neovim version
	if vim.fn.has("nvim-0.12") == 1 then
		health.ok("Neovim >= 0.12")
	else
		health.error("Neovim 0.12+ required for builtin treesitter support")
		return
	end

	-- Check module loaded
	local ts = package.loaded["beast.libs.treesitter"]
	if ts and ts.enabled then
		health.ok("Treesitter library enabled")
	else
		health.warn("Treesitter library not enabled (call require('beast.libs.treesitter').enable())")
	end

	-- Check config
	local ok_cfg, config = pcall(require, "beast.libs.treesitter.config")
	if not ok_cfg then
		health.error("Failed to load treesitter config")
		return
	end

	health.info(string.format("highlight.enable = %s", tostring(config.highlight.enable)))
	health.info(string.format("fold.enable = %s", tostring(config.fold.enable)))

	-- Sticky context
	health.info(string.format("context.enable = %s", tostring(config.context.enable)))
	local ctx = package.loaded["beast.libs.treesitter.context"]
	if ctx and ctx.enabled then
		health.ok("Sticky context enabled")
	elseif config.context.enable then
		health.warn("Sticky context configured but not yet enabled (enables on first treesitter activation)")
	else
		health.info("Sticky context disabled")
	end
	local langs = require("beast.libs.treesitter.context.query").languages()
	if #langs == 0 then
		health.info("No context query files installed yet (downloaded on demand per language)")
	else
		health.info(string.format("Context queries installed for %d languages: %s", #langs, table.concat(langs, ", ")))
	end

	-- Check ensure_installed parsers
	local ensure = config.ensure_installed
	if #ensure == 0 then
		health.info("ensure_installed is empty (using only pre-installed parsers)")
	else
		for _, lang in ipairs(ensure) do
			local has = pcall(vim.treesitter.language.inspect, lang)
			if has then
				health.ok(string.format("Parser available: %s", lang))
			else
				health.warn(string.format("Parser missing: %s (will install on FileType)", lang))
			end
		end
	end

	-- Check tree-sitter CLI availability
	if vim.fn.executable("tree-sitter") == 1 then
		health.ok("tree-sitter CLI found")
	else
		health.warn("tree-sitter CLI not found (needed for parser compilation)")
	end

	-- Check C compiler availability
	if vim.fn.executable("cc") == 1 or vim.fn.executable("gcc") == 1 or vim.fn.executable("clang") == 1 then
		health.ok("C compiler found")
	else
		health.warn("No C compiler found (cc/gcc/clang — needed for parser compilation)")
	end
end

return M
