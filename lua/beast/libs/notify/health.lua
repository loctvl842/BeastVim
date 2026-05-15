local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.notify")

	-- Check Neovim version (floating windows + winblend required)
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for notify floating windows and winblend")
		return
	end

	-- Check config loads
	local ok_cfg, config = pcall(require, "beast.libs.notify.config")
	if not ok_cfg then
		health.error("Failed to load notify config: " .. tostring(config))
		return
	end

	-- Check if notify is registered as vim.notify
	local notify_mod = package.loaded["beast.libs.notify"]
	if notify_mod and vim.notify == notify_mod.notify then
		health.ok("Registered as vim.notify")
	else
		health.warn("Not registered as vim.notify (call require('beast.libs.notify').setup())")
	end

	-- =========================================================================
	-- API contract: vim.notify(msg, level, opts) must behave like the native
	-- =========================================================================
	health.start("beast.libs.notify — API contract")

	local notify_fn = (notify_mod and notify_mod.notify) or vim.notify

	-- Test 1: simple string message
	local ok1, err1 = pcall(notify_fn, "[health] simple string", vim.log.levels.DEBUG)
	if ok1 then
		health.ok("notify(string, level) works")
	else
		health.error("notify(string, level) failed: " .. tostring(err1))
	end

	-- Test 2: multiline string (contains \n)
	local ok2, err2 = pcall(notify_fn, "[health] line1\nline2", vim.log.levels.DEBUG)
	if ok2 then
		health.ok("notify(multiline_string, level) works")
	else
		health.error("notify(multiline_string, level) failed: " .. tostring(err2))
	end

	-- Test 3: level as string name (plugins sometimes pass "info" instead of number)
	local ok3, err3 = pcall(notify_fn, "[health] string level", "DEBUG")
	if ok3 then
		health.ok("notify(msg, 'DEBUG') works (string level)")
	else
		health.error("notify(msg, 'DEBUG') failed: " .. tostring(err3))
	end

	-- Test 4: nil level (should default to INFO)
	local ok4, err4 = pcall(notify_fn, "[health] nil level")
	if ok4 then
		health.ok("notify(msg) works (nil level defaults to INFO)")
	else
		health.error("notify(msg) with nil level failed: " .. tostring(err4))
	end

	-- Test 5: opts table with title (nvim-notify compat)
	local ok5, err5 = pcall(notify_fn, "[health] with opts", vim.log.levels.DEBUG, { title = "HealthCheck" })
	if ok5 then
		health.ok("notify(msg, level, {title=...}) works")
	else
		health.error("notify(msg, level, opts) failed: " .. tostring(err5))
	end

	-- Test 6: returns a record/table (not nil) — some plugins rely on this
	local ok6, result = pcall(notify_fn, "[health] return value", vim.log.levels.DEBUG)
	if ok6 and type(result) == "table" then
		health.ok("notify() returns a record table")
	elseif ok6 then
		health.info(string.format("notify() returns %s (some plugins expect a table)", type(result)))
	else
		health.error("notify() raised: " .. tostring(result))
	end

	-- Dismiss health-check notifications so they don't linger
	if notify_mod and notify_mod.dismiss then
		pcall(notify_mod.dismiss)
	end

	-- =========================================================================
	-- Configuration & environment
	-- =========================================================================
	health.start("beast.libs.notify — configuration")

	health.info(string.format("width = %d", config.width))
	health.info(string.format("timeout = %dms", config.timeout))
	health.info(string.format("anim_ms = %dms", config.anim_ms))
	health.info(string.format("max_height = %d", config.max_height))
	health.info(string.format("gap = %d", config.gap))
	health.info(string.format("stagger = %dms", config.stagger))

	-- Check level filter
	local level_name
	for name, val in pairs(vim.log.levels) do
		if val == config.level then
			level_name = name
			break
		end
	end
	if level_name then
		health.ok(string.format("Minimum level: %s (%d)", level_name, config.level))
	else
		health.warn(string.format("Unknown level value: %s", tostring(config.level)))
	end

	-- Check icons are defined for all levels
	local expected_levels = { "ERROR", "WARN", "INFO", "DEBUG", "TRACE" }
	local missing_icons = {}
	for _, lvl in ipairs(expected_levels) do
		if not config.icons[lvl] or config.icons[lvl] == "" then
			missing_icons[#missing_icons + 1] = lvl
		end
	end
	if #missing_icons == 0 then
		health.ok("Icons defined for all levels")
	else
		health.warn("Missing icons for: " .. table.concat(missing_icons, ", "))
	end

	-- Check highlight groups
	local required_hls = { "BeastNotifyNormal", "BeastNotifyBorder", "BeastNotifyERROR", "BeastNotifyWARN", "BeastNotifyINFO" }
	local missing_hls = {}
	for _, hl_name in ipairs(required_hls) do
		local hl = vim.api.nvim_get_hl(0, { name = hl_name })
		if vim.tbl_isempty(hl) then
			missing_hls[#missing_hls + 1] = hl_name
		end
	end
	if #missing_hls == 0 then
		health.ok("All highlight groups defined")
	else
		health.warn("Missing highlight groups: " .. table.concat(missing_hls, ", "))
	end

	-- Check animate module loads
	local ok_anim, anim_err = pcall(require, "beast.libs.animate")
	if ok_anim then
		health.ok("Animation module available")
	else
		health.error("Failed to load animation module: " .. tostring(anim_err))
	end

	-- Check terminal width is sufficient
	if vim.o.columns < config.width + 4 then
		health.warn(string.format(
			"Terminal width (%d) < notify width (%d + borders) — notifications may clip",
			vim.o.columns,
			config.width
		))
	else
		health.ok(string.format("Terminal width (%d) sufficient for notifications", vim.o.columns))
	end
end

return M
