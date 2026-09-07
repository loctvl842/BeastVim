-- =====================================================================
-- Test: SSH-without-display OSC52 clipboard provider (beast.option)
-- =====================================================================
-- Run as: nvim --clean --headless -l tests/test-osc52-provider.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =====================================================================
-- Regression test for the provider's copy cache: Neovim calls paste() on
-- every read of "+" and overwrites the internal register with the result, so
-- a paste() that cannot answer (OSC52 query is refused by terminals) must
-- serve the last value this session copied. Otherwise `p` after y/d/x fails
-- with E353 (nothing in register).
-- =====================================================================

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

-- Force the SSH-without-display branch in option.lua regardless of where the
-- test itself runs.
vim.fn.setenv("SSH_TTY", "/dev/pts/9")
vim.fn.setenv("DISPLAY", "")
vim.fn.setenv("WAYLAND_DISPLAY", "")

require("beast.option")

assert_test("provider installed over SSH without a display", vim.g.clipboard ~= nil and vim.g.clipboard.name == "OSC 52")

io.write("\n--- paste() on a fresh session (nothing copied yet) ---\n")
do
	local notify_count = 0
	local saved_notify = vim.notify
	vim.notify = function(...)
		notify_count = notify_count + 1
		return saved_notify(...)
	end

	local text = vim.fn.getreg("+")
	local regtype = vim.fn.getregtype("+")
	vim.notify = saved_notify

	-- The warn stub returns { "" }, which Neovim normalizes to an empty
	-- linewise register (nothing pastable, no error data).
	assert_test("empty cache reads as an empty register", text == "" and regtype == "V", "got <" .. text .. "> type <" .. regtype .. ">")
	-- Each explicit register read (getreg, getregtype) queries paste() once.
	assert_test("empty cache paste() warns about the terminal's native paste", notify_count == 2, "notify_count=" .. notify_count)
end

io.write("\n--- copy/paste round-trip through the provider ---\n")
do
    vim.fn.setreg("+", { "hello" }, "v")
    assert_test("charwise round-trip: text", vim.fn.getreg("+") == "hello", "got <" .. vim.fn.getreg("+") .. ">")
    assert_test("charwise round-trip: regtype", vim.fn.getregtype("+") == "v", "got <" .. vim.fn.getregtype("+") .. ">")

    vim.fn.setreg("+", { "line one", "line two" }, "V")
    local linewise = vim.fn.getreg("+")
    assert_test("linewise round-trip: text", linewise == "line one\nline two\n", "got <" .. linewise .. ">")
    assert_test("linewise round-trip: regtype", vim.fn.getregtype("+") == "V", "got <" .. vim.fn.getregtype("+") .. ">")

    vim.fn.setreg("+", { "ab", "cd" }, "b")
    assert_test("blockwise round-trip: text", vim.fn.getreg("+") == "ab\ncd", "got <" .. vim.fn.getreg("+") .. ">")
    assert_test("blockwise round-trip: regtype", vim.fn.getregtype("+") == "\22" .. "2", "got <" .. vim.fn.getregtype("+") .. ">")
end

io.write("\n--- reads stay quiet once something has been copied ---\n")
do
    local notify_count = 0
    local saved_notify = vim.notify
    vim.notify = function(...)
        notify_count = notify_count + 1
        return saved_notify(...)
    end

    vim.fn.setreg("+", { "quiet" }, "v")
    assert_test("cached reads do not fire the warning notify", notify_count == 0, "notify_count=" .. notify_count)
    vim.notify = saved_notify
end

io.write(string.format("\n== %d passed, %d failed ==\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
