-- =========================================================================
-- Bench: Beast highlight reload pipeline
-- =========================================================================
-- Headless benchmark for `beast.reload_highlights()` — the function that
-- runs on every `ColorScheme` event. Measures cold (no cache) baseline so
-- Phase 2/3 of `docs/dev-specs/fast-highlight-reload.md` can prove gains.
--
-- Contract:
--   * Run as: nvim --headless -l scripts/bench-highlight-reload.lua
--   * Final stdout line begins with `BENCH ` and includes name, metric,
--     threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 20000 -- 20 ms — cold ceiling for 14 modules
local RUNS_PER_BATCH = 50
local BATCHES = 5

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok_beast, beast = pcall(require, "beast")
if not ok_beast then
	io.stderr:write("BENCH ERROR could not load beast: " .. tostring(beast) .. "\n")
	os.exit(2)
end

-- Minimal setup so all libs exist and a colorscheme is applied.
pcall(beast.setup, {})
pcall(vim.cmd, "colorscheme tokyonight")
vim.wait(50)

if not beast.reload_highlights then
	io.stderr:write("BENCH ERROR beast.reload_highlights missing\n")
	os.exit(2)
end

local function percentile(xs, p)
	table.sort(xs)
	local idx = math.max(1, math.ceil(#xs * p))
	return xs[idx]
end

local function mean(xs)
	local s = 0
	for _, v in ipairs(xs) do
		s = s + v
	end
	return s / #xs
end

local samples = {}
for _ = 1, BATCHES do
	collectgarbage("collect")
	local t0 = vim.uv.hrtime()
	for _ = 1, RUNS_PER_BATCH do
		beast.reload_highlights()
	end
	local elapsed_us = (vim.uv.hrtime() - t0) / 1e3 / RUNS_PER_BATCH
	samples[#samples + 1] = elapsed_us
end

local m = mean(samples)
local p95 = percentile(samples, 0.95)

print(string.format("reload_highlights  mean=%.1f µs  p95=%.1f µs  (n=%d×%d)", m, p95, BATCHES, RUNS_PER_BATCH))

local pass = m < FAIL_THRESHOLD_US
print(string.format("BENCH name=highlight-reload metric=mean_us value=%.1f threshold=%d status=%s", m, FAIL_THRESHOLD_US, pass and "PASS" or "FAIL"))
os.exit(pass and 0 or 1)
