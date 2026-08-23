-- =========================================================================
-- Test: beast.libs.explorer.clipboard ("+" register read/write/toggle)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-explorer-clipboard.lua
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
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local clipboard = require("beast.libs.explorer.clipboard")

io.write("\n--- read() on an empty register ---\n")
vim.fn.setreg("+", "")
assert_eq("empty register decodes to nil", clipboard.read(), nil)

io.write("\n--- write()/read() round-trip: single path, copy ---\n")
clipboard.write({ "/tmp/a.txt" }, "copy")
assert_eq("round-trips single path + copy mode", clipboard.read(), { paths = { "/tmp/a.txt" }, mode = "copy" })

io.write("\n--- write()/read() round-trip: multiple paths, cut ---\n")
clipboard.write({ "/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt" }, "cut")
assert_eq("round-trips multiple paths + cut mode", clipboard.read(), { paths = { "/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt" }, mode = "cut" })

io.write("\n--- clear() empties the register ---\n")
clipboard.write({ "/tmp/a.txt" }, "copy")
clipboard.clear()
assert_eq("clear() makes read() nil", clipboard.read(), nil)
assert_eq("clear() blanks the raw register text", vim.fn.getreg("+"), "")

io.write("\n--- read() rejects content that isn't ours ---\n")
vim.fn.setreg("+", "hello world")
assert_eq("plain text with no mode line decodes to nil", clipboard.read(), nil)

vim.fn.setreg("+", "/tmp/a.txt\n/tmp/b.txt")
assert_eq("paths with no trailing mode line decodes to nil", clipboard.read(), nil)

vim.fn.setreg("+", "/tmp/a.txt\nmaybe")
assert_eq("trailing line that isn't copy/cut decodes to nil", clipboard.read(), nil)

vim.fn.setreg("+", "copy")
assert_eq("mode line with no paths above it decodes to nil", clipboard.read(), nil)

io.write("\n--- a path literally named 'copy' or 'cut' still round-trips ---\n")
clipboard.write({ "/tmp/copy" }, "cut")
assert_eq("path literal 'copy' + cut mode round-trips", clipboard.read(), { paths = { "/tmp/copy" }, mode = "cut" })

io.write("\n--- a trailing newline from the clipboard provider doesn't break decoding ---\n")
vim.fn.setreg("+", "/tmp/a.txt\ncopy\n")
assert_eq("trailing newline is tolerated", clipboard.read(), { paths = { "/tmp/a.txt" }, mode = "copy" })

io.write("\n--- toggle() ---\n")
clipboard.clear()
local result = clipboard.toggle({ "/tmp/a.txt" }, "copy")
assert_eq("toggle() on empty clipboard marks it", result, { paths = { "/tmp/a.txt" }, mode = "copy" })
assert_eq("register reflects the mark", clipboard.read(), { paths = { "/tmp/a.txt" }, mode = "copy" })

result = clipboard.toggle({ "/tmp/a.txt" }, "copy")
assert_eq("toggle() with same mode clears it", result, nil)
assert_eq("register is empty after toggling off", clipboard.read(), nil)

clipboard.write({ "/tmp/a.txt" }, "copy")
result = clipboard.toggle({ "/tmp/b.txt" }, "cut")
assert_eq("toggle() with a different mode overwrites instead of clearing", result, { paths = { "/tmp/b.txt" }, mode = "cut" })

clipboard.clear()

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
