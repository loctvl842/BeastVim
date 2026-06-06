-- =========================================================================
-- Bench: Beast key hint
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/key/hint.lua`.
-- Run as: nvim --clean --headless -l scripts/bench-key-hint.lua
--   * Final stdout line begins with `BENCH ` and includes name=key-hint
--     plus primary metric and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
--
-- Measurements:
--   * index_build_us      — time to build prefix tree from 200-keymap registry
--   * hint_open_us       — time for one render of the root hint (proxy for
--                           "trigger fired → window visible")
-- =========================================================================

local OPEN_THRESHOLD_US = 5000 -- hint_open p50 must be < 5ms (spec target)
local INDEX_THRESHOLD_US = 500 -- index_build < 500us for 200 maps
local ITERS = 100

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
	refresh = function() end,
}
_G.Util = require("beast.util")
_G.Util.colors = _G.Util.colors or { set_hl = function() end }

local Key = require("beast.libs.key")
local hint = require("beast.libs.key.hint")

-- 200 mappings under <leader>: 10 groups × 20 leaves
local prefixes = { "f", "g", "b", "c", "d", "s", "t", "u", "w", "x" }
for _, p in ipairs(prefixes) do
	Key.safe_set("n", "<leader>" .. p, nil, { group = p })
	for i = 0, 19 do
		local key = string.char(string.byte("a") + (i % 26))
		Key.safe_set("n", "<leader>" .. p .. key .. tostring(i), function() end, { desc = "op_" .. p .. i })
	end
end

hint.setup({
	enabled = true,
	triggers = { "<leader>" },
	modes = { "n" },
	delay = 0,
	win = {
		width = { min = 30, max = 60 },
		height = { min = 4, max = 0.6 },
		border = "rounded",
		anchor = "SE",
		padding = { 0, 1 },
		title_pos = "left",
	},
})

vim.wait(150) -- let scheduled BeastKeysChanged emits flush

local hrtime = (vim.uv or vim.loop).hrtime
local function time_ns(fn)
	local t0 = hrtime()
	fn()
	return hrtime() - t0
end
local function percentile(sorted, p)
	return sorted[math.max(1, math.ceil(#sorted * p))]
end
local function stats(samples)
	table.sort(samples)
	return { min = samples[1], p50 = percentile(samples, 0.5), p95 = percentile(samples, 0.95), max = samples[#samples] }
end
local function us(ns)
	return ns / 1000
end

-- =========================================================================
-- 1. index_build — time to rebuild prefix tree after invalidation
-- =========================================================================
local index_samples = {}
for _ = 1, ITERS do
	hint._internal.invalidate_cache()
	table.insert(index_samples, time_ns(hint._internal.build_index))
end
local idx = stats(index_samples)

-- =========================================================================
-- 2. hint_open — time for one render of the root hint
-- =========================================================================
local open_samples = {}
for _ = 1, ITERS do
	table.insert(
		open_samples,
		time_ns(function()
			hint._internal.render_once("n", "<leader>", {})
		end)
	)
end
local opn = stats(open_samples)

-- =========================================================================
-- 3. keypress_resolve — time for one descent render at <leader>f
-- =========================================================================
local resolve_samples = {}
for _ = 1, ITERS do
	table.insert(
		resolve_samples,
		time_ns(function()
			hint._internal.render_once("n", "<leader>", { "f" })
		end)
	)
end
local res = stats(resolve_samples)

print(string.format("index_build_us:      min=%.1f p50=%.1f p95=%.1f max=%.1f", us(idx.min), us(idx.p50), us(idx.p95), us(idx.max)))
print(string.format("hint_open_us:       min=%.1f p50=%.1f p95=%.1f max=%.1f", us(opn.min), us(opn.p50), us(opn.p95), us(opn.max)))
print(string.format("keypress_resolve_us: min=%.1f p50=%.1f p95=%.1f max=%.1f", us(res.min), us(res.p50), us(res.p95), us(res.max)))

local idx_pass = us(idx.p50) < INDEX_THRESHOLD_US
local opn_pass = us(opn.p50) < OPEN_THRESHOLD_US
local status = (idx_pass and opn_pass) and "PASS" or "FAIL"

print(
	string.format(
		"BENCH name=key-hint index_p50=%.1fus(<%d) open_p50=%.1fus(<%d) status=%s",
		us(idx.p50),
		INDEX_THRESHOLD_US,
		us(opn.p50),
		OPEN_THRESHOLD_US,
		status
	)
)

os.exit(status == "PASS" and 0 or 1)
