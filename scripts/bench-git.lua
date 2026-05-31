-- =========================================================================
-- Bench: Beast git diff (compute_hunks)
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/git/diff.lua`.
--
-- Conforms to the bench contract in `docs/tec-config/health-config.md`:
--   * Run as: nvim --clean --headless -l scripts/bench-git.lua
--   * Final stdout line begins with `BENCH ` and includes name=git
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_MS = 10 -- hard cap for the 5k-line scenario
local RUNS = 3

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok, diff = pcall(require, "beast.libs.git.diff")
if not ok then
	io.stderr:write("BENCH ERROR could not load beast.libs.git.diff: " .. tostring(diff) .. "\n")
	os.exit(2)
end

-- Build a synthetic buffer of `n` lines, then return (base, current) where
-- `current` has `n_hunks` localised changes scattered uniformly.
local function make_pair(n, n_hunks)
	local base_lines = {}
	for i = 1, n do
		base_lines[i] = string.format("line %06d  alpha bravo charlie delta echo", i)
	end
	local cur_lines = vim.deepcopy(base_lines)
	local step = math.floor(n / (n_hunks + 1))
	for h = 1, n_hunks do
		local at = h * step
		cur_lines[at] = "MODIFIED " .. cur_lines[at]
		if h % 3 == 0 and at + 1 <= n then
			cur_lines[at + 1] = "INSERTED line after " .. h
		end
	end
	return table.concat(base_lines, "\n"), table.concat(cur_lines, "\n")
end

local function median(xs)
	table.sort(xs)
	return xs[math.ceil(#xs / 2)]
end

local function bench(label, n, n_hunks)
	local base, current = make_pair(n, n_hunks)
	-- Warm up the JIT.
	for _ = 1, 3 do
		diff.compute_hunks(base, current)
	end
	local samples = {}
	for _ = 1, RUNS do
		local t0 = vim.uv.hrtime()
		local hunks = diff.compute_hunks(base, current)
		local ms = (vim.uv.hrtime() - t0) / 1e6
		samples[#samples + 1] = ms
		assert(#hunks > 0, "expected hunks, got none for " .. label)
	end
	local m = median(samples)
	print(string.format("%-12s %d lines / %d hunks  median=%.3f ms", label, n, n_hunks, m))
	return m
end

print("backend: " .. diff.backend)
local m1k = bench("1k", 1000, 20)
local m5k = bench("5k", 5000, 50)
local m20k = bench("20k", 20000, 100)

local status = "PASS"
local exit = 0
if m5k > FAIL_THRESHOLD_MS then
	status = "FAIL"
	exit = 1
end

print(
	string.format(
		"BENCH name=git backend=%s 1k=%.2fms 5k=%.2fms 20k=%.2fms threshold=%dms status=%s",
		diff.backend,
		m1k,
		m5k,
		m20k,
		FAIL_THRESHOLD_MS,
		status
	)
)

os.exit(exit)
