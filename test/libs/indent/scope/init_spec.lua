local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

---Run the indent strategy (`scope.find_by_indent`) at `pos` of a scratch buffer and return the
---scopes without their `buf` field (nil when there is no scope).
---@param lines string[]
---@param sw integer
---@param pos {[1]: integer, [2]: integer}
---@return {from: integer, to: integer, indent: integer}[]?
local function find(lines, sw, pos)
	return n.exec_lua(function(l, shiftwidth, p)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, l)
		vim.bo[buf].shiftwidth = shiftwidth
		vim.bo[buf].tabstop = shiftwidth
		vim.bo[buf].expandtab = true
		vim.api.nvim_set_current_buf(buf)
		local scopes = require("beast.libs.indent.scope").find_by_indent(buf, p)
		if not scopes then
			return nil
		end
		local result = {}
		for _, s in ipairs(scopes) do
			result[#result + 1] = { from = s.from, to = s.to, indent = s.indent }
		end
		return result
	end, lines, sw, pos)
end

---Register one `it` per case: `{ line, name, expected }` against `lines`.
---@param lines string[]
---@param cases { [1]: integer, [2]: string, [3]: table? }[]
local function cases(lines, cases)
	for _, c in ipairs(cases) do
		t.it(("line %d %s"):format(c[1], c[2]), function()
			t.eq(c[3], find(lines, 2, { c[1], 0 }))
		end)
	end
end

local function scope(from, to, indent)
	return { { from = from, to = to, indent = indent } }
end

t.describe("indent scope detection (indent strategy)", function()
	t.before_each(h.clear)

	t.describe("simple function body (sw=2)", function()
		cases({
			"local a = 1",
			"",
			"function foo()",
			"  local x = 1",
			"  local y = 2",
			"  return x + y",
			"end",
			"",
			"local b = 2",
		}, {
			{ 1, "(top-level local, next is blank) -> nil", nil },
			{ 2, "(blank between top-level) -> nil", nil },
			{ 3, "(function decl, edge into body) -> {4,6,2}", scope(4, 6, 2) },
			{ 4, "(inside function body) -> {4,6,2}", scope(4, 6, 2) },
			{ 5, "(inside function body) -> {4,6,2}", scope(4, 6, 2) },
			{ 6, "(inside function body) -> {4,6,2}", scope(4, 6, 2) },
			{ 7, "(end, closing edge into body) -> {4,6,2}", scope(4, 6, 2) },
			{ 8, "(blank between top-level) -> nil", nil },
			{ 9, "(top-level local) -> nil", nil },
		})
	end)

	t.describe("nested scopes (sw=2)", function()
		cases({
			"function foo()",
			"  local x = 1",
			"  if true then",
			"    return x",
			"  end",
			"end",
		}, {
			{ 1, "(function decl, edge into body) -> {2,5,2}", scope(2, 5, 2) },
			{ 2, "(body, indent 2) -> {2,5,2}", scope(2, 5, 2) },
			{ 3, "(if-edge, steps into body) -> {4,4,4}", scope(4, 4, 4) },
			{ 4, "(nested body, indent 4) -> {4,4,4}", scope(4, 4, 4) },
			{ 5, "(end at indent 2, closing edge into body) -> {4,4,4}", scope(4, 4, 4) },
			{ 6, "(end, closing edge into body) -> {2,5,2}", scope(2, 5, 2) },
		})
	end)

	t.describe("blank line inside scope (sw=2)", function()
		cases({
			"function foo()",
			"  local x = 1",
			"",
			"  local y = 2",
			"end",
		}, {
			{ 3, "(blank inside scope) -> {2,4,2}", scope(2, 4, 2) },
		})
	end)

	t.describe("blank between top-level and indented (the original bug)", function()
		cases({
			'require("beast").setup()',
			"",
			"function foo()",
			"  local x = 1",
			"  local y = 2",
			"  return x + y",
			"end",
		}, {
			{ 1, "(require, indent 0) -> nil", nil },
			{ 2, "(blank between top-level and func) -> nil", nil },
			{ 3, "(function decl, edge into body) -> {4,6,2}", scope(4, 6, 2) },
			{ 4, "(body) -> {4,6,2}", scope(4, 6, 2) },
		})
	end)

	t.describe("if-block at top level (Beast init.lua pattern)", function()
		cases({
			'if os.getenv("BEAST_PROFILE") == "1" then',
			"  pcall(function()",
			'    local profile = require("beast.profile")',
			"    profile.start()",
			"  end)",
			"end",
			"",
			'require("beast").setup()',
		}, {
			{ 1, "(if, indent 0, edge into body) -> {2,5,2}", scope(2, 5, 2) },
			{ 2, "(pcall edge, steps into body) -> {3,4,4}", scope(3, 4, 4) },
			{ 3, "(inside pcall body) -> {3,4,4}", scope(3, 4, 4) },
			{ 5, "(end), closing edge into body) -> {3,4,4}", scope(3, 4, 4) },
			{ 6, "(end, closing edge into body) -> {2,5,2}", scope(2, 5, 2) },
			{ 7, "(blank) -> nil", nil },
			{ 8, "(require, indent 0) -> nil", nil },
		})
	end)

	t.describe("setmetatable pattern (sw=2)", function()
		cases({
			"local M = setmetatable({}, {",
			"  __call = function(self, cwd)",
			"    return self.toggle(cwd)",
			"  end,",
			"})",
		}, {
			{ 1, "(setmetatable, edge into body) -> {2,4,2}", scope(2, 4, 2) },
			{ 2, "(edge, steps into body) -> {3,3,4}", scope(3, 3, 4) },
			{ 3, "(inside nested body) -> {3,3,4}", scope(3, 3, 4) },
			{ 4, "(end at indent 2, closing edge) -> {3,3,4}", scope(3, 3, 4) },
			{ 5, "(closing, edge into body) -> {2,4,2}", scope(2, 4, 2) },
		})
	end)

	t.describe("multiple blank lines between scopes (sw=2)", function()
		cases({
			"function a()",
			"  return 1",
			"end",
			"",
			"",
			"function b()",
			"  return 2",
			"end",
		}, {
			{ 4, "(blank gap) -> nil", nil },
			{ 5, "(blank gap) -> nil", nil },
		})
	end)

	t.describe("closing end of nested function (sw=2)", function()
		cases({
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
		}, {
			{ 16, "(end at indent 2, closing edge into body) -> {13,15,4}", scope(13, 15, 4) },
		})
	end)
end)
