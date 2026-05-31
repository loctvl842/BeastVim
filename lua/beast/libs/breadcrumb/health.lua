local M = {}

-- Thresholds aligned with scripts/bench-breadcrumb.lua
local FAIL_THRESHOLD_US = 1000 -- 1 ms — hard fail
local WARN_THRESHOLD_US = 50 -- soft target
local BENCH_RENDERS = 1000

local WINBAR_EXPR = "%!v:lua.require'beast.libs.breadcrumb'.render()"

function M.check()
	local health = vim.health

	health.start("beast.libs.breadcrumb")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for winbar")
		return
	end

	-- =========================================================================
	-- Module loading
	-- =========================================================================
	health.start("beast.libs.breadcrumb — modules")

	local submodules = { "config", "context", "filepath", "highlights" }
	local missing_sub = {}
	for _, name in ipairs(submodules) do
		local ok, err = pcall(require, "beast.libs.breadcrumb." .. name)
		if not ok then
			missing_sub[#missing_sub + 1] = string.format("%s (%s)", name, tostring(err))
		end
	end
	if #missing_sub == 0 then
		health.ok("All submodules load (config, context, filepath, highlights)")
	else
		health.error("Failed submodules: " .. table.concat(missing_sub, "; "))
		return
	end

	local breadcrumb = package.loaded["beast.libs.breadcrumb"]
	if breadcrumb then
		health.ok("Breadcrumb module loaded")
	else
		health.warn("Breadcrumb module not loaded (require('beast.libs.breadcrumb').setup() not called)")
	end

	-- =========================================================================
	-- Registration / wiring
	-- =========================================================================
	health.start("beast.libs.breadcrumb — registration")

	local groups = vim.api.nvim_get_autocmds({ group = "BeastBreadcrumb" })
	if groups and #groups > 0 then
		health.ok(string.format("Augroup BeastBreadcrumb registered (%d autocmds)", #groups))
	else
		health.warn("Augroup BeastBreadcrumb has no autocmds (setup() not called?)")
	end

	local registered_wins, total_eligible = 0, 0
	local config_ok, config = pcall(require, "beast.libs.breadcrumb.config")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.bo[buf].filetype
		local bt = vim.bo[buf].buftype
		local ignored = config_ok and (config.ignored_filetypes[ft] or config.ignored_buftypes[bt])
		if not ignored then
			total_eligible = total_eligible + 1
			if vim.wo[win].winbar == WINBAR_EXPR then
				registered_wins = registered_wins + 1
			end
		end
	end
	if total_eligible == 0 then
		health.info("No eligible windows open to verify winbar registration")
	elseif registered_wins == total_eligible then
		health.ok(string.format("Winbar registered on all %d eligible windows", total_eligible))
	else
		health.warn(string.format("Winbar registered on %d/%d eligible windows", registered_wins, total_eligible))
	end

	local function is_callable(v)
		if type(v) == "function" then
			return true
		end
		local mt = type(v) == "table" and getmetatable(v) or nil
		return mt and type(mt.__call) == "function"
	end

	if type(_G.Util) == "table" and is_callable(rawget(_G.Util, "root") or _G.Util.root) then
		health.ok("Util.root() available (used by filepath.render)")
	else
		health.error("Global Util.root() missing or not callable — filepath.render() will fail")
	end

	local has_devicons = pcall(require, "nvim-web-devicons")
	if has_devicons then
		health.ok("nvim-web-devicons available (icons enabled)")
	else
		health.warn("nvim-web-devicons not installed — file icons disabled (non-fatal)")
	end

	-- =========================================================================
	-- API contract
	-- =========================================================================
	health.start("beast.libs.breadcrumb — API contract")

	if not breadcrumb then
		health.error("Module not loaded — skipping API tests")
	else
		local ok1, result = pcall(breadcrumb.render)
		if ok1 and type(result) == "string" then
			health.ok(string.format("render() returns string (%d chars)", #result))
		elseif ok1 then
			health.error(string.format("render() returned %s (expected string)", type(result)))
		else
			health.error("render() raised: " .. tostring(result))
		end

		if type(breadcrumb.setup) == "function" then
			health.ok("setup() is a function")
		else
			health.error("setup() missing or not a function")
		end

		if type(breadcrumb._invalidate) == "function" then
			-- Round-trip: invalidate, render, verify cache repopulates (smoke)
			local ok_inv = pcall(breadcrumb._invalidate)
			local ok_re = pcall(breadcrumb.render)
			if ok_inv and ok_re then
				health.ok("_invalidate() + re-render works")
			else
				health.warn("_invalidate()/render() round-trip failed")
			end
		else
			health.warn("_invalidate() missing (cache cannot be flushed externally)")
		end
	end

	-- =========================================================================
	-- Highlights
	-- =========================================================================
	health.start("beast.libs.breadcrumb — highlights")

	local expected_hls = { "BeastBcFile", "BeastBcDir", "BeastBcSep", "BeastBcModified" }
	local missing_hls = {}
	for _, name in ipairs(expected_hls) do
		local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
		if not hl or vim.tbl_isempty(hl) then
			missing_hls[#missing_hls + 1] = name
		end
	end
	if #missing_hls == 0 then
		health.ok("All breadcrumb highlights defined")
	else
		health.warn("Missing or empty highlights: " .. table.concat(missing_hls, ", "))
	end

	-- =========================================================================
	-- Configuration
	-- =========================================================================
	health.start("beast.libs.breadcrumb — configuration")

	if config_ok then
		health.info(string.format("separator = %q", config.separator))
		health.info(string.format("modified_icon = %q", config.modified_icon))
		local ft_count = vim.tbl_count(config.ignored_filetypes or {})
		local bt_count = vim.tbl_count(config.ignored_buftypes or {})
		health.info(string.format("ignored: %d filetypes, %d buftypes", ft_count, bt_count))
	end

	-- =========================================================================
	-- Performance (inline bench — cold + hot)
	-- =========================================================================
	health.start("beast.libs.breadcrumb — performance")

	if not breadcrumb or not breadcrumb.render then
		health.warn("Cannot benchmark — module not loaded")
		return
	end

	-- Warm up
	for _ = 1, 10 do
		breadcrumb.render()
	end

	-- Hot path: cache hits
	collectgarbage("collect")
	local t0 = vim.uv.hrtime()
	for _ = 1, BENCH_RENDERS do
		breadcrumb.render()
	end
	local hot_us = (vim.uv.hrtime() - t0) / 1e3 / BENCH_RENDERS

	-- Cold path: invalidate before every render (cache miss each time)
	collectgarbage("collect")
	local t1 = vim.uv.hrtime()
	for _ = 1, BENCH_RENDERS do
		breadcrumb._invalidate()
		breadcrumb.render()
	end
	local cold_us = (vim.uv.hrtime() - t1) / 1e3 / BENCH_RENDERS

	health.info(string.format("Bench (hot):  %.2f µs/render (mean of %d)", hot_us, BENCH_RENDERS))
	health.info(string.format("Bench (cold): %.2f µs/render (mean of %d)", cold_us, BENCH_RENDERS))
	health.info(string.format("Thresholds: warn > %d µs, fail > %d µs", WARN_THRESHOLD_US, FAIL_THRESHOLD_US))

	local primary_us = cold_us
	if primary_us > FAIL_THRESHOLD_US then
		health.error(
			string.format(
				"FAIL: %.2f µs/render exceeds hard threshold (%d µs). Run `nvim --headless -l scripts/bench-breadcrumb.lua` for details.",
				primary_us,
				FAIL_THRESHOLD_US
			)
		)
	elseif primary_us > WARN_THRESHOLD_US then
		health.warn(
			string.format(
				"%.2f µs/render exceeds soft target (%d µs) — investigate with `nvim --headless -l scripts/bench-breadcrumb.lua`",
				primary_us,
				WARN_THRESHOLD_US
			)
		)
	else
		health.ok(string.format("%.2f µs/render (cold) — within budget", primary_us))
	end
end

return M
