local M = {}

-- Thresholds aligned with scripts/bench-statusline.lua
local FAIL_THRESHOLD_US = 1000 -- 1 ms — hard fail
local WARN_THRESHOLD_US = 50 -- soft target — anything slower is suspicious
local BENCH_RENDERS = 500

function M.check()
	local health = vim.health

	health.start("beast.libs.statusline")

	-- Check Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for statusline features")
		return
	end

	-- Check config loads
	local ok_cfg, config = pcall(require, "beast.libs.statusline.config")
	if not ok_cfg then
		health.error("Failed to load statusline config: " .. tostring(config))
		return
	end

	-- Check module loaded and setup called
	local stl = package.loaded["beast.libs.statusline"]
	if stl then
		health.ok("Statusline module loaded")
	else
		health.warn("Statusline module not loaded (require('beast.libs.statusline').setup() not called)")
	end

	-- Check if registered as vim.o.statusline
	if vim.o.statusline:find("beast.libs.statusline") then
		health.ok("Registered as vim.o.statusline provider")
	else
		health.warn("Not registered as statusline provider (vim.o.statusline does not reference beast)")
	end

	-- =========================================================================
	-- API contract: render() must return a string
	-- =========================================================================
	health.start("beast.libs.statusline — API contract")

	if not stl then
		health.error("Module not loaded — cannot run API tests")
	else
		-- Test 1: render returns a string
		local ok1, result = pcall(stl.render)
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
			health.warn("render() returned empty string (no visible components?)")
		end

		-- Test 3: setup() callable (dry check — do NOT call with empty opts, it resets state)
		if type(stl.setup) == "function" then
			health.ok("setup() is a function")
		else
			health.error("setup() missing or not a function")
		end
	end

	-- =========================================================================
	-- Components
	-- =========================================================================
	health.start("beast.libs.statusline — components")

	local ok_comps, components = pcall(require, "beast.libs.statusline.components")
	if not ok_comps then
		health.error("Failed to load components: " .. tostring(components))
	else
		local expected = { "mode", "git_branch", "git_commit", "diagnostics", "encoding", "shiftwidth", "filetype", "position" }
		local missing = {}
		for _, name in ipairs(expected) do
			if not components[name] then
				missing[#missing + 1] = name
			end
		end
		if #missing == 0 then
			health.ok("All built-in components available")
		else
			health.warn("Missing components: " .. table.concat(missing, ", "))
		end

		-- Verify each component has a provider function
		local broken = {}
		for name, spec in pairs(components) do
			if type(spec) ~= "table" or type(spec.provider) ~= "function" then
				broken[#broken + 1] = name
			end
		end
		if #broken == 0 then
			health.ok("All components have a valid provider function")
		else
			health.error("Components without provider: " .. table.concat(broken, ", "))
		end

		-- Actually call each provider with a real context to verify they work
		local ok_ctx_mod, context_mod = pcall(require, "beast.libs.statusline.context")
		if ok_ctx_mod then
			local ctx = context_mod.build()
			local errored = {}
			for name, spec in pairs(components) do
				if type(spec) == "table" and type(spec.provider) == "function" then
					local ok_run, run_err = pcall(spec.provider, ctx)
					if not ok_run then
						errored[#errored + 1] = string.format("%s: %s", name, tostring(run_err))
					end
				end
			end
			if #errored == 0 then
				health.ok("All component providers execute without error")
			else
				for _, msg in ipairs(errored) do
					health.error("Provider error — " .. msg)
				end
			end
		else
			health.warn("Could not build context for provider tests: " .. tostring(context_mod))
		end
	end

	-- =========================================================================
	-- Render performance (inline bench)
	-- =========================================================================
	health.start("beast.libs.statusline — performance")

	if not stl or not stl.render then
		health.warn("Cannot benchmark — module not loaded")
	else
		-- Warm up
		for _ = 1, 10 do
			stl.render()
		end

		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for _ = 1, BENCH_RENDERS do
			stl.render()
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		local us_per_render = elapsed_ns / 1e3 / BENCH_RENDERS

		health.info(string.format("Bench: %.2f µs/render (mean of %d renders)", us_per_render, BENCH_RENDERS))
		health.info(string.format("Thresholds: warn > %d µs, fail > %d µs", WARN_THRESHOLD_US, FAIL_THRESHOLD_US))

		if us_per_render > FAIL_THRESHOLD_US then
			health.error(string.format(
				"FAIL: %.2f µs/render exceeds hard threshold (%d µs). Run `nvim --headless -l scripts/bench-statusline.lua` for details.",
				us_per_render,
				FAIL_THRESHOLD_US
			))
		elseif us_per_render > WARN_THRESHOLD_US then
			health.warn(string.format(
				"%.2f µs/render exceeds soft target (%d µs) — investigate with `nvim --headless -l scripts/bench-statusline.lua`",
				us_per_render,
				WARN_THRESHOLD_US
			))
		else
			health.ok(string.format("%.2f µs/render — within budget", us_per_render))
		end
	end

	-- =========================================================================
	-- Configuration
	-- =========================================================================
	health.start("beast.libs.statusline — configuration")

	local left_count = #(config.left or {})
	local center_count = #(config.center or {})
	local right_count = #(config.right or {})
	health.info(string.format("Regions: left=%d, center=%d, right=%d", left_count, center_count, right_count))
	health.info(string.format("separator = %q", config.separator))
	health.info(string.format("default_priority = %d", config.default_priority))
	health.info(string.format("truncate_marker = %q", config.truncate_marker))

	if left_count + center_count + right_count == 0 then
		health.warn("No components registered in any region")
	else
		health.ok(string.format("%d components registered", left_count + center_count + right_count))
	end

	-- Check laststatus setting
	if vim.o.laststatus == 3 then
		health.ok("laststatus = 3 (global statusline)")
	elseif vim.o.laststatus == 2 then
		health.info("laststatus = 2 (per-window statusline)")
	else
		health.warn(string.format("laststatus = %d (statusline may not always be visible)", vim.o.laststatus))
	end
end

return M
