-- =========================================================================
-- Test: Git word-level diff spans (hunk preview emphasis)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-git-word-diff.lua
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
		io.write("  FAIL: " .. name .. "\n")
		io.write("    expected: " .. vim.inspect(expected) .. "\n")
		io.write("    got:      " .. vim.inspect(got) .. "\n")
	end
end

local word_spans = require("beast.libs.git.diff").word_spans

---@param line string
---@param spans integer[][]
---@return string[]
local function texts(line, spans)
	local out = {}
	for i, sp in ipairs(spans) do
		out[i] = line:sub(sp[1] + 1, sp[2])
	end
	return out
end

io.write("\n== appended phrase ==\n")
do
	local old = "    if not confirmed then"
	local new = "    if not confirmed and vim.g.colors_name ~= original then"
	local o, n = word_spans(old, new)
	assert_eq("old side has no emphasis", o, {})
	assert_eq("new side marks only the phrase", texts(new, n), { "and vim.g.colors_name ~= original " })
end

io.write("\n== replaced word ==\n")
do
	local old, new = "local count = old_name(x)", "local count = new_name(x)"
	local o, n = word_spans(old, new)
	assert_eq("old word", texts(old, o), { "old_name" })
	assert_eq("new word", texts(new, n), { "new_name" })
end

io.write("\n== identical lines ==\n")
do
	local o, n = word_spans("same line", "same line")
	assert_eq("no spans on old", o, {})
	assert_eq("no spans on new", n, {})
end

io.write("\n== too different ==\n")
do
	local o, n = word_spans("foo(a, b)", "return bar")
	assert_eq("old is nil", o, nil)
	assert_eq("new is nil", n, nil)
end

io.write("\n== punctuation change ==\n")
do
	local old, new = "if a == b then", "if a ~= b then"
	local o, n = word_spans(old, new)
	assert_eq("old operator char", texts(old, o), { "=" })
	assert_eq("new operator char", texts(new, n), { "~" })
end

io.write("\n== whitespace-only change ==\n")
do
	local old, new = "local x = 1", "local  x = 1"
	local o, n = word_spans(old, new)
	assert_eq("old marks the single space", texts(old, o), { " " })
	assert_eq("new marks the double space", texts(new, n), { "  " })
end

io.write("\n== multibyte text ==\n")
do
	local old, new = "msg = 'héllo wörld'", "msg = 'héllo there wörld'"
	local o, n = word_spans(old, new)
	assert_eq("old has no emphasis", o, {})
	assert_eq("new marks the inserted word", texts(new, n), { "there " })
end

io.write("\n== over-length line ==\n")
do
	local long = string.rep("a", 1001)
	local o, n = word_spans(long, long .. "b")
	assert_eq("old is nil", o, nil)
	assert_eq("new is nil", n, nil)
end

io.write("\n== Summary ==\n")
io.write(("  Passed: %d\n  Failed: %d\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
