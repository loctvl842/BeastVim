-- =========================================================================
-- Bench: Beast finder matcher performance
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/finder/matcher`.
--
-- Conforms to the bench contract documented in
-- `docs/tec-config/health-config.md` § "Run-time Render Performance":
--   * Run as: nvim --clean --headless -l scripts/bench-finder-matcher.lua
--   * Final stdout line begins with `BENCH ` and includes name=finder-matcher,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FULL_SCAN_THRESHOLD_MS = 80 -- 1-char query on 90k items
local SUBSET_THRESHOLD_MS = 50 -- 3-char query on 90k items (subset path)
local ITEM_COUNT = 90000

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Minimal stubs
_G.Util = {
	root = function()
		return "/tmp"
	end,
}

local uv = vim.uv or vim.loop
local Filter = require("beast.libs.finder.filter")
local async = require("beast.libs.async")
local matcher = require("beast.libs.finder.matcher")

-- =========================================================================
-- Generate synthetic items
-- =========================================================================

local dirs = {
	"src/components/",
	"src/api/",
	"src/utils/",
	"lib/core/",
	"docs/guides/",
	"tests/unit/",
	"tests/integration/",
	"config/",
	"packages/auth/src/",
	"packages/ui/src/",
	"packages/data/src/",
	"vendor/lib/",
	"scripts/",
	"tools/build/",
	"assets/images/",
}
local exts = { ".lua", ".ts", ".js", ".md", ".json", ".yaml", ".go", ".rs" }

math.randomseed(42) -- deterministic

local items = {}
for i = 1, ITEM_COUNT do
	local dir = dirs[math.random(#dirs)]
	local ext = exts[math.random(#exts)]
	local name = string.format("file_%05d%s", i, ext)
	items[i] = {
		idx = i,
		score = 0,
		text = dir .. name,
		file = "/project/" .. dir .. name,
		cwd = "/project",
	}
end

-- =========================================================================
-- Helpers
-- =========================================================================

local cfg = { smartcase = true, ignorecase = true }

--- Run matcher synchronously by spinning the event loop until on_done fires
---@param pattern string
---@param prev_state? Beast.Finder.MatchState
---@return number elapsed_ms
---@return Beast.Finder.MatchState state
local function run_sync(pattern, prev_state)
	local filter = Filter()
	filter:update(pattern)

	local done = false
	local result_state = nil
	local result_matched = nil

	local start = uv.hrtime()
	matcher.run(items, filter, cfg, function(matched, state)
		result_matched = matched
		result_state = state
		done = true
	end, prev_state)

	-- Spin event loop until done
	while not done do
		vim.wait(1, function()
			return done
		end, 1)
	end
	local elapsed_ms = (uv.hrtime() - start) / 1e6

	return elapsed_ms, result_state, result_matched
end

-- =========================================================================
-- Run benchmarks
-- =========================================================================

print(string.format("Items: %d", ITEM_COUNT))
print(string.rep("-", 60))

-- 1. Full scan: 1-char query (no previous state)
local full_ms, state1, matched1 = run_sync("f")
print(string.format("Full scan ('f'):    %7.1f ms  (%d matched)", full_ms, #matched1))

-- 2. Subset: 2-char (appending to previous)
local sub2_ms, state2, matched2 = run_sync("fi", state1)
print(string.format("Subset    ('fi'):   %7.1f ms  (%d matched)", sub2_ms, #matched2))

-- 3. Subset: 3-char
local sub3_ms, state3, matched3 = run_sync("fil", state2)
print(string.format("Subset    ('fil'):  %7.1f ms  (%d matched)", sub3_ms, #matched3))

-- 4. Empty pattern fast-path
local empty_ms, _, matched_empty = run_sync("")
print(string.format("Empty     (''):     %7.1f ms  (%d returned)", empty_ms, #matched_empty))

-- 5. Full rescan after backspace (no prev_state)
local rescan_ms, _, matched_rescan = run_sync("fi")
print(string.format("Rescan    ('fi'):   %7.1f ms  (%d matched)", rescan_ms, #matched_rescan))

print(string.rep("-", 60))

-- =========================================================================
-- Verdict
-- =========================================================================

local full_pass = full_ms < FULL_SCAN_THRESHOLD_MS
local subset_pass = sub3_ms < SUBSET_THRESHOLD_MS

local status = (full_pass and subset_pass) and "PASS" or "FAIL"
print(
	string.format(
		"BENCH name=finder-matcher status=%s full_scan=%.1fms(<%dms) subset=%.1fms(<%dms)",
		status,
		full_ms,
		FULL_SCAN_THRESHOLD_MS,
		sub3_ms,
		SUBSET_THRESHOLD_MS
	)
)

if status == "FAIL" then
	vim.cmd("cquit 1")
else
	vim.cmd("qall!")
end
