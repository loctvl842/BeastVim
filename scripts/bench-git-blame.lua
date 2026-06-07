-- =========================================================================
-- Bench: Beast git blame
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/git/blame.lua`.
--
-- Measures the async round-trip wall time of `blame.run` for two
-- consumption patterns:
--   * single-line cursor blame (-L lnum,+1)       — cursor-move hot path
--   * full-file blame                             — on-demand UI
--
-- Each pattern is measured in unmodified and modified (--contents -)
-- variants.
--
-- Conforms to the bench contract:
--   * Run as: nvim --clean --headless -l scripts/bench-git-blame.lua
--   * Final stdout line begins with `BENCH ` and includes name=git-blame
--   * Exit code: 0 PASS, 1 FAIL (single-line threshold), 2 setup error.
-- =========================================================================

-- Threshold calibrated 2026-06-07 on macOS: single-line blame is bound by
-- `vim.system` → `git` process startup (~40ms floor on this hardware), not
-- by porcelain parsing or our code. Spec's 30ms target was optimistic;
-- 80ms gives headroom for CI/disk variance while still catching real
-- regressions (e.g. if we accidentally re-spawn per cursor move).
local SINGLE_LINE_THRESHOLD_MS = 80
local RUNS = 5

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok, blame = pcall(require, "beast.libs.git.blame")
if not ok then
	io.stderr:write("BENCH ERROR could not load beast.libs.git.blame: " .. tostring(blame) .. "\n")
	os.exit(2)
end

-- Use this lib's own init.lua as the fixture: it's tracked, real, and has
-- enough history for blame to actually do work.
local FIXTURE = "lua/beast/libs/git/init.lua"
local toplevel = vim.fn.getcwd()
local ctx = { toplevel = toplevel, gitdir = toplevel .. "/.git", relpath = FIXTURE }

if vim.fn.filereadable(toplevel .. "/" .. FIXTURE) ~= 1 then
	io.stderr:write("BENCH ERROR fixture not found: " .. FIXTURE .. "\n")
	os.exit(2)
end

local fixture_lines = vim.fn.readfile(toplevel .. "/" .. FIXTURE)
local lnum_mid = math.floor(#fixture_lines / 2)

local function median(xs)
	table.sort(xs)
	return xs[math.ceil(#xs / 2)]
end

local function bench(label, opts)
	local samples = {}
	for _ = 1, RUNS do
		local done = false
		local t0 = vim.uv.hrtime()
		blame.run(ctx, opts, function(b)
			local ms = (vim.uv.hrtime() - t0) / 1e6
			samples[#samples + 1] = ms
			assert(b, "blame returned nil for " .. label)
			done = true
		end)
		vim.wait(5000, function()
			return done
		end)
		assert(done, "blame timed out for " .. label)
	end
	local m = median(samples)
	print(string.format("%-22s median=%6.2f ms", label, m))
	return m
end

print(string.format("fixture: %s (%d lines)", FIXTURE, #fixture_lines))

local m_sl_unmod = bench("single-line unmodified", { lnum = lnum_mid })
local m_sl_mod = bench("single-line modified", { lnum = lnum_mid, contents = fixture_lines })
local m_full_unmod = bench("full-file unmodified", {})
local m_full_mod = bench("full-file modified", { contents = fixture_lines })

local status = "PASS"
local exit = 0
if m_sl_unmod > SINGLE_LINE_THRESHOLD_MS then
	status = "FAIL"
	exit = 1
end

print(
	string.format(
		"BENCH name=git-blame fixture_lines=%d sl_unmod=%.2fms sl_mod=%.2fms full_unmod=%.2fms full_mod=%.2fms threshold=%dms status=%s",
		#fixture_lines,
		m_sl_unmod,
		m_sl_mod,
		m_full_unmod,
		m_full_mod,
		SINGLE_LINE_THRESHOLD_MS,
		status
	)
)

os.exit(exit)
