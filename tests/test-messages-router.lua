-- =========================================================================
-- Test: beast.libs.messages (router rules + ui2 integration in an embedded nvim)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-messages-router.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local router = require("beast.libs.messages.router")
local routes = require("beast.libs.messages.config").routes

io.write("\n--- flatten ---\n")
assert_eq("joins chunks and trims", router.flatten({ { 0, " E492: " }, { 0, "Not an editor command: foo " } }), "E492: Not an editor command: foo")

io.write("\n--- resolve ---\n")
local r = router.resolve(routes, "emsg", "E486: Pattern not found: zzz")
assert_eq("E486 text", r and r.text, "Pattern not found: zzz")
assert_eq("E486 level", r and r.level, vim.log.levels.WARN)
assert_eq("E486 title", r and r.title, "Search")

r = router.resolve(routes, "wmsg", "search hit BOTTOM, continuing at TOP")
assert_eq("wrap forward", r and r.text, "Hit BOTTOM, continuing at TOP")
r = router.resolve(routes, "wmsg", "search hit TOP, continuing at BOTTOM")
assert_eq("wrap backward", r and r.text, "Hit TOP, continuing at BOTTOM")

r = router.resolve(routes, "search_count", " [2/3]")
assert_eq("search_count dropped", r and r.drop, true)

r = router.resolve(routes, "emsg", "E492: Not an editor command: foo")
assert_eq("other errors are error toasts", r and r.level, vim.log.levels.ERROR)
r = router.resolve(routes, "wmsg", "W10: Changing a readonly file")
assert_eq("other warnings are warn toasts", r and r.level, vim.log.levels.WARN)
r = router.resolve(routes, "emsg", "E5108: Error executing lua\nstack line 1\nstack line 2")
assert_eq("multi-line errors keep the first line + spill", r and r.text, "E5108: Error executing lua [+2]")

assert_eq("echo is left to ui2", router.resolve(routes, "echo", "hello"), nil)
assert_eq("list output is left to ui2", router.resolve(routes, "list_cmd", "  1 %a file"), nil)

io.write("\n--- ui2 integration (embedded nvim with a UI) ---\n")
local chan = vim.fn.jobstart({ "nvim", "--embed", "--clean" }, { rpc = true })
local function call(fn, ...)
	return vim.rpcrequest(chan, fn, ...)
end
call("nvim_ui_attach", 100, 30, {})
call(
	"nvim_exec_lua",
	[[
	vim.opt.runtimepath:prepend(...)
	package.path = (...) .. "/lua/?.lua;" .. (...) .. "/lua/?/init.lua;" .. package.path
	vim.o.cmdheight = 0
	_G.toasts = {}
	_G.Toast = function(msg, level, opts) _G.toasts[#_G.toasts + 1] = { msg, level, opts and opts.title } end
	require("beast.libs.messages").setup()
]],
	{ vim.fn.getcwd() }
)
assert_eq("router installed", call("nvim_exec_lua", "return require('beast.libs.messages').is_routing()", {}), true)

call("nvim_buf_set_lines", 0, 0, -1, false, { "abc", "abd" })
call("nvim_input", "/zzz<CR>")
vim.wait(300)
local toasts = call("nvim_exec_lua", "return _G.toasts", {})
assert_eq("not found becomes a toast", toasts[1] and toasts[1][1], "Pattern not found: zzz")
assert_eq("no hit-enter prompt", call("nvim_get_mode").blocking, false)

-- a failed search that wraps first emits "search hit BOTTOM" and then E486: only the error toast is shown
call("nvim_exec_lua", "_G.toasts = {}", {})
call("nvim_buf_set_lines", 0, 0, -1, false, { "abc", "abd" })
call("nvim_win_set_cursor", 0, { 2, 0 })
call("nvim_input", "/qqq<CR>")
vim.wait(300)
toasts = call("nvim_exec_lua", "return _G.toasts", {})
assert_eq("failed search shows one toast", #toasts, 1)
assert_eq("and it is the not-found one", toasts[1] and toasts[1][3], "Search")

call("nvim_input", ":nosuchcmd<CR>")
vim.wait(300)
toasts = call("nvim_exec_lua", "return _G.toasts", {})
assert_eq("unknown command becomes an error toast", toasts[#toasts] and toasts[#toasts][2], vim.log.levels.ERROR)
assert_eq("still not blocking", call("nvim_get_mode").blocking, false)

vim.fn.jobstop(chan)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
