local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Installed parsers live under the real config's site dir (the harness redirects stdpath("data")).
local SITE = vim.env.HOME .. "/.local/share/BeastVim/site"

-- Covers where the scope body starts/ends for languages with and without a closing delimiter,
-- wrapped (multi-line) headers, and comments directly under the header.
-- Cases whose parser is not installed are reported as pending.

t.describe("indent scope detection (treesitter strategy)", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function(site)
			vim.opt.runtimepath:append(site)
		end, SITE)
	end)

	---Run `find` at `pos` of a scratch buffer.
	---@param lang string
	---@param lines string[]
	---@param sw integer
	---@param pos {[1]: integer, [2]: integer}
	---@return { missing: boolean?, found: boolean?, scopes: table[]? }
	local function scope_at(lang, lines, sw, pos)
		return n.exec_lua(function(lg, l, shiftwidth, p)
			if not pcall(vim.treesitter.get_string_parser, "", lg) then
				return { missing = true }
			end
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, l)
			vim.bo[buf].shiftwidth = shiftwidth
			vim.bo[buf].tabstop = shiftwidth
			vim.bo[buf].expandtab = true
			vim.api.nvim_set_current_buf(buf)
			vim.treesitter.start(buf, lg)
			local scopes = vim.api.nvim_buf_call(buf, function()
				return require("beast.libs.indent.scope.treesitter").find(buf, p)
			end)
			if not scopes then
				return { found = false }
			end
			local result = {}
			for _, s in ipairs(scopes) do
				result[#result + 1] = { from = s.from, to = s.to, indent = s.indent }
			end
			return { found = true, scopes = result }
		end, lang, lines, sw, pos)
	end

	---@param name string
	---@param lang string
	---@param lines string[]
	---@param sw integer
	---@param pos {[1]: integer, [2]: integer}
	---@param expected table[]|nil
	local function check(name, lang, lines, sw, pos, expected)
		t.it(name, function()
			local r = scope_at(lang, lines, sw, pos)
			if r.missing then
				t.pending("no " .. lang .. " parser")
			end
			t.eq(expected, r.scopes)
		end)
	end

	t.describe("Lua: closing end excluded", function()
		check("function body stops before `end`", "lua", {
			"local function f()",
			"  local x = 1",
			"  return x",
			"end",
		}, 2, { 1, 0 }, { { from = 2, to = 3, indent = 2 } })
	end)

	t.describe("Lua: comment before first statement", function()
		check("comment under header starts the body", "lua", {
			"local function install_require_hook()",
			"  -- fooo",
			"    if state.rawrequire then",
			"        return",
			"    end",
			"    state.rawrequire = require",
			"    _G.require = hooked_require",
			"end",
		}, 4, { 1, 0 }, { { from = 2, to = 7, indent = 2 } })
	end)

	t.describe("Python: last body line kept", function()
		local py = {
			"class A:",
			"    def add(self, item):",
			"        if item not in self:",
			"            super().add(item)",
			"            _invalidate()",
		}
		check("function scope includes the last line", "python", py, 4, { 2, 4 }, { { from = 3, to = 5, indent = 8 } })
		check("nested if scope includes the last line", "python", py, 4, { 3, 8 }, { { from = 4, to = 5, indent = 12 } })
	end)

	t.describe("Python: wrapped header", function()
		local wrapped = {
			"class A:",
			"    def add(",
			"            self, item: Any) -> None:",
			"        if item not in self:",
			"            super().add(item)",
			"            _invalidate()",
		}
		check("continuation line is not part of the body (cursor on def)", "python", wrapped, 4, { 2, 4 }, { { from = 4, to = 6, indent = 8 } })
		check("continuation line is not part of the body (cursor on continuation)", "python", wrapped, 4, { 3, 12 }, { { from = 4, to = 6, indent = 8 } })
		check("continuation line with no indentation", "python", {
			"class A:",
			"    def add(",
			"            self",
			", item: Any) -> None:",
			"        if item not in self:",
			"            super().add(item)",
			"            _invalidate()",
		}, 4, { 2, 4 }, { { from = 5, to = 7, indent = 8 } })
	end)

	t.describe("JavaScript: wrapped header", function()
		check("body starts after the line holding `{`", "javascript", {
			"function f(a,",
			"           b) {",
			"  if (a) {",
			"    g();",
			"  }",
			"  h();",
			"}",
		}, 2, { 1, 0 }, { { from = 3, to = 6, indent = 2 } })
	end)

	t.describe("XML: element scope", function()
		-- uneven indentation splits the body into two stretches
		local xml_uneven = {
			"<app:metadata>",
			"  <app:annotations>",
			'    <app:annotation key="multiline">',
			"      First line",
			"  <app:code>literal</app:code>",
			"      Final line",
			"    </app:annotation>",
			"  </app:annotations>",
			"</app:metadata>",
		}
		local annotation_stretches = { { from = 4, to = 4, indent = 6 }, { from = 6, to = 6, indent = 6 } }
		check("cursor in the body marks both stretches", "xml", xml_uneven, 2, { 4, 6 }, annotation_stretches)
		check("cursor on a single-line element marks the enclosing element", "xml", xml_uneven, 2, { 5, 2 }, annotation_stretches)
		check("cursor on the opening tag marks the same element", "xml", xml_uneven, 2, { 3, 4 }, annotation_stretches)
		check("cursor on the closing tag marks the same element", "xml", xml_uneven, 2, { 7, 4 }, annotation_stretches)
		check(
			"outer element marks its own stretches",
			"xml",
			xml_uneven,
			2,
			{ 2, 2 },
			{ { from = 3, to = 4, indent = 4 }, { from = 6, to = 7, indent = 4 } }
		)

		check("wrapped start tag attributes are not body", "xml", {
			"<root>",
			"  <item",
			'      a="1"',
			'      b="2">',
			"    text",
			"  </item>",
			"</root>",
		}, 2, { 5, 4 }, { { from = 5, to = 5, indent = 4 } })

		-- Missing closing tag: tree-sitter error recovery must not make detection throw
		t.it("missing closing tag does not error", function()
			local ok, missing = n.exec_lua(function()
				if not pcall(vim.treesitter.get_string_parser, "", "xml") then
					return false, true
				end
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<a>", "  <b>", "    text", "</a>" })
				vim.bo[buf].shiftwidth = 2
				vim.bo[buf].tabstop = 2
				vim.bo[buf].expandtab = true
				vim.api.nvim_set_current_buf(buf)
				vim.treesitter.start(buf, "xml")
				local ok = pcall(vim.api.nvim_buf_call, buf, function()
					return require("beast.libs.indent.scope.treesitter").find(buf, { 3, 4 })
				end)
				return ok, false
			end)
			if missing then
				t.pending("no xml parser")
			end
			t.eq(true, ok)
		end)
	end)

	t.describe("HTML", function()
		-- Other grammars name their nodes `element` too: HTML must keep its behaviour
		check("html element is not a scope node", "html", {
			"<div>",
			"  <p>",
			"    text",
			"  </p>",
			"</div>",
		}, 2, { 3, 4 }, nil)
	end)
end)
