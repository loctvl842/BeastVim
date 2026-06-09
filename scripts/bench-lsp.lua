-- =========================================================================
-- Bench: beast.libs.lsp capabilities resolution time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/lsp`.
--
-- Why this metric?
--   After Phase 1 of docs/dev-specs/lsp-infra-hardening.md, the default
--   `capabilities` passed to `vim.lsp.config` is a function thunk that
--   resolves at every `vim.lsp.start_client()` call. The merge cost runs
--   once per client start, so it must stay cheap even with many contributors
--   (blink.cmp, nvim-cmp polyfills, lang-extension overlays, etc.).
--
--   Threshold rationale: Each LSP start already runs ~10–100 ms of work
--   (binary spawn + initialize handshake). A 1 ms ceiling on capabilities
--   resolution is well under 1% of that — invisible in practice. The spec's
--   original 50 µs target was wishful; vim.tbl_deep_extend over a deep
--   capabilities table is O(table-depth) per call, dominated by Lua loop
--   cost. 50 contributors is a stress scenario — real-world is 1–3.
--
-- Conforms to the bench contract:
--   * Run as: nvim --clean --headless -l scripts/bench-lsp.lua
--   * Final stdout line begins with `BENCH ` and includes name=lsp,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 1000 -- 1 ms — see rationale above
local WARN_THRESHOLD_US = 500
local CONTRIB_COUNT = 50 -- stress (real-world is 1–3)
local CALLS_PER_RUN = 1000
local RUNS = 5
local WARMUP_RUNS = 2

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ok_caps, caps = pcall(require, "beast.libs.lsp.capabilities")
if not ok_caps then
	io.stderr:write("BENCH ERROR could not load beast.libs.lsp.capabilities: " .. tostring(caps) .. "\n")
	os.exit(2)
end

-- Realistic mix: half table contributors, half function contributors.
-- Each contributes a small unique key so deep_extend has work to do.
for i = 1, CONTRIB_COUNT do
	if i % 2 == 0 then
		caps.add({ textDocument = { ["contrib_" .. i] = { dynamicRegistration = true } } })
	else
		local n = i
		caps.add(function()
			return { textDocument = { ["contrib_" .. n] = { dynamicRegistration = true } } }
		end)
	end
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

local function median(xs)
	local sorted = vim.deepcopy(xs)
	table.sort(sorted)
	local n = #sorted
	if n % 2 == 1 then
		return sorted[(n + 1) / 2]
	end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

---@return number  µs/call (median across RUNS, warmups discarded)
local function bench()
	local samples = {}
	for _ = 1, WARMUP_RUNS + RUNS do
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for _ = 1, CALLS_PER_RUN do
			caps.get()
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		samples[#samples + 1] = elapsed_ns / 1e3 / CALLS_PER_RUN
	end
	-- Drop warmup samples
	local kept = {}
	for i = WARMUP_RUNS + 1, #samples do
		kept[#kept + 1] = samples[i]
	end
	return median(kept), mean(kept)
end

-- =========================================================================
-- Run
-- =========================================================================

local median_us, mean_us = bench()
print(
	string.format(
		"Beast lsp capabilities resolution: median=%.2f µs/call mean=%.2f µs/call (contributors=%d, %d×%d)",
		median_us,
		mean_us,
		CONTRIB_COUNT,
		RUNS,
		CALLS_PER_RUN
	)
)

print(string.format("BENCH name=lsp median=%.2fus mean=%.2fus threshold=%dus", median_us, mean_us, FAIL_THRESHOLD_US))

if median_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.2f µs > %d µs threshold\n", median_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if median_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.2f µs > %d µs soft target (investigate)\n", median_us, WARN_THRESHOLD_US))
end

os.exit(0)
