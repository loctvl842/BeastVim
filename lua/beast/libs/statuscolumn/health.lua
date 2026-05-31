local M = {}

local STC_EXPR = "%!v:lua.require'beast.libs.statuscolumn'.render()"
local FAIL_THRESHOLD_US = 5 -- per-line, matches scripts/bench-statuscolumn.lua
local BENCH_RENDERS = 1000

local VALID_PRODUCERS = { number = true, diagnostic = true, git = true, fold = true }

function M.check()
	local health = vim.health

	health.start("beast.libs.statuscolumn")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required (extmark `type=sign` API)")
		return
	end

	-- =====================================================================
	-- Submodules
	-- =====================================================================
	health.start("beast.libs.statuscolumn — modules")

	local submodules = { "config", "ffi", "cache", "number", "signs", "fold", "highlights" }
	local missing = {}
	for _, name in ipairs(submodules) do
		local ok, err = pcall(require, "beast.libs.statuscolumn." .. name)
		if not ok then
			missing[#missing + 1] = string.format("%s (%s)", name, tostring(err))
		end
	end
	if #missing == 0 then
		health.ok("All submodules load: " .. table.concat(submodules, ", "))
	else
		health.error("Failed submodules: " .. table.concat(missing, "; "))
		return
	end

	local stc = package.loaded["beast.libs.statuscolumn"]
	if stc then
		health.ok("Module loaded")
	else
		health.warn("Module not loaded (require('beast.libs.statuscolumn').setup() not called)")
		return
	end

	-- =====================================================================
	-- FFI
	-- =====================================================================
	health.start("beast.libs.statuscolumn — FFI")

	local ffi = require("beast.libs.statuscolumn.ffi")
	local report = ffi.report()
	if not report.available then
		health.warn("FFI unavailable (no LuaJIT?). Fold producer + tick-based cache invalidation disabled.")
	else
		health.ok("FFI loaded")
		for sym, present in pairs(report.symbols) do
			if present then
				health.ok(string.format("symbol %s ✓", sym))
			else
				health.warn(string.format("symbol %s missing — feature degrades", sym))
			end
		end
	end

	-- =====================================================================
	-- Wiring
	-- =====================================================================
	health.start("beast.libs.statuscolumn — wiring")

	if vim.o.statuscolumn == STC_EXPR then
		health.ok("vim.o.statuscolumn wired to render()")
	elseif vim.o.statuscolumn == "" then
		health.warn("vim.o.statuscolumn empty — setup() not called, or option was cleared")
	else
		health.warn(string.format("vim.o.statuscolumn = %q (not the Beast renderer)", vim.o.statuscolumn))
	end

	local groups = vim.api.nvim_get_autocmds({ group = "BeastStatuscolumn" })
	if groups and #groups > 0 then
		health.ok(string.format("Augroup BeastStatuscolumn registered (%d autocmds)", #groups))
	else
		health.warn("Augroup BeastStatuscolumn has no autocmds (setup() not called?)")
	end

	-- =====================================================================
	-- Configuration
	-- =====================================================================
	health.start("beast.libs.statuscolumn — configuration")

	local config = require("beast.libs.statuscolumn.config")
	local segments = config.segments or {}
	if #segments == 0 then
		health.warn("segments is empty — column renders nothing")
	else
		health.ok(string.format("%d slot(s) configured", #segments))
		local bad = {}
		local bad_width = {}
		for i, slot in ipairs(segments) do
			local list = slot.producers or slot
			for _, p in ipairs(list) do
				if not VALID_PRODUCERS[p] then
					bad[#bad + 1] = string.format("slot %d: %q", i, p)
				end
			end
			if slot.width ~= nil and (type(slot.width) ~= "number" or slot.width < 1) then
				bad_width[#bad_width + 1] = string.format("slot %d: width=%s", i, tostring(slot.width))
			end
		end
		if #bad > 0 then
			health.error("Unknown producer(s): " .. table.concat(bad, ", "))
		else
			health.ok("All producers valid")
		end
		if #bad_width > 0 then
			health.error("Invalid width(s): " .. table.concat(bad_width, ", "))
		end
	end

	health.info(string.format("ft_ignore: %d entries", #(config.ft_ignore or {})))
	health.info(string.format("bt_ignore: %d entries", #(config.bt_ignore or {})))
	health.info(string.format("git.enabled = %s, fold.open = %s", tostring(config.git.enabled), tostring(config.fold.open)))

	-- =====================================================================
	-- Highlights
	-- =====================================================================
	health.start("beast.libs.statuscolumn — highlights")

	local expected = {
		"BeastStcNumber",
		"BeastStcDiagError",
		"BeastStcGitAdd",
		"BeastStcFold",
	}
	local missing_hl = {}
	for _, name in ipairs(expected) do
		local hl = vim.api.nvim_get_hl(0, { name = name, link = true })
		if not hl or vim.tbl_isempty(hl) then
			missing_hl[#missing_hl + 1] = name
		end
	end
	if #missing_hl == 0 then
		health.ok("Core highlight groups defined")
	else
		health.warn("Missing highlights: " .. table.concat(missing_hl, ", "))
	end

	-- =====================================================================
	-- Performance (cache-hit inline bench)
	-- =====================================================================
	health.start("beast.libs.statuscolumn — performance")

	if not stc.render then
		health.warn("render() missing — skipping bench")
		return
	end

	for _ = 1, 10 do
		stc.render()
	end

	collectgarbage("collect")
	local t0 = vim.uv.hrtime()
	for _ = 1, BENCH_RENDERS do
		stc.render()
	end
	local hot_us = (vim.uv.hrtime() - t0) / 1e3 / BENCH_RENDERS

	health.info(string.format("Bench (cache hit): %.2f µs/render (mean of %d)", hot_us, BENCH_RENDERS))
	health.info(string.format("Hard threshold: %d µs (cache-miss path)", FAIL_THRESHOLD_US))
	if hot_us > FAIL_THRESHOLD_US then
		health.error(
			string.format("Cache hit %.2f µs exceeds hard threshold — run `nvim --headless -l scripts/bench-statuscolumn.lua` for details", hot_us)
		)
	else
		health.ok(string.format("%.2f µs/render — within budget", hot_us))
	end
end

return M
