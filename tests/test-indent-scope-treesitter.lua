-- =========================================================================
-- Test: Indent scope detection - treesitter strategy
-- =========================================================================
-- Run as: NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-indent-scope-treesitter.lua
-- Exit code: 0 = PASS, 1 = FAIL
--
-- Covers where the scope body starts/ends for languages with and without a
-- closing delimiter, wrapped (multi-line) headers, and comments directly under
-- the header. Cases whose parser is not installed are skipped.
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
-- Installed parsers live under stdpath("data")/site (not on rtp with --clean)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ts = require("beast.libs.indent.scope.treesitter")

local passed = 0
local failed = 0
local skipped = 0

---@param name string
---@param got table?
---@param expected table?
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

---Run `find` at (line, col) of a scratch buffer and return {from,to,indent}[]
---without the buf field. Returns false when the parser is unavailable.
---@param lang string
---@param lines string[]
---@param sw integer
---@param pos {[1]: integer, [2]: integer}
---@return table[]|nil|false
local function scope_at(lang, lines, sw, pos)
	if not pcall(vim.treesitter.get_string_parser, "", lang) then
		return false
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].shiftwidth = sw
	vim.bo[buf].tabstop = sw
	vim.bo[buf].expandtab = true
	vim.api.nvim_set_current_buf(buf)
	vim.treesitter.start(buf, lang)

	local scopes = vim.api.nvim_buf_call(buf, function()
		return ts.find(buf, pos)
	end)
	vim.api.nvim_buf_delete(buf, { force = true })

	if not scopes then
		return nil
	end
	local result = {}
	for _, s in ipairs(scopes) do
		result[#result + 1] = { from = s.from, to = s.to, indent = s.indent }
	end
	return result
end

---@param name string
---@param lang string
---@param lines string[]
---@param sw integer
---@param pos {[1]: integer, [2]: integer}
---@param expected table[]|nil
local function check(name, lang, lines, sw, pos, expected)
	local got = scope_at(lang, lines, sw, pos)
	if got == false then
		skipped = skipped + 1
		io.write("  SKIP: " .. name .. " (no " .. lang .. " parser)\n")
		return
	end
	assert_eq(name, got, expected)
end

-- =========================================================================
-- Lua: closing `end`
-- =========================================================================
io.write("\n== Lua: closing end excluded ==\n")
check("function body stops before `end`", "lua", {
	"local function f()",
	"  local x = 1",
	"  return x",
	"end",
}, 2, { 1, 0 }, { { from = 2, to = 3, indent = 2 } })

-- =========================================================================
-- Lua: comment directly under the header belongs to the body
-- =========================================================================
io.write("\n== Lua: comment before first statement ==\n")
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

-- =========================================================================
-- Python: no closing delimiter, last body line is kept
-- =========================================================================
io.write("\n== Python: last body line kept ==\n")
check("function scope includes the last line", "python", {
	"class A:",
	"    def add(self, item):",
	"        if item not in self:",
	"            super().add(item)",
	"            _invalidate()",
}, 4, { 2, 4 }, { { from = 3, to = 5, indent = 8 } })

check("nested if scope includes the last line", "python", {
	"class A:",
	"    def add(self, item):",
	"        if item not in self:",
	"            super().add(item)",
	"            _invalidate()",
}, 4, { 3, 8 }, { { from = 4, to = 5, indent = 12 } })

-- =========================================================================
-- Python: wrapped (multi-line) headers
-- =========================================================================
io.write("\n== Python: wrapped header ==\n")
check("continuation line is not part of the body (cursor on def)", "python", {
	"class A:",
	"    def add(",
	"            self, item: Any) -> None:",
	"        if item not in self:",
	"            super().add(item)",
	"            _invalidate()",
}, 4, { 2, 4 }, { { from = 4, to = 6, indent = 8 } })

check("continuation line is not part of the body (cursor on continuation)", "python", {
	"class A:",
	"    def add(",
	"            self, item: Any) -> None:",
	"        if item not in self:",
	"            super().add(item)",
	"            _invalidate()",
}, 4, { 3, 12 }, { { from = 4, to = 6, indent = 8 } })

check("continuation line with no indentation", "python", {
	"class A:",
	"    def add(",
	"            self",
	", item: Any) -> None:",
	"        if item not in self:",
	"            super().add(item)",
	"            _invalidate()",
}, 4, { 2, 4 }, { { from = 5, to = 7, indent = 8 } })

-- =========================================================================
-- JavaScript: brace on the header line, closing `}` excluded
-- =========================================================================
io.write("\n== JavaScript: wrapped header ==\n")
check("body starts after the line holding `{`", "javascript", {
	"function f(a,",
	"           b) {",
	"  if (a) {",
	"    g();",
	"  }",
	"  h();",
	"}",
}, 2, { 1, 0 }, { { from = 3, to = 6, indent = 2 } })

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n%d passed, %d failed, %d skipped\n", passed, failed, skipped))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
