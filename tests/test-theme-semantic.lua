-- =========================================================================
-- Test: Theme semantic colors (red/yellow/green derived from the palette)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-theme-semantic.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Util = _G.Util or require("beast.util")

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local palette = require("beast.theme.palette")

--- Defaults with `overrides` applied (a fresh copy each time).
local function make(overrides)
	return vim.tbl_extend("force", vim.deepcopy(palette.defaults), overrides or {})
end

local function semantic(overrides)
	local p = palette.with_semantic(make(overrides))
	return p.red, p.yellow, p.green
end

-- default palette
do
	local r, y, g = semantic()
	assert_eq("default red", r, "#ffc0b9")
	assert_eq("default yellow", y, "#fce094")
	assert_eq("default green", g, "#b3f6c0")
end

-- accent slots are not trusted: shuffled order gives the same result
do
	local r, y, g = semantic({ accent1 = "#b3f6c0", accent2 = "#ffc0b9", accent3 = "#fce094" })
	assert_eq("shuffled red", r, "#ffc0b9")
	assert_eq("shuffled yellow", y, "#fce094")
	assert_eq("shuffled green", g, "#b3f6c0")
end

-- monokai-pro: accent2 is orange and must not win red or yellow
do
	local r, y, g = semantic({
		accent1 = "#ff6188",
		accent2 = "#fc9867",
		accent3 = "#ffd866",
		accent4 = "#a9dc76",
		accent5 = "#78dce8",
		accent6 = "#ab9df2",
	})
	assert_eq("monokai red", r, "#ff6188")
	assert_eq("monokai yellow", y, "#ffd866")
	assert_eq("monokai green", g, "#a9dc76")
end

-- a color is never picked twice, even when one color is closest to two targets
do
	local r, y, g = semantic({
		accent1 = "#ff6188",
		accent2 = "#a9dc76",
		accent3 = "#98d070",
		accent4 = "#88c060",
		accent5 = "#78b050",
		accent6 = "#68a040",
	})
	assert_eq("distinct: red", r, "#ff6188")
	assert_eq("distinct: yellow differs from red and green", y ~= r and y ~= g, true)
	assert_eq("distinct: green differs from red", g ~= r, true)
end

-- greys only: falls back to the default hexes
do
	local grey = {}
	for key in pairs(palette.defaults) do
		grey[key] = "#808080"
	end
	local p = palette.with_semantic(grey)
	assert_eq("fallback red", p.red, "#ffc0b9")
	assert_eq("fallback yellow", p.yellow, "#fce094")
	assert_eq("fallback green", p.green, "#b3f6c0")
end

-- base keys are untouched
do
	local p = palette.with_semantic(make())
	assert_eq("base key preserved", p.accent2, palette.defaults.accent2)
end

-- Theme.get() exposes them before and after refresh
do
	local theme = require("beast.theme")
	assert_eq("get() has red before refresh", type(theme.get().red), "string")
	vim.cmd.colorscheme("default")
	theme.refresh()
	local p = theme.get()
	assert_eq("get() has red after refresh", type(p.red), "string")
	assert_eq("get() has yellow after refresh", type(p.yellow), "string")
	assert_eq("get() has green after refresh", type(p.green), "string")
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
