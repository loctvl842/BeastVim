-- =========================================================================
-- Test: beast.libs.searchcount (format cap + get() visibility rules)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-searchcount.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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

local sc = require("beast.libs.searchcount")

io.write("\n--- format ---\n")
assert_eq("small", sc.format(2, 3), "2/3")
assert_eq("at cap", sc.format(999, 999), "999/999")
assert_eq("total over cap", sc.format(1, 1000), "1/999+")
assert_eq("both over cap", sc.format(5000, 12000), "999+/999+")

io.write("\n--- get ---\n")
vim.o.hlsearch = true
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a", "", "x = local", "y", "local z" })
local win = vim.api.nvim_get_current_win()

assert_eq("nil before any search", sc.get(win), nil)

vim.cmd("normal! gg0")
vim.fn.setreg("/", "local")
vim.v.hlsearch = 1
local r = sc.get(win)
assert_eq("first match", r and r.text, "1/3")

vim.api.nvim_win_set_cursor(win, { 3, 4 })
r = sc.get(win)
assert_eq("second match", r and r.text, "2/3")

vim.api.nvim_win_set_cursor(win, { 4, 0 })
assert_eq("nil when cursor off a match", sc.get(win), nil)

vim.api.nvim_win_set_cursor(win, { 5, 0 })
vim.v.hlsearch = 0
assert_eq("nil when highlight cleared", sc.get(win), nil)

vim.v.hlsearch = 1
vim.fn.setreg("/", "zzz")
assert_eq("nil when no matches", sc.get(win), nil)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
