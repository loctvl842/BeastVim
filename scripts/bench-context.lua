-- =========================================================================
-- Bench: Beast treesitter sticky-context update cost
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/treesitter/context`.
--
-- Measures the work that runs when the context overlay refreshes — the thing
-- driven by the WinScrolled / CursorMoved / WinEnter autocmds:
--   * context.get(win)        — walk TS ancestors, run the context query
--   * render.open (no change)  — the common throttled redraw (set_lines no-op)
--   * render.open (full)       — when the context changes: rebuild highlights
--   * one multiwindow tick      — get+render summed over N visible splits
--
-- IMPORTANT: these do NOT run on every keystroke. `update_win` is throttled to
-- at most ~2×/150ms per window, so per-event input cost is just the cheap
-- schedule/throttle bookkeeping; the numbers below are the cost of a refresh
-- when it actually fires.
--
-- Conforms to the bench contract in `docs/development/benchmarking.md`:
--   * Run as: nvim --clean --headless -l scripts/bench-context.lua
--   * Final stdout line begins with `BENCH ` (name=context, metric, threshold).
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 2000 -- single-window full refresh (get + full render)
local WARN_THRESHOLD_US = 800 -- soft target
local RUNS = 5
local ITERS = 500
local MULTIWIN_N = 3 -- splits to simulate for the multiwindow tick

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok_view, View = pcall(require, "beast.libs.view")
if not ok_view then
	io.stderr:write("BENCH ERROR could not load beast.libs.view: " .. tostring(View) .. "\n")
	os.exit(2)
end
_G.View = View

-- Seed a lua context query in a throwaway install dir so the loader resolves it
-- without touching the user's real site dir or the network.
local install = require("beast.libs.treesitter.install")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/queries/lua", "p")
vim.fn.writefile({
	"(for_statement body: (_) @context.end) @context",
	"(while_statement body: (_) @context.end) @context",
	"(do_statement) @context",
	"(function_definition parameters: (_) _ @context.end) @context",
	"(function_declaration parameters: (_) @context.final) @context",
	"(if_statement consequence: (_) @context.end) @context",
	"(repeat_statement body: (_) @context.end) @context",
}, tmp .. "/queries/lua/context.scm")
install.get_install_dir = function()
	return tmp
end

if vim.treesitter.language.add("lua") ~= true then
	io.stderr:write("BENCH ERROR lua treesitter parser not available\n")
	os.exit(2)
end

-- A realistically nested Lua buffer (~150 lines, 4 levels deep) so the context
-- walk has real work and the cursor sits under several pinned scopes.
local lines = { "local M = {}", "" }
for f = 1, 12 do
	lines[#lines + 1] = string.format("function M.handler_%d(input, opts)", f)
	lines[#lines + 1] = "\tif input ~= nil then"
	lines[#lines + 1] = "\t\tfor index = 1, #input do"
	lines[#lines + 1] = "\t\t\twhile opts.active do"
	lines[#lines + 1] = "\t\t\t\tlocal value = input[index]"
	lines[#lines + 1] = "\t\t\t\tlocal scaled = value * opts.factor"
	lines[#lines + 1] = "\t\t\t\tprint(index, value, scaled)"
	lines[#lines + 1] = "\t\t\t\topts.active = scaled < opts.limit"
	lines[#lines + 1] = "\t\t\tend"
	lines[#lines + 1] = "\t\tend"
	lines[#lines + 1] = "\tend"
	lines[#lines + 1] = "\treturn input"
	lines[#lines + 1] = "end"
	lines[#lines + 1] = ""
end
lines[#lines + 1] = "return M"

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.bo[buf].filetype = "lua"
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, buf)
vim.wo[win].number = true
pcall(vim.treesitter.start, buf, "lua")

-- Tall enough to scroll; park the cursor deep in a function body with the
-- function/if/for/while headers scrolled above the viewport top.
vim.o.lines = 20
local print_row = 8 -- the print() line inside the first handler
vim.api.nvim_win_set_cursor(win, { 5, 0 })
vim.cmd("normal! zt")
vim.api.nvim_win_set_cursor(win, { print_row, 4 })

local context = require("beast.libs.treesitter.context.context")
local render = require("beast.libs.treesitter.context.render")

local ranges, ctx_lines = context.get(win)
if not ranges or #ranges == 0 then
	io.stderr:write("BENCH ERROR context.get returned no ranges — setup is wrong (cannot bench)\n")
	os.exit(2)
end
io.stderr:write(string.format("# pinned scopes = %d: %s\n", #ranges, table.concat(ctx_lines, " / ")))

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
---@return number us_per_op
local function bench(fn)
	local samples = {}
	for _ = 1, RUNS do
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for i = 1, ITERS do
			fn(i)
		end
		samples[#samples + 1] = (vim.uv.hrtime() - t0) / 1e3 / ITERS
	end
	return median(samples)
end

-- =========================================================================
-- Scenario 1: context.get — the per-refresh compute
-- =========================================================================

local get_us = bench(function()
	context.get(win)
end)
print(string.format("ContextGet      %.2f µs/op (median of %d×%d)", get_us, RUNS, ITERS))

-- =========================================================================
-- Scenario 2: render.open, no content change (the common throttled redraw)
-- =========================================================================

render.open(win, ranges, ctx_lines, false) -- warm: open floats once
local render_nochange_us = bench(function()
	render.open(win, ranges, ctx_lines, false)
end)
print(string.format("RenderNoChange  %.2f µs/op (median of %d×%d)", render_nochange_us, RUNS, ITERS))

-- =========================================================================
-- Scenario 3: render.open, full highlight rebuild (context changed)
-- =========================================================================

local render_full_us = bench(function()
	render.open(win, ranges, ctx_lines, true) -- force_hl => rebuild highlights
end)
print(string.format("RenderFull      %.2f µs/op (median of %d×%d)", render_full_us, RUNS, ITERS))

-- =========================================================================
-- Scenario 4: one full single-window refresh = get + full render
-- =========================================================================

local single_refresh_us = bench(function()
	local r, l = context.get(win)
	render.open(win, r, l, true)
end)
print(string.format("SingleRefresh   %.2f µs/op (median of %d×%d)", single_refresh_us, RUNS, ITERS))
render.close(win)

-- =========================================================================
-- Scenario 5: one multiwindow tick = get + render across N visible splits
-- =========================================================================
--
-- This is the worst case the multiwindow autocmd path does on a throttled
-- tick: recompute + redraw every eligible split. We build N windows on the
-- same buffer and sum the per-window work.

local wins = { win }
for _ = 2, MULTIWIN_N do
	vim.cmd("split")
	local w = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(w, buf)
	vim.wo[w].number = true
	vim.api.nvim_win_set_cursor(w, { 5, 0 })
	vim.cmd("normal! zt")
	vim.api.nvim_win_set_cursor(w, { print_row, 4 })
	wins[#wins + 1] = w
end

local multiwin_us = bench(function()
	for _, w in ipairs(wins) do
		local r, l = context.get(w)
		if r and #r > 0 then
			render.open(w, r, l, true)
		end
	end
end)
print(string.format("MultiWinTick    %.2f µs/op (%d windows, median of %d×%d)", multiwin_us, #wins, RUNS, ITERS))
render.close_all()

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(
	string.format(
		"BENCH name=context get=%.1fus render_nochange=%.1fus render_full=%.1fus single=%.1fus multiwin%d=%.1fus threshold=%dus",
		get_us,
		render_nochange_us,
		render_full_us,
		single_refresh_us,
		#wins,
		multiwin_us,
		FAIL_THRESHOLD_US
	)
)

if single_refresh_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: single-window refresh %.1f µs > %d µs threshold\n", single_refresh_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if single_refresh_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: single-window refresh %.1f µs > %d µs soft target\n", single_refresh_us, WARN_THRESHOLD_US))
end

os.exit(0)
