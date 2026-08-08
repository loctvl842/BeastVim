-- =========================================================================
-- Test: beast.libs.input.position (cursor-anchored vs. centered-fallback)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-input-position.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Util = require("beast.util")
_G.View = Util.mod("beast.libs.view")

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local position = require("beast.libs.input.position")
local BOX_HEIGHT = 3

--- Fill the current buffer with `n` lines and put the cursor on `line`,
--- scrolled so `line` lands at the given window-relative row.
---@param n integer
---@param line integer
---@param scroll_cmd string  normal-mode command to position the viewport ("zt"/"zz")
local function setup_buffer(n, line, scroll_cmd)
	local lines = {}
	for i = 1, n do
		lines[i] = "line " .. i
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	vim.cmd("normal! " .. scroll_cmd)
end

--- Like setup_buffer, but sets an exact topline so the cursor lands at a
--- precise screen row — needed to hit the above/below boundary exactly.
---@param n integer
---@param line integer
---@param topline integer
local function setup_buffer_exact_topline(n, line, topline)
	local lines = {}
	for i = 1, n do
		lines[i] = "line " .. i
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	vim.fn.winrestview({ topline = topline })
end

io.write("\n--- cursor-anchored: plenty of room above -> anchor SW ---\n")
do
	vim.bo.buftype = ""
	setup_buffer(40, 20, "zz")
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "cursor")
	assert_eq("anchor", result.anchor, "SW")
end

io.write("\n--- cursor-anchored: no room above -> anchor NW (flip below) ---\n")
do
	vim.bo.buftype = ""
	setup_buffer(40, 1, "zt")
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "cursor")
	assert_eq("anchor", result.anchor, "NW")
end

io.write("\n--- boundary: room_above exactly BOX_HEIGHT -> anchor SW ---\n")
do
	vim.bo.buftype = ""
	setup_buffer_exact_topline(40, 20, 20 - BOX_HEIGHT)
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "cursor")
	assert_eq("anchor", result.anchor, "SW")
end

io.write("\n--- boundary: room_above one less than BOX_HEIGHT -> anchor NW ---\n")
do
	vim.bo.buftype = ""
	setup_buffer_exact_topline(40, 20, 20 - (BOX_HEIGHT - 1))
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "cursor")
	assert_eq("anchor", result.anchor, "NW")
end

io.write("\n--- special buftype -> centered fallback ---\n")
do
	setup_buffer(40, 20, "zz")
	vim.bo.buftype = "nofile"
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "center")
	assert_eq("anchor", result.anchor, nil)
	vim.bo.buftype = ""
end

io.write("\n--- current window is floating -> centered fallback ---\n")
do
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 0,
		col = 0,
		width = 10,
		height = 5,
		style = "minimal",
	})
	local result = position.resolve(BOX_HEIGHT)
	assert_eq("mode", result.mode, "center")
	assert_eq("anchor", result.anchor, nil)
	vim.api.nvim_win_close(win, true)
end

io.write("\n--- " .. passed .. " passed, " .. failed .. " failed ---\n")
os.exit(failed == 0 and 0 or 1)
