local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Treesitter-driven indentexpr (lua/beast/libs/treesitter/indent.lua).
--
-- Uses the vendored fixture at test/libs/treesitter/fixtures/queries/lua/indents.scm (a copy of the
-- real, upstream-synced lua/indents.scm) so the spec doesn't depend on
-- stdpath('data')/site being populated or on network access. Exercises get_indent()
-- directly, matching the PM spec scenarios (docs/pm-specs/treesitter-indent.md).
t.describe("treesitter indent", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/test/libs/treesitter/fixtures")
			---Scratch Lua buffer with treesitter started, sw=2.
			_G.make_buf = function(lines)
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
		end)
	end)

	---Indent get_indent() computes for each of `lnums` in a buffer of `lines`.
	---@param lines string[]
	---@param lnums integer[]
	---@return integer[]
	local function indents(lines, lnums)
		return n.exec_lua(function(l, nums)
			_G.make_buf(l)
			local indent = require("beast.libs.treesitter.indent")
			local out = {}
			for i, lnum in ipairs(nums) do
				out[i] = indent.get_indent(lnum)
			end
			return out
		end, lines, lnums)
	end

	t.it("accumulates depth when opening a line inside nested blocks", function()
		t.eq({ 6 }, indents({ "local t = {", "  a = {", "    b = {", "", "    },", "  },", "}" }, { 4 }))
	end)

	t.it("dedents a closing character to match the opener", function()
		t.eq({ 0 }, indents({ "function greet()", "  print('hi')", "" }, { 3 }))
	end)

	t.it("indents a blank line inside an if-block", function()
		t.eq({ 2 }, indents({ "if true then", "", "end" }, { 2 }))
	end)

	t.it("indents a blank line after a comment, still inside the body", function()
		t.eq({ 2 }, indents({ "function f()", "  -- a comment", "", "end" }, { 3 }))
	end)

	t.it("reindenting an already correct buffer is a no-op", function()
		t.eq(
			{ 0, 2, 4, 2, 2, 0 },
			indents({
				"local function outer()",
				"  local function inner()",
				"    return 1",
				"  end",
				"  return inner()",
				"end",
			}, { 1, 2, 3, 4, 5, 6 })
		)
	end)
end)
