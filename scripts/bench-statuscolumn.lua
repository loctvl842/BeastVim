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

-- Seed realistic sign load: 10 diagnostic + 20 git extmarks scattered through
-- the buffer so the diagnostic/git producers have work on cache miss.
local function seed_signs()
	local diag_ns = vim.api.nvim_create_namespace("vim.diagnostic.bench")
	local git_ns = vim.api.nvim_create_namespace("gitsigns_extmark_signs_bench")
	for i = 1, 10 do
		vim.api.nvim_buf_set_extmark(buf, diag_ns, (i * 17) % LINES, 0, {
			sign_text = "E ",
			sign_hl_group = "DiagnosticSignError",
			priority = 20,
		})
	end
	for i = 1, 20 do
		vim.api.nvim_buf_set_extmark(buf, git_ns, (i * 7) % LINES, 0, {
			sign_text = "▎",
			sign_hl_group = "GitSignsAdd",
			priority = 6,
		})
	end
end
seed_signs()

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
-- Scenario 1: cache hits, number-only (same line every call)
-- =========================================================================

stc.setup({ segments = { { "number" } } })
require("beast.libs.statuscolumn.cache").drop_win(winid)
eval_line(1) -- warm

local hit_us = bench(function()
	eval_line(1)
end)
print(string.format("CacheHit       %.3f µs/render (median of %d×%d)", hit_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Scenario 2: cache misses, number-only (sweep lines on same tick)
-- =========================================================================
--
-- Models the realistic flow: signs.collect runs once per redraw, then all
-- visible lines reuse it. Per-line cost should be just slot dispatch.

local cache = require("beast.libs.statuscolumn.cache")
local sweep_us = bench(function(i)
	local lnum = ((i - 1) % LINES) + 1
	cache.drop_lines(winid)
	eval_line(lnum)
end)
print(string.format("CacheMiss      %.3f µs/render (median of %d×%d)", sweep_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Scenario 3: 3-slot layout {number, git, diagnostic} (sweep, same tick)
-- =========================================================================

stc.setup({
	segments = { { "number" }, { "git" }, { "diagnostic" } },
})
cache.drop_win(winid)
eval_line(1) -- warm signs.collect once for this layout

local full_us = bench(function(i)
	local lnum = ((i - 1) % LINES) + 1
	cache.drop_lines(winid)
	eval_line(lnum)
end)
print(string.format("3Slot+Signs    %.3f µs/render (median of %d×%d)", full_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Scenario 4: full redraw = signs.collect + LINES line renders, amortised
-- =========================================================================
--
-- Models a buffer redraw: drop the whole per-window state, render all lines
-- once, divide by LINES. This is what the "<500 µs / 80-line window" budget
-- in the spec measures.

local function full_redraw()
	cache.drop_win(winid)
	for lnum = 1, LINES do
		eval_line(lnum)
	end
end

local samples = {}
for _ = 1, RUNS do
	collectgarbage("collect")
	local t0 = vim.uv.hrtime()
	for _ = 1, 10 do
		full_redraw()
	end
	local elapsed_ns = vim.uv.hrtime() - t0
	samples[#samples + 1] = elapsed_ns / 1e3 / 10 -- µs per full redraw
end
table.sort(samples)
local redraw_us = samples[math.ceil(#samples / 2)]
print(string.format("FullRedraw     %.1f µs/redraw (%d lines, median of %d×10)", redraw_us, LINES, RUNS))

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(
	string.format(
		"BENCH name=statuscolumn hit=%.3fus miss=%.3fus full=%.3fus redraw%d=%.1fus threshold=%dus",
		hit_us,
		sweep_us,
		full_us,
		LINES,
		redraw_us,
		FAIL_THRESHOLD_US
	)
)

local worst = math.max(sweep_us, full_us)
if worst > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.3f µs > %d µs threshold\n", worst, FAIL_THRESHOLD_US))
	os.exit(1)
end

if worst > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.3f µs > %d µs soft target — investigate before adding segments\n", worst, WARN_THRESHOLD_US))
end

os.exit(0)
