-- =========================================================================
-- Bench: Beast breadcrumb (winbar) render time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/breadcrumb`.
--
-- Conforms to the bench contract:
--   * Run as: nvim --clean --headless -l scripts/bench-breadcrumb.lua
--   * Final stdout line begins with `BENCH ` and includes name=breadcrumb,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 1000 -- 1 ms
local WARN_THRESHOLD_US = 50
local RENDERS_PER_RUN = 1000
local RUNS = 3

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stub globals so highlights resolve (real config not loaded).
_G.Theme = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = {
	root = function()
		return vim.fn.getcwd()
	end,
	colors = {
		set_hl = function() end,
		lighten = function(_, _)
			return "#ffffff"
		end,
		blend = function(_, _, _)
			return "#ffffff"
		end,
		inspect = function(_)
			return setmetatable({}, {
				__index = function()
					return nil
				end,
			})
		end,
	},
}

-- Open a deep file to simulate a realistic breadcrumb path
local test_file = "lua/beast/libs/breadcrumb/init.lua"
local ok_edit = pcall(vim.cmd.edit, test_file)
if not ok_edit then
	io.stderr:write("BENCH WARN could not open " .. test_file .. "\n")
end

-- Load breadcrumb
local ok_bc, breadcrumb = pcall(require, "beast.libs.breadcrumb")
if not ok_bc then
	io.stderr:write("BENCH ERROR could not load beast.libs.breadcrumb: " .. tostring(breadcrumb) .. "\n")
	os.exit(2)
end

-- Setup without actually setting vim.o.winbar (we call render directly)
local ok_cfg = pcall(function()
	require("beast.libs.breadcrumb.config").setup({})
end)
if not ok_cfg then
	io.stderr:write("BENCH ERROR could not setup breadcrumb config\n")
	os.exit(2)
end

-- Pre-warm one render
local ok_render, err = pcall(breadcrumb.render)
if not ok_render then
	io.stderr:write("BENCH ERROR render failed: " .. tostring(err) .. "\n")
	os.exit(2)
end

-- =========================================================================
-- Bench helpers
-- =========================================================================

local function mean(xs)
	local s = 0
	for _, v in ipairs(xs) do
		s = s + v
	end
	return s / #xs
end

---@param fn fun()
---@return number  µs/render (mean across RUNS)
local function bench(fn)
	local samples = {}
	for _ = 1, RUNS do
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for _ = 1, RENDERS_PER_RUN do
			fn()
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		samples[#samples + 1] = elapsed_ns / 1e3 / RENDERS_PER_RUN
	end
	return mean(samples)
end

-- =========================================================================
-- Bench runs
-- =========================================================================

-- Cold render: force cache invalidation on every iteration
local cold_us = bench(function()
	breadcrumb._invalidate()
	breadcrumb.render()
end)
print(string.format("Beast breadcrumb (cold) %.2f µs/render  (mean of %d×%d)", cold_us, RUNS, RENDERS_PER_RUN))

-- Hot render: cached path (no events between redraws)
local hot_us = bench(function()
	breadcrumb.render()
end)
print(string.format("Beast breadcrumb (hot)  %.2f µs/render  (mean of %d×%d)", hot_us, RUNS, RENDERS_PER_RUN))

-- Symbol lookup: binary search through a 5.4k-symbol tree (branching 4, depth 6)
local lsp = require("beast.libs.breadcrumb.symbols.lsp")

---@return table[]
local function build_level(depth, first_row, rows)
	local nodes = {}
	local span = rows / 4
	for i = 0, 3 do
		local start = first_row + i * span
		nodes[#nodes + 1] = {
			name = "sym",
			kind = "Function",
			range = { start, 0, start + span, 0 },
			children = depth > 1 and build_level(depth - 1, start, span) or {},
		}
	end
	return nodes
end
local tree = build_level(6, 0, 4 ^ 7)
local probe_row = 4 ^ 7 / 3
local find_us = bench(function()
	lsp.find(tree, probe_row, 0)
end)
print(string.format("Beast breadcrumb (find) %.2f µs/lookup  (mean of %d×%d)", find_us, RUNS, RENDERS_PER_RUN))

-- Render with a 5-symbol trail (source excluded): segment building + truncation
local filepath = require("beast.libs.breadcrumb.filepath")
local ctx = { bufnr = vim.api.nvim_get_current_buf(), bufname = vim.fn.getcwd() .. "/" .. test_file, width = 80 }
local trail = {}
for i = 1, 5 do
	trail[i] = { name = "symbol_" .. i, kind = "Function" }
end
local trail_us = bench(function()
	filepath.render(ctx, "  ", "", trail)
end)
print(string.format("Beast breadcrumb (trail render) %.2f µs/render  (mean of %d×%d)", trail_us, RUNS, RENDERS_PER_RUN))

-- Use cold render for the primary metric (worst case)
local primary_us = cold_us

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(
	string.format(
		"BENCH name=breadcrumb cold=%.2fus hot=%.2fus find=%.2fus trail=%.2fus threshold=%dus",
		cold_us,
		hot_us,
		find_us,
		trail_us,
		FAIL_THRESHOLD_US
	)
)

if math.max(primary_us, find_us, trail_us) > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: find %.2f µs / trail render %.2f µs over %d µs\n", find_us, trail_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if primary_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.2f µs > %d µs threshold\n", primary_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if primary_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.2f µs > %d µs soft target (investigate)\n", primary_us, WARN_THRESHOLD_US))
end

os.exit(0)
