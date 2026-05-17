local M = {}

-- Thresholds aligned with scripts/bench-tabline.lua
local FAIL_THRESHOLD_US = 1000 -- 1 ms — hard fail
local WARN_THRESHOLD_US = 50 -- soft target — anything slower is suspicious
local BENCH_RENDERS = 500

function M.check()
	local health = vim.health

	health.start("beast.libs.tabline")

	-- Check Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for tabline features")
		return
	end

	-- Check config loads
	local ok_cfg, config = pcall(require, "beast.libs.tabline.config")
	if not ok_cfg then
		health.error("Failed to load tabline config: " .. tostring(config))
		return
	end

	-- Check module loaded and setup called
	local tabline = package.loaded["beast.libs.tabline"]
	if tabline then
		health.ok("Tabline module loaded")
	else
		health.warn("Tabline module not loaded (require('beast.libs.tabline').setup() not called)")
	end

	-- Check if registered as vim.o.tabline
	if vim.o.tabline:find("beast.libs.tabline") then
		health.ok("Registered as vim.o.tabline provider")
	else
		health.warn("Not registered as tabline provider (vim.o.tabline does not reference beast)")
	end

	-- =========================================================================
	-- API contract: render() must return a string
	-- =========================================================================
	health.start("beast.libs.tabline — API contract")

	if not tabline then
		health.error("Module not loaded — cannot run API tests")
	else
		-- Test 1: render returns a string
		local ok1, result = pcall(tabline.render)
		if ok1 and type(result) == "string" then
			health.ok("render() returns a string")
		elseif ok1 then
			health.error(string.format("render() returned %s (expected string)", type(result)))
		else
			health.error("render() raised: " .. tostring(result))
		end

		-- Test 2: render produces non-empty output
		if ok1 and type(result) == "string" and #result > 0 then
			health.ok(string.format("render() produces output (%d chars)", #result))
		elseif ok1 then
			health.warn("render() returned empty string (no buffers listed?)")
		end

		-- Test 3: public API helpers exist
		local helpers = { "goto_buffer", "cycle_next", "cycle_prev", "move_next", "move_prev", "get_visible_buffers", "get_truncation_counts" }
		local missing_helpers = {}
		for _, name in ipairs(helpers) do
			if type(tabline[name]) ~= "function" then
				missing_helpers[#missing_helpers + 1] = name
			end
		end
		if #missing_helpers == 0 then
			health.ok("All public API helpers available")
		else
			health.warn("Missing helpers: " .. table.concat(missing_helpers, ", "))
		end

		-- Test 4: get_visible_buffers returns a table
		local ok4, visible = pcall(tabline.get_visible_buffers)
		if ok4 and type(visible) == "table" then
			health.ok(string.format("get_visible_buffers() returns %d buffers", #visible))
		elseif ok4 then
			health.error(string.format("get_visible_buffers() returned %s (expected table)", type(visible)))
		else
			health.error("get_visible_buffers() raised: " .. tostring(visible))
		end
	end

	-- =========================================================================
	-- Submodules
	-- =========================================================================
	health.start("beast.libs.tabline — submodules")

	local submodules = {
		"beast.libs.tabline.buffers",
		"beast.libs.tabline.context",
		"beast.libs.tabline.icons",
		"beast.libs.tabline.name",
		"beast.libs.tabline.truncate",
		"beast.libs.tabline.sections.buffer_list",
		"beast.libs.tabline.sections.cell",
		"beast.libs.tabline.sections.offset",
		"beast.libs.tabline.sections.tabpages",
	}

	local failed_modules = {}
	for _, mod_name in ipairs(submodules) do
		local ok, err = pcall(require, mod_name)
		if not ok then
			failed_modules[#failed_modules + 1] = string.format("%s: %s", mod_name, tostring(err))
		end
	end
	if #failed_modules == 0 then
		health.ok("All submodules load without error")
	else
		for _, msg in ipairs(failed_modules) do
			health.error("Failed to load — " .. msg)
		end
	end

	-- Verify context.build works
	local ok_ctx, context = pcall(require, "beast.libs.tabline.context")
	if ok_ctx then
		local ok_build, build_err = pcall(context.build, {
			last_active_bufnr = vim.api.nvim_get_current_buf(),
			dirty = true,
		})
		if ok_build then
			health.ok("context.build() executes without error")
		else
			health.error("context.build() failed: " .. tostring(build_err))
		end
	end

	-- Verify buffers.list works
	local ok_bufs, buffers_mod = pcall(require, "beast.libs.tabline.buffers")
	if ok_bufs then
		local ok_list, listed = pcall(buffers_mod.list)
		if ok_list and type(listed) == "table" then
			health.ok(string.format("buffers.list() returns %d listed buffers", #listed))
		elseif ok_list then
			health.error("buffers.list() did not return a table")
		else
			health.error("buffers.list() failed: " .. tostring(listed))
		end
	end

	-- =========================================================================
	-- Render performance (inline bench)
	-- =========================================================================
	health.start("beast.libs.tabline — performance")

	if not tabline or not tabline.render then
		health.warn("Cannot benchmark — module not loaded")
	else
		-- Warm up
		for _ = 1, 10 do
			tabline.render()
		end

		-- Cold render (invalidate each time — worst case)
		if tabline._invalidate then
			collectgarbage("collect")
			local t0 = vim.uv.hrtime()
			for _ = 1, BENCH_RENDERS do
				tabline._invalidate()
				tabline.render()
			end
			local elapsed_ns = vim.uv.hrtime() - t0
			local cold_us = elapsed_ns / 1e3 / BENCH_RENDERS

			health.info(string.format("Cold bench: %.2f µs/render (mean of %d renders, invalidated each time)", cold_us, BENCH_RENDERS))

			if cold_us > FAIL_THRESHOLD_US then
				health.error(string.format(
					"FAIL: %.2f µs/render exceeds hard threshold (%d µs). Run `nvim --headless -l scripts/bench-tabline.lua` for details.",
					cold_us,
					FAIL_THRESHOLD_US
				))
			elseif cold_us > WARN_THRESHOLD_US then
				health.warn(string.format(
					"%.2f µs/render exceeds soft target (%d µs) — investigate with `nvim --headless -l scripts/bench-tabline.lua`",
					cold_us,
					WARN_THRESHOLD_US
				))
			else
				health.ok(string.format("Cold render: %.2f µs — within budget", cold_us))
			end
		end

		-- Hot render (cached path)
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for _ = 1, BENCH_RENDERS do
			tabline.render()
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		local hot_us = elapsed_ns / 1e3 / BENCH_RENDERS

		health.info(string.format("Hot bench: %.2f µs/render (cached, mean of %d renders)", hot_us, BENCH_RENDERS))
		health.info(string.format("Thresholds: warn > %d µs, fail > %d µs", WARN_THRESHOLD_US, FAIL_THRESHOLD_US))

		if hot_us > WARN_THRESHOLD_US then
			health.warn(string.format("Hot render %.2f µs exceeds soft target — cache may not be working", hot_us))
		else
			health.ok(string.format("Hot render: %.2f µs — cache effective", hot_us))
		end
	end

	-- =========================================================================
	-- Configuration
	-- =========================================================================
	health.start("beast.libs.tabline — configuration")

	health.info(string.format("max_name_width = %d", config.max_name_width))
	health.info(string.format("min_cell_width = %d", config.min_cell_width))
	health.info(string.format("show_close_button = %s", tostring(config.show_close_button)))
	health.info(string.format("show_modified = %s", tostring(config.show_modified)))
	health.info(string.format("show_diagnostics = %s", tostring(config.show_diagnostics)))

	-- Check showtabline
	if vim.o.showtabline == 2 then
		health.ok("showtabline = 2 (always visible)")
	elseif vim.o.showtabline == 1 then
		health.info("showtabline = 1 (visible when multiple tabs)")
	else
		health.warn(string.format("showtabline = %d (tabline may be hidden)", vim.o.showtabline))
	end

	-- Check sidebar filetypes configured
	local sidebar_count = 0
	for _ in pairs(config.sidebar_filetypes or {}) do
		sidebar_count = sidebar_count + 1
	end
	health.info(string.format("sidebar_filetypes: %d entries", sidebar_count))
end

return M
