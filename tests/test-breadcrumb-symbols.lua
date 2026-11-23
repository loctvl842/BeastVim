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

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
