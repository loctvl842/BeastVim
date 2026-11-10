-- ==============================================================================
-- Test: Indent scope draw column
-- ==============================================================================
-- Run as: NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-indent-scope-draw.lua
-- Exit code: 0 = PASS, 1 = FAIL
--
-- The scope line must sit at the indent of the opener line, even when the
-- body's first line is off grid (15 or 17 columns with shiftwidth 4, for
-- example) or the header is wrapped. Captures the column passed to
-- nvim_buf_set_extmark instead of reading the screen.
-- ==============================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
-- Installed parsers live under stdpath("data")/site (not on rtp with --clean)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Util = require("beast.util")
local config = require("beast.libs.indent.config")
local scope = require("beast.libs.indent.scope")

local passed = 0
local failed = 0
local skipped = 0

---@param name string
---@param got any
---@param expected any
local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write(" PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write(" FAIL: " .. name .. "\n")
		io.write("   expected: " .. vim.inspect(expected) .. "\n")
		io.write("   got:      " .. vim.inspect(got) .. "\n")
	end
end

---Render the scope for a scratch buffer and return the buffer columns the
---vertical line is drawn at. Returns false when the parser is unavailable.
---@param lines string[]
---@param sw integer
---@param pos {[1]: integer, [2]: integer}
---@param opts? { treesitter?: boolean }
---@return integer[]|false
local function draw_cols(lines, sw, pos, opts)
	opts = opts or {}
	local use_ts = opts.treesitter ~= false
	if use_ts and not pcall(vim.treesitter.get_string_parser, "", "python") then
		return false
	end
	config.setup({ scope = { treesitter = { enabled = use_ts } } })
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].shiftwidth = sw
	vim.bo[buf].tabstop = sw
	vim.bo[buf].expandtab = true
	vim.api.nvim_set_current_buf(buf)
	if use_ts then
		vim.treesitter.start(buf, "python")
	end
	vim.api.nvim_win_set_cursor(0, pos)
	scope.update(function()
		return false
	end)
	vim.wait(200)

	local win = vim.api.nvim_get_current_win()
	local cols = {}
	local real = vim.api.nvim_buf_set_extmark
	vim.api.nvim_buf_set_extmark = function(_, _, _, _, extmark_opts)
		if extmark_opts and extmark_opts.virt_text_win_col then
			cols[extmark_opts.virt_text_win_col] = true
		end
		return 0
	end
	-- draw runs inside nvim_buf_call in the decoration provider
	vim.api.nvim_buf_call(buf, function()
		scope.draw(buf, 1, win, 1, #lines, 0, sw)
	end)
	vim.api.nvim_buf_set_extmark = real
	vim.api.nvim_buf_delete(buf, { force = true })

	local result = vim.tbl_keys(cols)
	table.sort(result)
	return result
end

---@param name string
---@param lines string[]
---@param sw integer
---@param pos {[1]: integer, [2]: integer}
---@param expected integer[]
---@param opts? { treesitter?: boolean }
local function check(name, lines, sw, pos, expected, opts)
	local got = draw_cols(lines, sw, pos, opts)
	if got == false then
		skipped = skipped + 1
		io.write(" SKIP: " .. name .. " (no python parser)\n")
		return
	end
	assert_eq(name, got, expected)
end

io.write("\n= Scope line anchored to the opener =\n")

-- Body first line at 7 with shiftwidth 4: line belongs at the opener indent 4,
-- not 3 (indent - shiftwidth).
check("under-indented body keeps the opener column", {
	"def f():",
	"    if a:",
	"       pass",
}, 4, { 2, 4 }, { 4 })

-- Body first line at 17 (one past the aligned 16): still the opener indent 4,
-- not 13 (indent - shiftwidth) or 16 (a grid snap).
check("over-indented body keeps the opener column", {
	"def f():",
	"    if a:",
	"                 pass",
}, 4, { 2, 4 }, { 4 })

-- Aligned body: same result as before the change (indent 8 - shiftwidth 4 = 4).
check("aligned body keeps the opener column", {
	"def f():",
	"    if a:",
	"        pass",
}, 4, { 2, 4 }, { 4 })

-- Body indent below one shiftwidth: the opener is at column 0.
check("body shallower than shiftwidth draws at column 0", {
	"if a:",
	" pass",
}, 4, { 1, 0 }, { 0 })

-- Wrapped header: the line directly above the body is a continuation at 12,
-- so the anchor must be the node's first line (the `def` at 4), not from - 1.
check("wrapped header anchors to the first header line", {
	"class A:",
	"    def add(",
	"            self):",
	"        pass",
}, 4, { 2, 4 }, { 4 })

-- Same off-grid body through the indent fallback (no treesitter).
check("indent strategy anchors to the opener too", {
	"def f():",
	"    if a:",
	"          pass",
}, 4, { 2, 4 }, { 4 }, { treesitter = false })

io.write(string.format("\n%d passed, %d failed, %d skipped\n", passed, failed, skipped))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
