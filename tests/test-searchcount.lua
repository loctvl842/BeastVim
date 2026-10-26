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

io.write("\n--- get past the cap ---\n")
do
	local many = {}
	for i = 1, 1500 do
		many[i] = "local x"
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, many)
	vim.fn.setreg("/", "local")
	vim.v.hlsearch = 1
	vim.api.nvim_win_set_cursor(win, { 1200, 0 })
	r = sc.get(win)
	assert_eq("index and total capped", r and r.text, "999+/999+")
	vim.api.nvim_win_set_cursor(win, { 1200, 3 })
	assert_eq("nil when off a match past the cap", sc.get(win), nil)
end

io.write("\n--- search keys only toast for real searches ---\n")
do
	local toasts = {}
	_G.Toast = function(msg)
		toasts[#toasts + 1] = msg
	end
	package.loaded["beast"] = { apply_highlights = function() end } -- theme globals are not loaded under --clean
	sc.setup()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "abc" })
	vim.fn.setreg("/", "zzz")
	vim.api.nvim_feedkeys("in\27", "tx", false)
	vim.wait(50)
	assert_eq("n typed in insert mode", #toasts, 0)
	vim.api.nvim_feedkeys("fn", "tx", false)
	vim.wait(50)
	assert_eq("n as the target of f", #toasts, 0)
	vim.api.nvim_feedkeys("n", "tx", false)
	vim.wait(50)
	assert_eq("n in normal mode with no match", #toasts, 1)
end

io.write("\n--- is_wrap ---\n")
assert_eq("forward wraps to earlier pos", sc.is_wrap(true, { 5, 0 }, { 1, 0 }), true)
assert_eq("forward same-line earlier col wraps", sc.is_wrap(true, { 2, 8 }, { 2, 1 }), true)
assert_eq("forward normal jump", sc.is_wrap(true, { 1, 0 }, { 5, 0 }), false)
assert_eq("backward wraps to later pos", sc.is_wrap(false, { 1, 0 }, { 5, 0 }), true)
assert_eq("backward normal jump", sc.is_wrap(false, { 5, 0 }, { 1, 0 }), false)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
