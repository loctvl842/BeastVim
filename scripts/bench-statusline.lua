-- =========================================================================
-- Bench: Beast statusline render time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/statusline`.
--
-- Conforms to the bench contract documented in
-- `docs/tec-config/health-config.md` § "Run-time Render Performance":
--   * Run as: nvim --clean --headless -l scripts/bench-statusline.lua
--   * Final stdout line begins with `BENCH ` and includes name=statusline,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 1000 -- 1 ms full-bar render
local WARN_THRESHOLD_US = 50 -- soft target — anything slower is suspicious
local RENDERS_PER_RUN = 1000
local RUNS = 3
local LUALINE_PATHS = {
	"~/.local/share/LazyVim/lazy/lualine.nvim",
	"~/.local/share/nvim/lazy/lualine.nvim",
}

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stub palette so component highlights resolve (real config not loaded).
_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}

-- Open a real file buffer so file_bound and git_commit see a non-empty name.
local target_buf = "lua/beast/libs/statusline/init.lua"
local ok_edit = pcall(vim.cmd.edit, target_buf)
if not ok_edit then
	io.stderr:write("BENCH ERROR could not open " .. target_buf .. "\n")
	os.exit(2)
end
vim.go.laststatus = 3

-- Beast setup
local ok_stl, stl = pcall(require, "beast.libs.statusline")
if not ok_stl then
	io.stderr:write("BENCH ERROR could not load beast.libs.statusline: " .. tostring(stl) .. "\n")
	os.exit(2)
end
local C = require("beast.libs.statusline.components")
stl.setup({
	left = { C.mode, C.filename, C.git_branch, C.git_commit, C.diagnostics },
	right = { C.encoding, C.shiftwidth, C.filetype, C.position },
})

-- Trigger BufEnter so git_commit fetches once, wait for the async callback.
vim.api.nvim_exec_autocmds("BufEnter", {})
vim.wait(800, function()
	return stl.render():find("(", 1, true) ~= nil
end, 20)

vim.g.statusline_winid = vim.api.nvim_get_current_win()
vim.g.actual_curwin = vim.api.nvim_get_current_win()

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

local beast_us = bench(function()
	stl.render()
end)
print(string.format("Beast    %.2f µs/render  (mean of %d×%d)", beast_us, RUNS, RENDERS_PER_RUN))

-- =========================================================================
-- Lualine baseline (optional)
-- =========================================================================

local lualine_us, ratio_str = nil, "n/a"
for _, p in ipairs(LUALINE_PATHS) do
	if vim.fn.isdirectory(vim.fn.expand(p)) == 1 then
		vim.opt.runtimepath:prepend(vim.fn.expand(p))
		local ok = pcall(function()
			require("lualine").setup({})
		end)
		if ok then
			-- Pre-warm one render.
			vim.api.nvim_eval_statusline("%!v:lua.require'lualine'.statusline()", {
				winid = vim.api.nvim_get_current_win(),
			})
			lualine_us = bench(function()
				vim.api.nvim_eval_statusline("%!v:lua.require'lualine'.statusline()", {
					winid = vim.api.nvim_get_current_win(),
				})
			end)
			print(string.format("Lualine  %.2f µs/render  (mean of %d×%d)", lualine_us, RUNS, RENDERS_PER_RUN))
			ratio_str = string.format("%.1fx", lualine_us / beast_us)
			break
		end
	end
end
if not lualine_us then
	print("Lualine  n/a (plugin not found at any of " .. table.concat(LUALINE_PATHS, ", ") .. ")")
end

-- =========================================================================
-- Summary line + exit code
-- =========================================================================

print(
	string.format(
		"BENCH name=statusline beast=%.2fus lualine=%s ratio=%s threshold=%dus",
		beast_us,
		lualine_us and string.format("%.2fus", lualine_us) or "n/a",
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
