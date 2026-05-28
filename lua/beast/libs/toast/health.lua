local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.toast")

	-- Check Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for toast floating windows and winblend")
		return
	end

	-- Check config loads
	local ok_cfg, config = pcall(require, "beast.libs.toast.config")
	if not ok_cfg then
		health.error("Failed to load toast config: " .. tostring(config))
		return
	end

	-- Check module loaded
	local toast_mod = package.loaded["beast.libs.toast"]
	if toast_mod then
		health.ok("Toast module loaded")
	else
		health.warn("Toast module not loaded (require('beast.libs.toast').setup() not called)")
	end

	-- =========================================================================
	-- API contract: toast(msg, level, opts) must work correctly
	-- =========================================================================
	health.start("beast.libs.toast — API contract")

	local toast_fn = toast_mod and toast_mod.toast
	if not toast_fn then
		health.error("toast.toast() function not available — cannot run API tests")
		return
	end

	-- Test 1: simple string message
	local ok1, err1 = pcall(toast_fn, "[health] simple string", vim.log.levels.DEBUG)
	if ok1 then
		health.ok("toast(string, level) works")
	else
		health.error("toast(string, level) failed: " .. tostring(err1))
	end

	-- Test 2: multiline message (collapses to single line)
	local ok2, err2 = pcall(toast_fn, "[health] line1\nline2", vim.log.levels.DEBUG)
	if ok2 then
		health.ok("toast(multiline_string, level) works (collapses to single line)")
	else
		health.error("toast(multiline_string, level) failed: " .. tostring(err2))
	end

	-- Test 3: table message (array of lines)
	local ok3, err3 = pcall(toast_fn, { "[health]", "table msg" }, vim.log.levels.DEBUG)
	if ok3 then
		health.ok("toast(string[], level) works")
	else
		health.error("toast(string[], level) failed: " .. tostring(err3))
	end

	-- Test 4: string level name
	local ok4, err4 = pcall(toast_fn, "[health] string level", "DEBUG")
	if ok4 then
		health.ok("toast(msg, 'DEBUG') works (string level)")
	else
		health.error("toast(msg, 'DEBUG') failed: " .. tostring(err4))
	end

	-- Test 5: nil level (defaults to INFO)
	local ok5, err5 = pcall(toast_fn, "[health] nil level")
	if ok5 then
		health.ok("toast(msg) works (nil level defaults to INFO)")
	else
		health.error("toast(msg) with nil level failed: " .. tostring(err5))
	end

	-- Test 6: opts table with title and dim
	local ok6, err6 = pcall(toast_fn, "[health] with opts", vim.log.levels.DEBUG, { title = "Health", dim = true })
	if ok6 then
		health.ok("toast(msg, level, {title=..., dim=...}) works")
	else
		health.error("toast(msg, level, opts) failed: " .. tostring(err6))
	end

	-- Test 7: returns a record table
	local ok7, result = pcall(toast_fn, "[health] return value", vim.log.levels.DEBUG)
	if ok7 and type(result) == "table" then
		health.ok("toast() returns a record table")
	elseif ok7 then
		health.info(string.format("toast() returns %s (expected table)", type(result)))
	else
		health.error("toast() raised: " .. tostring(result))
	end

	-- Test 8: __call metamethod on module
	if toast_mod then
		local ok8, err8 = pcall(toast_mod, "[health] __call test", vim.log.levels.DEBUG)
		if ok8 then
			health.ok("Module __call metamethod works")
		else
			health.error("Module __call failed: " .. tostring(err8))
		end
	end

	-- Dismiss health-check toasts
	if toast_mod and toast_mod.dismiss then
		pcall(toast_mod.dismiss)
	end

	-- =========================================================================
	-- Configuration & environment
	-- =========================================================================
	health.start("beast.libs.toast — configuration")

	health.info(string.format("timeout = %dms", config.timeout))
	health.info(string.format("anim_ms = %dms", config.anim_ms))
	health.info(string.format("gap = %d", config.gap))
	health.info(string.format("stagger = %dms", config.stagger))
	health.info(string.format("margin_bottom = %d", config.margin_bottom))

	local max_w = type(config.max_width) == "function" and config.max_width() or config.max_width
	health.info(string.format("max_width = %d (current)", max_w))

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

	-- Check icons for all levels
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

	-- Check highlight groups referenced in config.hl
	local missing_hls = {}
	for lvl, hl_pair in pairs(config.hl) do
		for _, hl_name in pairs(hl_pair) do
			local hl = vim.api.nvim_get_hl(0, { name = hl_name })
			if vim.tbl_isempty(hl) then
				missing_hls[#missing_hls + 1] = hl_name .. " (" .. lvl .. ")"
			end
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

	-- Check terminal width vs max_width
	if vim.o.columns < max_w then
		health.warn(string.format("Terminal width (%d) < max_width (%d) — toasts may clip", vim.o.columns, max_w))
	else
		health.ok(string.format("Terminal width (%d) sufficient for toasts", vim.o.columns))
	end
end

return M
