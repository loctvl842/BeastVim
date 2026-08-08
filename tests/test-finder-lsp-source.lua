-- =========================================================================
-- Test: finder LSP source excludes the occurrence under the cursor
-- =========================================================================
-- Covers docs/dev-specs/finder-lsp-exclude-current-position.md: the shared
-- LSP source factory (source/lsp.lua) must not emit a result whose
-- file/line/column-range matches wherever the cursor was when the jump was
-- triggered.
--
-- Run as: nvim --clean --headless -l tests/test-finder-lsp-source.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local lsp_source = require("beast.libs.finder.source.lsp")

local CUR_FILE = "/scratch/target.lua"

-- Real scratch buffer/window so filter.cur_win, nvim_win_get_cursor, and
-- nvim_buf_get_name behave normally; only the vim.lsp.* entry points are
-- stubbed, so the fixture data is fully controlled.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, CUR_FILE)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"1",
	"2",
	"3",
	"4",
	'local profile = require("beast.profile")',
	"profile.start()",
	"profile.auto_dump_on_quit(out)",
})
vim.api.nvim_win_set_buf(0, buf)
local win = vim.api.nvim_get_current_win()

local orig_get_clients = vim.lsp.get_clients
local orig_get_client_by_id = vim.lsp.get_client_by_id
local orig_make_position_params = vim.lsp.util.make_position_params
local orig_locations_to_items = vim.lsp.util.locations_to_items
local orig_buf_request_all = vim.lsp.buf_request_all

local fake_client = { id = 1, offset_encoding = "utf-16" }

vim.lsp.get_clients = function()
	return { fake_client }
end
vim.lsp.get_client_by_id = function()
	return fake_client
end
vim.lsp.util.make_position_params = function()
	return {}
end
vim.lsp.buf_request_all = function(bufnr, method, params, handler)
	handler({ [1] = { err = nil, result = { "dummy" } } })
end

---@param qf_items table[]
---@param cursor {[1]: integer, [2]: integer}
---@return table[] items
local function run(qf_items, cursor)
	vim.lsp.util.locations_to_items = function()
		return qf_items
	end
	vim.api.nvim_win_set_cursor(win, cursor)

	local items = {}
	lsp_source.create("textDocument/references", "References").get({ cur_win = win, cwd = "/scratch" }, function(item)
		if item ~= nil then
			items[#items + 1] = item
		end
	end)
	return items
end

io.write("\n--- exact-column exclusion ---\n")
do
	-- "profile" spans byte columns 10..17 (0-indexed) on line 5.
	local qf_items = {
		{ filename = CUR_FILE, lnum = 5, col = 11, end_col = 18, text = 'local profile = require("beast.profile")' },
		{ filename = CUR_FILE, lnum = 6, col = 1, end_col = 8, text = "profile.start()" },
	}
	local items = run(qf_items, { 5, 10 })
	assert_eq("only the other occurrence is emitted", #items, 1)
	assert_eq("emitted item is line 6", items[1] and items[1].pos[1], 6)
end

io.write("\n--- mid-word exclusion ---\n")
do
	local qf_items = {
		{ filename = CUR_FILE, lnum = 5, col = 11, end_col = 18, text = 'local profile = require("beast.profile")' },
		{ filename = CUR_FILE, lnum = 6, col = 1, end_col = 8, text = "profile.start()" },
	}
	-- Cursor past the first character of "profile" (col 13 of 10..17), not on its start column.
	local items = run(qf_items, { 5, 13 })
	assert_eq("still only the other occurrence is emitted", #items, 1)
	assert_eq("emitted item is line 6", items[1] and items[1].pos[1], 6)
end

io.write("\n--- all results excluded ---\n")
do
	local qf_items = {
		{ filename = CUR_FILE, lnum = 5, col = 11, end_col = 18, text = 'local profile = require("beast.profile")' },
	}
	local completed = false
	vim.lsp.util.locations_to_items = function()
		return qf_items
	end
	vim.api.nvim_win_set_cursor(win, { 5, 10 })

	local items = {}
	lsp_source.create("textDocument/references", "References").get({ cur_win = win, cwd = "/scratch" }, function(item)
		if item == nil then
			completed = true
		else
			items[#items + 1] = item
		end
	end)
	assert_eq("no items emitted", #items, 0)
	assert_test("completion callback still fires", completed, "cb(nil) was never called")
end

io.write("\n--- unaffected case: no match for cursor position ---\n")
do
	local qf_items = {
		{ filename = CUR_FILE, lnum = 6, col = 1, end_col = 8, text = "profile.start()" },
		{ filename = CUR_FILE, lnum = 7, col = 1, end_col = 8, text = "profile.auto_dump_on_quit(out)" },
	}
	-- Cursor on line 1, nowhere near either result.
	local items = run(qf_items, { 1, 0 })
	assert_eq("both occurrences emitted", #items, 2)
	assert_eq("idx counts both", items[2] and items[2].idx, 2)
end

vim.lsp.get_clients = orig_get_clients
vim.lsp.get_client_by_id = orig_get_client_by_id
vim.lsp.util.make_position_params = orig_make_position_params
vim.lsp.util.locations_to_items = orig_locations_to_items
vim.lsp.buf_request_all = orig_buf_request_all

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
