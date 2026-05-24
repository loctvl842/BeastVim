-- =========================================================================
-- Test: Indent scope detection
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-indent-scope.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stubs for globals
_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = {
	colors = {
		set_hl = function() end,
	},
}

-- =========================================================================
-- Test helpers
-- =========================================================================

local passed = 0
local failed = 0

local function assert_eq(name, got, expected)
	local function tbl_eq(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for k, v in pairs(a) do
			if not tbl_eq(v, b[k]) then return false end
		end
		for k in pairs(b) do
			if a[k] == nil then return false end
		end
		return true
	end

	if tbl_eq(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n")
		io.write("    expected: " .. vim.inspect(expected) .. "\n")
		io.write("    got:      " .. vim.inspect(got) .. "\n")
	end
end

---Create a scratch buffer with given lines and shiftwidth.
---Sets it as the current buffer so vim.fn.indent() works.
---@param lines string[]
---@param sw integer
---@return integer buf
local function make_buf(lines, sw)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].shiftwidth = sw
	vim.bo[buf].tabstop = sw
	vim.bo[buf].expandtab = true
	vim.api.nvim_set_current_buf(buf)
	return buf
end

---Strip buf field from scopes for easier comparison.
---@param scopes Beast.Indent.Scope[]?
---@return table[]?
local function strip_buf(scopes)
	if not scopes then return nil end
	local result = {}
	for _, scope in ipairs(scopes) do
		table.insert(result, { from = scope.from, to = scope.to, indent = scope.indent })
	end
	return result
end

-- =========================================================================
-- Load scope module
-- =========================================================================

local scope = require("beast.libs.indent.scope")

-- =========================================================================
-- Test: Simple function body
-- =========================================================================
io.write("\n== Simple function body (sw=2) ==\n")
do
	--[[
    1: local a = 1
    2:
    3: function foo()
    4:   local x = 1
    5:   local y = 2
    6:   return x + y
    7: end
    8:
    9: local b = 2
  ]]
	local buf = make_buf({
		"local a = 1",
		"",
		"function foo()",
		"  local x = 1",
		"  local y = 2",
		"  return x + y",
		"end",
		"",
		"local b = 2",
	}, 2)

	assert_eq("line 1 (top-level local, next is blank) → nil", strip_buf(scope.find(buf, { 1, 0 })), nil)

	assert_eq("line 2 (blank between top-level) → nil", strip_buf(scope.find(buf, { 2, 0 })), nil)

	assert_eq(
		"line 3 (function decl, edge into body) → {4,6,2}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq(
		"line 4 (inside function body) → {4,6,2}",
		strip_buf(scope.find(buf, { 4, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq(
		"line 5 (inside function body) → {4,6,2}",
		strip_buf(scope.find(buf, { 5, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq(
		"line 6 (inside function body) → {4,6,2}",
		strip_buf(scope.find(buf, { 6, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq(
		"line 7 (end, closing edge into body) → {4,6,2}",
		strip_buf(scope.find(buf, { 7, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq("line 8 (blank between top-level) → nil", strip_buf(scope.find(buf, { 8, 0 })), nil)

	assert_eq("line 9 (top-level local) → nil", strip_buf(scope.find(buf, { 9, 0 })), nil)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: Nested scopes
-- =========================================================================
io.write("\n== Nested scopes (sw=2) ==\n")
do
	--[[
    1: function foo()
    2:   local x = 1
    3:   if true then
    4:     return x
    5:   end
    6: end
  ]]
	local buf = make_buf({
		"function foo()",
		"  local x = 1",
		"  if true then",
		"    return x",
		"  end",
		"end",
	}, 2)

	assert_eq(
		"line 1 (function decl, edge into body) → {2,5,2}",
		strip_buf(scope.find(buf, { 1, 0 })),
		{ { from = 2, to = 5, indent = 2 } }
	)

	assert_eq(
		"line 2 (body, indent 2) → {2,5,2}",
		strip_buf(scope.find(buf, { 2, 0 })),
		{ { from = 2, to = 5, indent = 2 } }
	)

	assert_eq(
		"line 3 (if-edge, steps into body) → {4,4,4}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 4, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 4 (nested body, indent 4) → {4,4,4}",
		strip_buf(scope.find(buf, { 4, 0 })),
		{ { from = 4, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 5 (end at indent 2, closing edge into body) → {4,4,4}",
		strip_buf(scope.find(buf, { 5, 0 })),
		{ { from = 4, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 6 (end, closing edge into body) → {2,5,2}",
		strip_buf(scope.find(buf, { 6, 0 })),
		{ { from = 2, to = 5, indent = 2 } }
	)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: Blank line inside scope
-- =========================================================================
io.write("\n== Blank line inside scope (sw=2) ==\n")
do
	--[[
    1: function foo()
    2:   local x = 1
    3:
    4:   local y = 2
    5: end
  ]]
	local buf = make_buf({
		"function foo()",
		"  local x = 1",
		"",
		"  local y = 2",
		"end",
	}, 2)

	assert_eq(
		"line 3 (blank inside scope) → {2,4,2}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 2, to = 4, indent = 2 } }
	)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: Blank between top-level and indented (the original bug)
-- =========================================================================
io.write("\n== Blank between top-level and indented (sw=2) ==\n")
do
	--[[
    1: require("beast").setup()
    2:
    3: function foo()
    4:   local x = 1
    5:   local y = 2
    6:   return x + y
    7: end
  ]]
	local buf = make_buf({
		'require("beast").setup()',
		"",
		"function foo()",
		"  local x = 1",
		"  local y = 2",
		"  return x + y",
		"end",
	}, 2)

	assert_eq("line 1 (require, indent 0) → nil", strip_buf(scope.find(buf, { 1, 0 })), nil)

	assert_eq("line 2 (blank between top-level and func) → nil", strip_buf(scope.find(buf, { 2, 0 })), nil)

	assert_eq(
		"line 3 (function decl, edge into body) → {4,6,2}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	assert_eq(
		"line 4 (body) → {4,6,2}",
		strip_buf(scope.find(buf, { 4, 0 })),
		{ { from = 4, to = 6, indent = 2 } }
	)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: if-block at top level (Beast init.lua pattern)
-- =========================================================================
io.write("\n== if-block at top level (sw=2) ==\n")
do
	--[[
    1: if os.getenv("BEAST_PROFILE") == "1" then
    2:   pcall(function()
    3:     local profile = require("beast.profile")
    4:     profile.start()
    5:   end)
    6: end
    7:
    8: require("beast").setup()
  ]]
	local buf = make_buf({
		'if os.getenv("BEAST_PROFILE") == "1" then',
		"  pcall(function()",
		'    local profile = require("beast.profile")',
		"    profile.start()",
		"  end)",
		"end",
		"",
		'require("beast").setup()',
	}, 2)

	assert_eq(
		"line 1 (if, indent 0, edge into body) → {2,5,2}",
		strip_buf(scope.find(buf, { 1, 0 })),
		{ { from = 2, to = 5, indent = 2 } }
	)

	assert_eq(
		"line 2 (pcall edge, steps into body) → {3,4,4}",
		strip_buf(scope.find(buf, { 2, 0 })),
		{ { from = 3, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 3 (inside pcall body) → {3,4,4}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 3, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 5 (end), closing edge into body) → {3,4,4}",
		strip_buf(scope.find(buf, { 5, 0 })),
		{ { from = 3, to = 4, indent = 4 } }
	)

	assert_eq(
		"line 6 (end, closing edge into body) → {2,5,2}",
		strip_buf(scope.find(buf, { 6, 0 })),
		{ { from = 2, to = 5, indent = 2 } }
	)

	assert_eq("line 7 (blank) → nil", strip_buf(scope.find(buf, { 7, 0 })), nil)

	assert_eq("line 8 (require, indent 0) → nil", strip_buf(scope.find(buf, { 8, 0 })), nil)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: setmetatable pattern
-- =========================================================================
io.write("\n== setmetatable pattern (sw=2) ==\n")
do
	--[[
    1: local M = setmetatable({}, {
    2:   __call = function(self, cwd)
    3:     return self.toggle(cwd)
    4:   end,
    5: })
  ]]
	local buf = make_buf({
		"local M = setmetatable({}, {",
		"  __call = function(self, cwd)",
		"    return self.toggle(cwd)",
		"  end,",
		"})",
	}, 2)

	assert_eq(
		"line 1 (setmetatable, edge into body) → {2,4,2}",
		strip_buf(scope.find(buf, { 1, 0 })),
		{ { from = 2, to = 4, indent = 2 } }
	)

	assert_eq(
		"line 2 (edge, steps into body) → {3,3,4}",
		strip_buf(scope.find(buf, { 2, 0 })),
		{ { from = 3, to = 3, indent = 4 } }
	)

	assert_eq(
		"line 3 (inside nested body) → {3,3,4}",
		strip_buf(scope.find(buf, { 3, 0 })),
		{ { from = 3, to = 3, indent = 4 } }
	)

	assert_eq(
		"line 4 (end at indent 2, closing edge) → {3,3,4}",
		strip_buf(scope.find(buf, { 4, 0 })),
		{ { from = 3, to = 3, indent = 4 } }
	)

	assert_eq(
		"line 5 (closing, edge into body) → {2,4,2}",
		strip_buf(scope.find(buf, { 5, 0 })),
		{ { from = 2, to = 4, indent = 2 } }
	)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: Multiple blank lines between scopes
-- =========================================================================
io.write("\n== Multiple blank lines between scopes (sw=2) ==\n")
do
	--[[
    1: function a()
    2:   return 1
    3: end
    4:
    5:
    6: function b()
    7:   return 2
    8: end
  ]]
	local buf = make_buf({
		"function a()",
		"  return 1",
		"end",
		"",
		"",
		"function b()",
		"  return 2",
		"end",
	}, 2)

	assert_eq("line 4 (blank gap) → nil", strip_buf(scope.find(buf, { 4, 0 })), nil)

	assert_eq("line 5 (blank gap) → nil", strip_buf(scope.find(buf, { 5, 0 })), nil)

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- =========================================================================
-- Test: Closing end of nested function (user's current.txt case)
-- =========================================================================
io.write("\n== Closing end of nested function (sw=2) ==\n")
do
	--[[
    1: if os.getenv("BEAST_PROFILE") == "1" then
    2:   pcall(function()
    3:     local profile = require("beast.profile")
    4:     profile.start()
    5:     local out = os.getenv("BEAST_PROFILE_OUT")
    6:     profile.auto_dump_on_quit(out)
    7:   end)
    8: end
    9:
    10: require("beast").setup()
    11:
    12:   function foo()
    13:     local x = 1
    14:     local y = 2
    15:     return x + y
    16:   end
  ]]
	local buf = make_buf({
		'if os.getenv("BEAST_PROFILE") == "1" then',
		"  pcall(function()",
		'    local profile = require("beast.profile")',
		"    profile.start()",
		'    local out = os.getenv("BEAST_PROFILE_OUT")',
		"    profile.auto_dump_on_quit(out)",
		"  end)",
		"end",
		"",
		'require("beast").setup()',
		"",
		"  function foo()",
		"    local x = 1",
		"    local y = 2",
		"    return x + y",
		"  end",
	}, 2)

	assert_eq(
		"line 16 (end at indent 2, closing edge into body) → {13,15,4}",
		strip_buf(scope.find(buf, { 16, 0 })),
		{ { from = 13, to = 15, indent = 4 } }
	)

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
