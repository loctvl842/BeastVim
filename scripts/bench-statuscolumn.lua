-- =========================================================================
-- Bench: Beast statuscolumn render time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/statuscolumn`.
--
-- Conforms to the bench contract in `docs/tec-config/health-config.md`:
--   * Run as: nvim --clean --headless -l scripts/bench-statuscolumn.lua
--   * Final stdout line begins with `BENCH ` and includes name=statuscolumn,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 5 -- per-line median, full segment dispatch
local WARN_THRESHOLD_US = 2 -- soft target for Phase 1 (eval_statusline adds ~1µs overhead)
local LINES = 200
local RENDERS_PER_RUN = 1000
local RUNS = 3

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok_stc, stc = pcall(require, "beast.libs.statuscolumn")
if not ok_stc then
	io.stderr:write("BENCH ERROR could not load beast.libs.statuscolumn: " .. tostring(stc) .. "\n")
	os.exit(2)
end

-- Scratch buffer with LINES lines so v:lnum is realistic.
local buf = vim.api.nvim_create_buf(false, true)
local lines = {}
for i = 1, LINES do
	lines[i] = string.format("line %d - some content here", i)
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_win_set_buf(0, buf)

stc.setup({
	segments = { { "number" } },
})

-- Use nvim_eval_statusline so v:lnum / v:relnum / v:virtnum are set the same
-- way Neovim sets them for an actual statuscolumn evaluation. We bind to the
-- render fn directly afterwards for the tight inner loop — eval_statusline
-- adds ~1 µs of parser overhead per call which we don't want in the hot path.
local winid = vim.api.nvim_get_current_win()
vim.g.statusline_winid = winid

local function eval_line(lnum)
	vim.api.nvim_eval_statusline("%!v:lua.require'beast.libs.statuscolumn'.render()", {
		winid = winid,
		use_statuscol_lnum = lnum,
	})
end

-- Pre-warm: hit the cache once per line.
for i = 1, LINES do
	eval_line(i)
end

-- =========================================================================
-- Bench helpers
-- =========================================================================

local function median(xs)
	local s = {}
	for i, v in ipairs(xs) do
		s[i] = v
	end
	table.sort(s)
	local n = #s
	if n % 2 == 1 then
		return s[(n + 1) / 2]
	end
	return (s[n / 2] + s[n / 2 + 1]) / 2
end

---@param fn fun(i: integer)
---@return number us_per_render
local function bench(fn)
	local samples = {}
	for _ = 1, RUNS do
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for i = 1, RENDERS_PER_RUN do
			fn(i)
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		samples[#samples + 1] = elapsed_ns / 1e3 / RENDERS_PER_RUN
	end
	return median(samples)
end

-- =========================================================================
-- Scenario 1: cache hits (same line every call)
-- =========================================================================

local hit_us = bench(function()
	eval_line(1)
end)
print(string.format("CacheHit  %.3f µs/render (median of %d×%d)", hit_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Scenario 2: cache misses (sweep through all lines, bumping tick each time)
-- =========================================================================

local cache = require("beast.libs.statuscolumn.cache")
local sweep_us = bench(function(i)
	local lnum = ((i - 1) % LINES) + 1
	cache.drop_win(winid)
	eval_line(lnum)
end)
print(string.format("CacheMiss %.3f µs/render (median of %d×%d)", sweep_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(string.format("BENCH name=statuscolumn hit=%.3fus miss=%.3fus threshold=%dus", hit_us, sweep_us, FAIL_THRESHOLD_US))

if sweep_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.3f µs (miss) > %d µs threshold\n", sweep_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if sweep_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.3f µs (miss) > %d µs soft target — investigate before adding segments\n", sweep_us, WARN_THRESHOLD_US))
end

os.exit(0)
