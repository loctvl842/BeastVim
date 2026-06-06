-- =========================================================================
-- Bench: Beast tabline render time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/tabline`.
--
-- Conforms to the bench contract documented in
-- `docs/tec-config/health-config.md` § "Run-time Render Performance":
--   * Run as: nvim --clean --headless -l scripts/bench-tabline.lua
--   * Final stdout line begins with `BENCH ` and includes name=tabline,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 1000 -- 1 ms full-bar render
local WARN_THRESHOLD_US = 50 -- soft target — anything slower is suspicious
local RENDERS_PER_RUN = 1000
local RUNS = 3
local BUFFERLINE_PATHS = {
	"~/.local/share/LazyVim/lazy/bufferline.nvim",
	"~/.local/share/nvim/lazy/bufferline.nvim",
}

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stub globals so highlights resolve (real config not loaded).
_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = {
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
_G.View = setmetatable({
	buf = { delete = function() end },
}, {
	__index = function()
		return function() end
	end,
})

-- Open multiple buffers to simulate a realistic tabline.
local test_files = {
	"lua/beast/libs/tabline/init.lua",
	"lua/beast/libs/tabline/config.lua",
	"lua/beast/libs/tabline/context.lua",
	"lua/beast/libs/tabline/buffers.lua",
	"lua/beast/libs/tabline/name.lua",
	"lua/beast/libs/tabline/icons.lua",
	"lua/beast/libs/tabline/highlights.lua",
	"lua/beast/libs/tabline/truncate.lua",
	"lua/beast/libs/tabline/sections/cell.lua",
	"lua/beast/libs/tabline/sections/buffer_list.lua",
}
for _, f in ipairs(test_files) do
	local ok_edit = pcall(vim.cmd.edit, f)
	if not ok_edit then
		io.stderr:write("BENCH WARN could not open " .. f .. "\n")
	end
end

-- Beast setup
local ok_tl, tabline = pcall(require, "beast.libs.tabline")
if not ok_tl then
	io.stderr:write("BENCH ERROR could not load beast.libs.tabline: " .. tostring(tabline) .. "\n")
	os.exit(2)
end

-- Setup without actually setting vim.o.tabline (we call render directly)
local ok_cfg = pcall(function()
	require("beast.libs.tabline.config").setup({})
end)
if not ok_cfg then
	io.stderr:write("BENCH ERROR could not setup tabline config\n")
	os.exit(2)
end

-- Pre-warm one render.
local ok_render, err = pcall(tabline.render)
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
-- Beast bench (required)
-- =========================================================================

-- Cold render: force dirty on every iteration (simulates event-driven rebuild)
local beast_cold_us = bench(function()
	-- Simulate event: mark dirty so render() does a full rebuild
	tabline._invalidate()
	tabline.render()
end)
print(string.format("Beast (cold) %.2f µs/render  (%d bufs, mean of %d×%d)", beast_cold_us, #test_files, RUNS, RENDERS_PER_RUN))

-- Hot render: cached path (no events between redraws)
local beast_hot_us = bench(function()
	tabline.render()
end)
print(string.format("Beast (hot)  %.2f µs/render  (%d bufs, mean of %d×%d)", beast_hot_us, #test_files, RUNS, RENDERS_PER_RUN))

-- Use cold render for the primary metric (worst case)
local beast_us = beast_cold_us

-- =========================================================================
-- Bufferline baseline (optional)
-- =========================================================================

local bufferline_us, ratio_str = nil, "n/a"
for _, p in ipairs(BUFFERLINE_PATHS) do
	if vim.fn.isdirectory(vim.fn.expand(p)) == 1 then
		vim.opt.runtimepath:prepend(vim.fn.expand(p))
		local ok = pcall(function()
			require("bufferline").setup({})
		end)
		if ok then
			-- Pre-warm one render.
			pcall(function()
				vim.api.nvim_eval_statusline(vim.o.tabline, {
					use_tabline = true,
				})
			end)
			bufferline_us = bench(function()
				pcall(function()
					vim.api.nvim_eval_statusline(vim.o.tabline, {
						use_tabline = true,
					})
				end)
			end)
			print(string.format("Bufferline %.2f µs/render  (mean of %d×%d)", bufferline_us, RUNS, RENDERS_PER_RUN))
			ratio_str = string.format("%.1fx", bufferline_us / beast_us)
			break
		end
	end
end
if not bufferline_us then
	print("Bufferline n/a (plugin not found at any of " .. table.concat(BUFFERLINE_PATHS, ", ") .. ")")
end

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(
	string.format(
		"BENCH name=tabline beast=%.2fus bufferline=%s ratio=%s threshold=%dus",
		beast_us,
		bufferline_us and string.format("%.2fus", bufferline_us) or "n/a",
		ratio_str,
		FAIL_THRESHOLD_US
	)
)

if beast_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.2f µs > %d µs threshold\n", beast_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if beast_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.2f µs > %d µs soft target (investigate)\n", beast_us, WARN_THRESHOLD_US))
end

os.exit(0)
