--- :checkhealth provider for beast.libs.autopairs.

local M = {}

function M.check()
	local health = vim.health

	-- =========================================================================
	-- Core
	-- =========================================================================
	health.start("beast.libs.autopairs")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required (uses vim.treesitter.get_captures_at_pos)")
		return
	end

	local ok_cfg, config = pcall(require, "beast.libs.autopairs.config")
	if not ok_cfg then
		health.error("Failed to load config: " .. tostring(config))
		return
	end
	health.ok("config loaded")

	local ok_mod, mod = pcall(require, "beast.libs.autopairs")
	if not ok_mod then
		health.error("Failed to load autopairs module: " .. tostring(mod))
		return
	end
	health.ok("autopairs module loaded")

	if vim.g.beast_autopairs_disable then
		health.warn("Disabled globally via vim.g.beast_autopairs_disable")
	else
		health.ok("Not globally disabled")
	end

	if mod.is_installed() then
		health.ok("Mappings installed")
	else
		health.warn("Mappings NOT installed — call autopairs.enable() or trigger InsertEnter")
	end

	-- =========================================================================
	-- API contract
	-- =========================================================================
	health.start("beast.libs.autopairs — API contract")

	for _, name in ipairs({ "setup", "enable", "disable", "toggle", "is_installed" }) do
		if type(mod[name]) == "function" then
			health.ok(name .. "() available")
		else
			health.error(name .. "() missing or wrong type")
		end
	end

	-- =========================================================================
	-- Mappings
	-- =========================================================================
	health.start("beast.libs.autopairs — mappings")

	if not mod.is_installed() then
		health.info("Skipping mapping checks (mappings not installed)")
	else
		local cfg = config.get()
		local checked = 0
		local missing = {}
		for open_char in pairs(cfg.pairs) do
			checked = checked + 1
			if vim.fn.maparg(open_char, "i") == "" then
				missing[#missing + 1] = open_char
			end
		end
		if #missing == 0 then
			health.ok(string.format("All %d open chars mapped in insert mode", checked))
		else
			health.error("Missing insert-mode mappings for: " .. table.concat(missing, " "))
		end

		if cfg.modes.insert then
			if vim.fn.maparg("<BS>", "i") ~= "" then
				health.ok("<BS> mapped in insert")
			else
				health.error("<BS> not mapped despite modes.insert = true")
			end
			if vim.fn.maparg("<CR>", "i") ~= "" then
				health.ok("<CR> mapped in insert")
			else
				health.error("<CR> not mapped despite modes.insert = true")
			end
		end
	end

	-- =========================================================================
	-- Configuration dump
	-- =========================================================================
	health.start("beast.libs.autopairs — configuration")

	local cfg = config.get()
	local pair_count = 0
	for _ in pairs(cfg.pairs) do
		pair_count = pair_count + 1
	end

	health.info(string.format("pairs: %d configured", pair_count))
	health.info(
		string.format("modes: insert=%s command=%s terminal=%s", tostring(cfg.modes.insert), tostring(cfg.modes.command), tostring(cfg.modes.terminal))
	)
	health.info("skip_next:       " .. (cfg.skip_next or "<unset>"))
	health.info("skip_ts:         " .. (cfg.skip_ts and table.concat(cfg.skip_ts, ",") or "<unset>"))
	health.info("skip_unbalanced: " .. tostring(cfg.skip_unbalanced))
	health.info("markdown:        " .. tostring(cfg.markdown))

	-- skip_ts requires a treesitter parser to be effective
	if cfg.skip_ts and #cfg.skip_ts > 0 then
		health.info("skip_ts is active — effective only on buffers with vim.treesitter.start()")
	end
end

return M
