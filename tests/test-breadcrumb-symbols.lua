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

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
