-- =========================================================================
-- Test: beast.libs.select.filter (case-insensitive substring matcher)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-select-filter.lua
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
		io.write("  FAIL: " .. name .. " — expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local filter = require("beast.libs.select.filter")

io.write("\n--- empty query matches everything ---\n")
do
	assert_eq("empty query, non-empty text", filter.matches("dracula", ""), true)
	assert_eq("empty query, empty text", filter.matches("", ""), true)
end

io.write("\n--- case-insensitive substring match ---\n")
do
	assert_eq("exact match", filter.matches("dracula", "dracula"), true)
	assert_eq("uppercase query, lowercase text", filter.matches("dracula", "DRAC"), true)
	assert_eq("lowercase query, uppercase text", filter.matches("Dracula", "drac"), true)
	assert_eq("substring not at start", filter.matches("dracula-soft", "soft"), true)
end

io.write("\n--- literal (non-pattern) matching ---\n")
do
	assert_eq("magic pattern chars treated literally", filter.matches("a.b", ".b"), true)
	assert_eq("percent sign treated literally", filter.matches("100% done", "100%"), true)
end

io.write("\n--- no match ---\n")
do
	assert_eq("unrelated query", filter.matches("dracula", "zzz"), false)
	assert_eq("query longer than text", filter.matches("ab", "abc"), false)
end

io.write(string.format("\n--- %d passed, %d failed ---\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
