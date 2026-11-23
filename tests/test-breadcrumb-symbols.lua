-- =========================================================================
-- Test: Breadcrumb symbol trail (render + truncation, LSP lookup, treesitter)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-breadcrumb-symbols.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Util = {
	root = function()
		return "/proj"
	end,
}

local passed = 0
local failed = 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n         expected: " .. vim.inspect(expected) .. "\n         got:      " .. vim.inspect(got) .. "\n")
	end
end

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. (msg and ("\n         " .. msg) or "") .. "\n")
	end
end

---Statusline format string -> visible text.
local function plain(fmt)
	return (fmt:gsub("%%#%w+#", ""):gsub("%%%*", ""))
end

-- =========================================================================
-- Render: parity without symbols, then trail + truncation
-- =========================================================================

io.write("filepath.render\n")
local filepath = require("beast.libs.breadcrumb.filepath")
local buf = vim.api.nvim_create_buf(false, false)
local BUFNAME = "/proj/lua/beast/libs/breadcrumb/init.lua"
local SEP = "  "

local function render(width, symbols, modified)
	vim.bo[buf].modified = modified or false
	return filepath.render({ bufnr = buf, bufname = BUFNAME, width = width }, SEP, "+", symbols)
end

-- Output captured from the implementation before symbols existed
local parity = {
	{
		modified = false,
		width = 80,
		expected = "%#BeastBcDir#lua%*%#BeastBcSep#  %*%#BeastBcDir#beast%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*",
	},
	{
		modified = false,
		width = 30,
		expected = "%#BeastBcSep#…%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*",
	},
	{ modified = false, width = 20, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*" },
	{
		modified = true,
		width = 80,
		expected = "%#BeastBcDir#lua%*%#BeastBcSep#  %*%#BeastBcDir#beast%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*",
	},
	{ modified = true, width = 24, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*" },
	{ modified = true, width = 12, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*" },
}
for _, c in ipairs(parity) do
	assert_eq(
		("no symbols, width %d, modified=%s matches old output"):format(c.width, tostring(c.modified)),
		render(c.width, nil, c.modified),
		c.expected
	)
end

local chain = {
	{ name = "M", kind = "Module" },
	{ name = "setup", kind = "Function" },
	{ name = "ensure_autocmds", kind = "Function" },
}
local icon_fn = vim.trim(require("beast.icon").kinds.Function)

local full = plain(render(200, chain))
assert_test("wide: path, file and every symbol in order", full:find("breadcrumb  init.lua  .-M  .-setup  .-ensure_autocmds") ~= nil, full)
assert_test("symbol segment carries the kind icon", full:find(icon_fn .. " setup", 1, true) ~= nil, full)
assert_test("symbol uses its family highlight", render(200, chain):find("%#BeastBcSymCallable#" .. icon_fn, 1, true) ~= nil)

assert_test(
	"empty-name symbols are skipped",
	plain(render(200, { { name = "", kind = "Function" }, { name = "x", kind = "Function" } })):find("init.lua  .- x$") ~= nil
)

assert_test("modified marker is last, after the final symbol", plain(render(200, chain, true)):sub(-1) == "+", plain(render(200, chain, true)))
assert_test("clean buffer has no marker", plain(render(200, chain, false)):find("+", 1, true) == nil)

-- Directories go first: tail (file + all symbols) still fits
local tail_only = plain(render(200, chain)):gsub("^.-init.lua", "init.lua")
local w_dirs_drop = 1 + vim.fn.strdisplaywidth(tail_only) + 3
local dirs_dropped = plain(render(w_dirs_drop, chain))
assert_test(
	"narrow: dirs collapse first, symbols stay whole",
	dirs_dropped:find("…", 1, true) == 1 and dirs_dropped:find("setup", 1, true) ~= nil and dirs_dropped:find("ensure_autocmds", 1, true) ~= nil,
	dirs_dropped
)
assert_test("narrow: outer dir is gone", dirs_dropped:find("breadcrumb", 1, true) == nil, dirs_dropped)

-- Narrower still: outer symbols collapse, file + innermost stay
local narrow = plain(render(36, chain))
assert_test("narrower: file kept", narrow:find("init.lua", 1, true) ~= nil, narrow)
assert_test("narrower: innermost symbol kept", narrow:find("ensure_autocmds", 1, true) ~= nil, narrow)
assert_test(
	"narrower: outer symbols collapsed to ellipsis",
	narrow:find("setup", 1, true) == nil and narrow:find("init.lua  …", 1, true) ~= nil,
	narrow
)

local narrow_mod = plain(render(36, chain, true))
assert_test("narrower: marker still last", narrow_mod:sub(-1) == "+" and narrow_mod:find("ensure_autocmds", 1, true) ~= nil, narrow_mod)

local single = plain(render(10, { { name = "only_symbol", kind = "Function" } }))
assert_test("single symbol never dropped", single:find("only_symbol", 1, true) ~= nil, single)

-- =========================================================================
-- LSP source: normalization, lookup, refresh ordering
-- =========================================================================

io.write("\nsymbols.lsp\n")
local lsp = require("beast.libs.breadcrumb.symbols.lsp")

local function rng(sr, sc, er, ec)
	return { start = { line = sr, character = sc }, ["end"] = { line = er, character = ec } }
end

-- class Server (0-9) { method start (1-4) { inner (2-3) } ; method stop (6-8) }
local doc_symbols = {
	{
		name = "Server",
		kind = 5,
		range = rng(0, 0, 9, 3),
		selectionRange = rng(0, 6, 0, 12),
		children = {
			{ name = "stop", kind = 6, range = rng(6, 2, 8, 5), selectionRange = rng(6, 2, 6, 6) },
			{
				name = "start",
				kind = 6,
				range = rng(1, 2, 4, 5),
				selectionRange = rng(1, 2, 1, 7),
				children = { { name = "inner", kind = 12, range = rng(2, 4, 3, 7), selectionRange = rng(2, 4, 2, 9) } },
			},
		},
	},
}

local function names(chain)
	return table.concat(
		vim.tbl_map(function(n)
			return n.name
		end, chain),
		">"
	)
end

local tree = lsp.normalize(doc_symbols)
assert_eq("kind number maps to Icon.kinds key", tree[1].kind, "Class")
assert_eq("siblings are sorted by start", tree[1].children[1].name, "start")
assert_eq("nested cursor gives the full chain", names(lsp.find(tree, 2, 5)), "Server>start>inner")
assert_eq("cursor in method body, outside inner", names(lsp.find(tree, 1, 3)), "Server>start")
assert_eq("cursor on a header line counts as inside", names(lsp.find(tree, 6, 2)), "Server>stop")
assert_eq("cursor between siblings stays in the parent", names(lsp.find(tree, 5, 0)), "Server")
assert_eq("cursor after the end of a symbol is outside", names(lsp.find(tree, 9, 3)), "")
assert_eq("cursor before a symbol on its first line is outside", names(lsp.find(tree, 2, 3)), "Server>start")
assert_eq("empty tree gives an empty chain", names(lsp.find({}, 0, 0)), "")

-- Flat SymbolInformation: hierarchy rebuilt from ranges, input order irrelevant
local flat = lsp.normalize({
	{ name = "inner", kind = 12, location = { uri = "file:///x", range = rng(2, 4, 3, 7) } },
	{ name = "start", kind = 6, location = { uri = "file:///x", range = rng(1, 2, 4, 5) } },
	{ name = "Server", kind = 5, location = { uri = "file:///x", range = rng(0, 0, 9, 3) } },
	{ name = "later", kind = 12, location = { uri = "file:///x", range = rng(11, 0, 12, 3) } },
})
assert_eq("flat form: nested by range containment", names(lsp.find(flat, 2, 5)), "Server>start>inner")
assert_eq("flat form: second root", names(lsp.find(flat, 11, 1)), "later")

-- refresh(): stub the client lookup and the request so replies can be ordered by hand
local lbuf = vim.api.nvim_create_buf(false, false)
vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, { "class Server {", "  start() {", "    inner", "  }", "}" })
local pending = {}
local orig_get_clients, orig_request_all = vim.lsp.get_clients, vim.lsp.buf_request_all
local orig_get_client_by_id = vim.lsp.get_client_by_id
vim.lsp.get_clients = function()
	return { { id = 1 } }
end
vim.lsp.get_client_by_id = function()
	return { offset_encoding = "utf-16" }
end
vim.lsp.buf_request_all = function(_, _, _, cb)
	pending[#pending + 1] = cb
end

local changed = 0
lsp.on_change = function()
	changed = changed + 1
end

local function reply(i, res)
	pending[i](res)
end
local function ok(result)
	return { [1] = { result = result } }
end
local function trail_names(row, col)
	local tr = lsp.trail(lbuf, row, col)
	return tr and names(tr) or "nil"
end

assert_eq("no reply yet: source has nothing", trail_names(2, 4), "nil")
lsp.refresh(lbuf)
lsp.refresh(lbuf)
reply(2, ok(doc_symbols))
assert_eq("newest reply applied", trail_names(2, 5), "Server>start>inner")
reply(1, ok({ { name = "Stale", kind = 12, range = rng(0, 0, 9, 0), selectionRange = rng(0, 0, 0, 1) } }))
assert_eq("older reply arriving late is ignored", trail_names(2, 5), "Server>start>inner")
assert_eq("on_change ran once per applied reply", changed, 1)

lsp.refresh(lbuf)
reply(3, { [1] = { err = { code = -32801 } } })
assert_eq("errored reply keeps the previous tree", trail_names(2, 5), "Server>start>inner")

lsp.refresh(lbuf)
reply(4, ok({}))
assert_eq("successful empty reply clears (file has no symbols)", trail_names(2, 5), "nil")

lsp.refresh(lbuf)
reply(5, ok(doc_symbols))
assert_eq("tree comes back after a later reply", trail_names(2, 5), "Server>start>inner")

-- Multibyte: UTF-16 server columns vs byte cursor columns
vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, { "é = function() return 1 end" })
lsp.refresh(lbuf)
reply(6, ok({ { name = "f", kind = 12, range = rng(0, 4, 0, 27), selectionRange = rng(0, 4, 0, 5) } }))
-- "é" is 2 bytes but 1 UTF-16 unit: byte col 5 is UTF-16 col 4 (start of `function`)
assert_eq("byte column converted to server encoding (inside)", trail_names(0, 5), "f")
assert_eq("byte column converted to server encoding (before)", trail_names(0, 3), "")

lsp.clear(lbuf)
assert_eq("clear forgets the buffer", trail_names(0, 5), "nil")

vim.lsp.get_clients, vim.lsp.buf_request_all, vim.lsp.get_client_by_id = orig_get_clients, orig_request_all, orig_get_client_by_id
lsp.on_change = nil

-- =========================================================================
-- Treesitter fallback and source selection
-- =========================================================================

io.write("\nsymbols.treesitter\n")
-- Parsers installed by the real config live outside --clean's runtimepath
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/../BeastVim/site")
local ts = require("beast.libs.breadcrumb.symbols.treesitter")
vim.treesitter.language.register("tsx", "typescriptreact") -- the real config does this in its treesitter lib

---@param ft string
---@param lines string[]
local function scratch(ft, lines)
	local b = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
	vim.bo[b].filetype = ft
	return b
end

local function ts_names(b, row, col)
	local tr = ts.trail(b, row, col)
	return tr and names(tr) or "nil"
end

---@param ft string
---@param lines string[]
---@param cases { [1]: integer, [2]: integer, [3]: string }[]  row, col, expected chain
local function ts_cases(ft, lines, cases)
	local lang = vim.treesitter.language.get_lang(ft)
	local loaded = lang and select(2, pcall(vim.treesitter.language.add, lang))
	if not loaded then
		io.write(("  SKIP: %s (no parser installed)\n"):format(ft))
		return
	end
	local b = scratch(ft, lines)
	for _, c in ipairs(cases) do
		assert_eq(("%s: (%d,%d)"):format(ft, c[1], c[2]), ts_names(b, c[1], c[2]), c[3])
	end
end

ts_cases("lua", {
	"local M = {}",
	"function M.setup(opts)",
	"  local f = function()",
	"    return 1",
	"  end",
	'  vim.api.nvim_create_autocmd("X", { callback = function()',
	"    print(1)",
	"  end })",
	"end",
	"function M:method() end",
}, { { 0, 0, "" }, { 3, 6, "M.setup>f" }, { 6, 6, "M.setup>callback" }, { 9, 21, "M:method" } })

ts_cases("python", {
	"class Server:",
	"    def start(self):",
	"        def inner():",
	"            pass",
	"async def run():",
	"    pass",
}, { { 0, 0, "Server" }, { 3, 12, "Server>start>inner" }, { 5, 4, "run" } })

local js = {
	"class Server {",
	"  start() {",
	"    const f = () => 1;",
	"  }",
	"}",
	"function run() {}",
	"const arrow = () => {};",
}
ts_cases("javascript", js, { { 2, 20, "Server>start>f" }, { 5, 16, "run" }, { 6, 21, "arrow" } })
ts_cases("typescript", {
	"interface Cfg { a: number }",
	"enum Color { Red }",
	"const o = { key: function() { return 1 } }",
}, { { 0, 20, "Cfg" }, { 1, 14, "Color" }, { 2, 35, "key" } })
ts_cases("typescriptreact", { "const C = () => <div/>;" }, { { 0, 20, "C" } })

ts_cases("c", {
	"struct S { int a; };",
	"int main(void) {",
	"  return 0;",
	"}",
}, { { 0, 13, "S" }, { 2, 4, "main" } })

ts_cases("cpp", {
	"namespace N {",
	"class C { void m() { int x; } };",
	"void C::f() { int y; }",
	"}",
}, { { 1, 22, "N>C>m" }, { 2, 15, "N>C::f" } })

ts_cases("markdown", {
	"# Install",
	"text",
	"## Linux",
	"more",
	"",
	"```lua",
	"local x = 1",
	"```",
	"# Other",
}, { { 1, 0, "Install" }, { 3, 1, "Install>Linux" }, { 6, 2, "Install>Linux" }, { 8, 2, "Other" } })

assert_eq("unknown language: source has nothing", ts_names(scratch("text", { "plain" }), 0, 0), "nil")

-- Source selection: the server wins; the trail is never a mix of both sources
local sym = require("beast.libs.breadcrumb.symbols")
if select(2, pcall(vim.treesitter.language.add, "lua")) then
	local sb = scratch("lua", { "local M = {}", "function M.setup()", "  return 1", "end" })
	vim.api.nvim_win_set_buf(0, sb)
	vim.api.nvim_win_set_cursor(0, { 3, 4 })
	assert_eq("no server: trail comes from the syntax tree", names(sym.trail(sb, 0)), "M.setup")

	vim.lsp.get_clients = function()
		return { { id = 1 } }
	end
	vim.lsp.get_client_by_id = function()
		return { offset_encoding = "utf-16" }
	end
	local replies = {}
	vim.lsp.buf_request_all = function(_, _, _, cb)
		replies[#replies + 1] = cb
	end
	sym.refresh(sb)
	replies[1]({ [1] = { result = { { name = "ServerSaysSetup", kind = 12, range = rng(1, 0, 3, 3), selectionRange = rng(1, 9, 1, 14) } } } })
	assert_eq("server answered: its symbols are used, not the syntax tree's", names(sym.trail(sb, 0)), "ServerSaysSetup")
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	assert_eq("server answered, cursor outside every symbol: stays empty", names(sym.trail(sb, 0)), "")

	sym.clear(sb)
	assert_eq("server gone: syntax tree again", names(sym.trail(sb, 0)), "")
	vim.lsp.get_clients, vim.lsp.buf_request_all, vim.lsp.get_client_by_id = orig_get_clients, orig_request_all, orig_get_client_by_id
else
	io.write("  SKIP: source selection (lua parser unavailable)\n")
end

-- =========================================================================

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
