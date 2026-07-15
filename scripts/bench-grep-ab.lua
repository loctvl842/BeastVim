-- =========================================================================
-- Bench: live_grep engine A/B — bigram prefilter ON vs OFF
-- =========================================================================
-- Measures how much the bigram prefilter speeds up live_grep on a target repo,
-- by running the real source.get path both ways over the same queries.
--
--   Run as:  BENCH_ROOT=/path/to/repo \
--            nvim --clean --headless -l scripts/bench-grep-ab.lua
--
-- BENCH_ROOT defaults to the cwd. The index build is one-time (engine ON only);
-- per-query times are measured after the build, so they reflect steady state.
-- Page cache: run once to warm, or `sudo purge` first for a cold comparison.
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local uv = vim.uv or vim.loop
local config = require("beast.libs.finder.config")
local lg = require("beast.libs.finder.source.live_grep")
local index = require("beast.libs.finder.source.live_grep.engine.index")

local root = os.getenv("BENCH_ROOT") or uv.cwd()

-- Queries spanning the selectivity range (tune to your repo's tokens).
local QUERIES = vim.split(os.getenv("BENCH_QUERIES") or "calendar,function,authentication,needle_rare_token,zebra_marker_500", ",")

--- Run one live_grep query to completion; return elapsed ms + result count.
---@param pattern string
---@return number ms, integer results
local function run(pattern)
	local n, done = 0, false
	local t = uv.hrtime()
	lg.get({ pattern = pattern, cwd = root }, function(item)
		if item == nil then
			done = true
		else
			n = n + 1
		end
	end)
	vim.wait(120000, function()
		return done
	end, 20)
	return (uv.hrtime() - t) / 1e6, n
end

print("Repo: " .. root)

-- Build the index once (engine ON path needs it ready).
config.setup({ engine = { enabled = true } })
local built, bt = nil, uv.hrtime()
index.build(root, { max_files = 90000, max_file_size = 1024 * 1024 }, function(i)
	built = i
end)
vim.wait(600000, function()
	return built ~= nil
end, 50)
if not built then
	print("BENCH name=grep-ab status=FAIL reason=build-failed")
	vim.cmd("cquit 2")
end
print(string.format("Index: %d files, build %.0fms (one-time)\n", #built.files, (uv.hrtime() - bt) / 1e6))

print(string.format("%-22s %9s %11s %11s %9s", "query", "survivors", "OFF (full)", "ON (engine)", "speedup"))
print(string.rep("-", 66))

local total_off, total_on = 0, 0
for _, q in ipairs(QUERIES) do
	local surv = built:query(q)
	local sc = surv and #surv or 0

	-- Warm the cache once per side (discard), then measure.
	config.setup({ engine = { enabled = false } })
	run(q)
	local off_ms = run(q)

	config.setup({ engine = { enabled = true } })
	run(q)
	local on_ms = run(q)

	total_off, total_on = total_off + off_ms, total_on + on_ms
	print(string.format("%-22s %9s %9.0fms %9.0fms %7.1fx", q, surv and tostring(sc) or "full", off_ms, on_ms, off_ms / math.max(on_ms, 0.01)))
end

print(string.rep("-", 66))
print(string.format("BENCH name=grep-ab status=PASS total_off=%.0fms total_on=%.0fms speedup=%.1fx", total_off, total_on, total_off / math.max(total_on, 0.01)))
vim.cmd("qall!")
