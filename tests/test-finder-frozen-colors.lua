-- =========================================================================
-- Test: finder frozen highlight namespaces (docs/dev-specs/finder-colorscheme-stable-menu.md)
--
-- Run as: nvim --clean --headless -l tests/test-finder-frozen-colors.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

-- highlights.lua reads the Theme / Util globals normally set up by beast.setup().
local colors = {
	dark2 = "#111111",
	dark1 = "#222222",
	background = "#333333",
	text = "#eeeeee",
	accent1 = "#ff0000",
	accent2 = "#ffaa00",
	accent3 = "#ffff00",
	accent4 = "#00ff00",
	accent5 = "#0000ff",
	accent6 = "#ff00ff",
	dimmed1 = "#aaaaaa",
	dimmed2 = "#999999",
	dimmed3 = "#888888",
	dimmed4 = "#777777",
	dimmed5 = "#666666",
}
Util = require("beast.util")
Theme = {
	get = function()
		return colors
	end,
}

local highlights = require("beast.libs.finder.highlights")

io.write("\n--- freeze snapshots the panel colors per window namespace ---\n")
local frozen = highlights.freeze()
local function hl(ns, name)
	return vim.api.nvim_get_hl(ns, { name = name })
end
assert_eq("list Normal bg is the list panel color", hl(frozen.list, "Normal").bg, tonumber("111111", 16))
assert_eq("input Normal bg is the prompt panel color", hl(frozen.input, "Normal").bg, tonumber("222222", 16))
assert_eq("input border blends into the prompt panel", hl(frozen.input, "FloatBorder").bg, tonumber("222222", 16))
assert_eq("end-of-buffer cells use the panel color", hl(frozen.list, "EndOfBuffer").bg, tonumber("111111", 16))
assert_eq("selected-row group is copied", hl(frozen.list, "BeastFinderListSelected").fg, tonumber("0000ff", 16))

io.write("\n--- swatch groups are defined in the list namespace ---\n")
local group = highlights.swatch("#abcdef")
assert_eq("swatch group lives in the frozen list namespace", hl(frozen.list, group).fg, tonumber("abcdef", 16))
assert_eq("swatch group is not global", next(vim.api.nvim_get_hl(0, { name = group })), nil)

io.write("\n--- a window namespace survives :colorscheme ---\n")
do
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 10, height = 2, style = "minimal" })
	vim.api.nvim_win_set_hl_ns(win, frozen.list)
	assert_eq("window is attached to the namespace", vim.api.nvim_get_hl_ns({ winid = win }), frozen.list)

	vim.cmd.colorscheme("default")
	vim.o.background = "light"
	vim.cmd.colorscheme("default")
	assert_eq("namespace Normal unchanged after :colorscheme", hl(frozen.list, "Normal").bg, tonumber("111111", 16))
	assert_eq("namespace swatch unchanged after :colorscheme", hl(frozen.list, group).fg, tonumber("abcdef", 16))
	vim.api.nvim_win_close(win, true)
end

io.write("\n--- unfreeze routes swatches to the global namespace again ---\n")
highlights.unfreeze()
local g2 = highlights.swatch("#123456")
assert_eq("swatch defined globally after unfreeze", vim.api.nvim_get_hl(0, { name = g2 }).fg, tonumber("123456", 16))

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
