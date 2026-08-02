-- =========================================================================
-- Test: Treesitter-driven indentexpr (lua/beast/libs/treesitter/indent.lua)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-treesitter-indent.lua
-- Exit code: 0 = PASS, 1 = FAIL
--
-- Uses the vendored fixture at tests/fixtures/queries/lua/indents.scm (a copy
-- of the real, upstream-synced lua/indents.scm) so the test doesn't depend on
-- stdpath('data')/site being populated or on network access. Exercises
-- get_indent() directly, matching the PM spec scenarios (docs/pm-specs/
-- treesitter-indent.md): nested-block open, closing-character dedent, deep
-- nesting, blank/comment lines, and whole-buffer reindent parity.
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/tests/fixtures")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local indent = require("beast.libs.treesitter.indent")

local passed = 0
local failed = 0

---@param name string
---@param got integer
---@param expected integer
local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " (got=" .. tostring(got) .. " expected=" .. tostring(expected) .. ")\n")
	end
end

---Create a scratch Lua buffer with treesitter started, sw=2.
---@param lines string[]
---@return integer buf
local function make_buf(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "lua"
	vim.bo[buf].shiftwidth = 2
	vim.bo[buf].tabstop = 2
	vim.bo[buf].expandtab = true
	vim.api.nvim_set_current_buf(buf)
	vim.treesitter.start(buf, "lua")
	return buf
end

-- =========================================================================
-- Scenario 1 + 4: opening a line inside a nested block accumulates depth
-- =========================================================================
io.write("\n== Nested block open (sw=2) ==\n")
do
	--[[
    1: local t = {
    2:   a = {
    3:     b = {
    4:
    5:     },
    6:   },
    7: }
  ]]
	local buf = make_buf({
		"local t = {",
		"  a = {",
		"    b = {",
		"",
		"    },",
		"  },",
		"}",
	})

	assert_eq("line 4 (3 levels deep inside table constructors) → 6", indent.get_indent(4), 6)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Scenario 2: typing a closing character dedents to match the opener
-- =========================================================================
io.write("\n== Closing character dedent (sw=2) ==\n")
do
	--[[
    1: function greet()
    2:   print("hi")
    3: end          <- over-indented before typing 'end', should resolve to 0
  ]]
	local buf = make_buf({
		"function greet()",
		"  print('hi')",
		"",
	})

	assert_eq("line 3 ('end' should align with 'function') → 0", indent.get_indent(3), 0)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Scenario 3: blank lines and comments get a sensible (not rigid) indent
-- =========================================================================
io.write("\n== Blank lines and comments (sw=2) ==\n")
do
	local buf = make_buf({
		"if true then",
		"",
		"end",
	})
	assert_eq("blank line inside if-block → 2", indent.get_indent(2), 2)
	vim.api.nvim_buf_delete(buf, { force = true })

	buf = make_buf({
		"function f()",
		"  -- a comment",
		"",
		"end",
	})
	assert_eq("blank line after a comment, still inside body → 2", indent.get_indent(3), 2)
	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Scenario 6: reindenting an existing (already correct) buffer is a no-op
-- =========================================================================
io.write("\n== Whole-buffer reindent parity (sw=2) ==\n")
do
	local lines = {
		"local function outer()",
		"  local function inner()",
		"    return 1",
		"  end",
		"  return inner()",
		"end",
	}
	local expected = { 0, 2, 4, 2, 2, 0 }
	local buf = make_buf(lines)

	for lnum, want in ipairs(expected) do
		assert_eq(("line %d matches its already-typed indent"):format(lnum), indent.get_indent(lnum), want)
	end

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
