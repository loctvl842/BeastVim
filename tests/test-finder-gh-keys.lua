-- =========================================================================
-- Test: finder keys on GitHub rows (and unchanged behavior on file rows)
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 3 step 3: Enter opens the
-- URL, <C-y> copies it, message rows ignore both, <C-s>/<C-v> keep the picker
-- open for rows without a file but still open files for file rows.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-keys.lua
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
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

_G.Util = require("beast.util")
_G.View = require("beast.libs.view")
_G.Theme = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#222222"
			end,
		})
	end,
}
local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end
package.loaded["beast"] = { apply_highlights = function() end }
package.loaded["beast.libs.finder.source.live_grep.engine.index"] = { setup = function() end }

local action = require("beast.libs.finder.action")
local finder = require("beast.libs.finder")

local opened_urls = {}
local orig_open = vim.ui.open
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.open = function(url)
	opened_urls[#opened_urls + 1] = url
	return {}, nil
end

local split_calls = {}
local orig_split, orig_vsplit = action.open_split, action.open_vsplit
action.open_split = function(_, item)
	split_calls[#split_calls + 1] = "split:" .. item.file
end
action.open_vsplit = function(_, item)
	split_calls[#split_calls + 1] = "vsplit:" .. item.file
end

-- The row the next search returns; the test swaps it between cases.
local row
package.loaded["beast.libs.finder.source.fake_keys"] = {
	live = true,
	async = true,
	initial_query = "q",
	run_when_empty = true,
	debounce_ms = 10,
	get = function(_, cb)
		cb(row)
		cb(nil)
	end,
	cancel = function() end,
}

local function settle(ms)
	vim.wait(ms or 150, function()
		return false
	end, 10)
end

local function prompt_buf()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "prompt" then
			return buf
		end
	end
end

--- Open the picker on a single `item`, press `lhs` in the prompt, return whether it is still open.
local function press(item, lhs)
	row = item
	finder.close()
	finder.open("fake_keys")
	settle()
	local buf = prompt_buf()
	local map = vim.fn.maparg(lhs, "i", false, true)
	assert_test("prompt maps " .. lhs, map and map.callback ~= nil)
	vim.api.nvim_buf_call(buf, function()
		map.callback()
	end)
	settle()
	return prompt_buf() ~= nil
end

local pr = { idx = 1, score = 1, text = "#1 t", url = "https://github.com/o/n/pull/1" }
local msg = { idx = 1, score = 1, text = "No results for this search", message = true }
local file = { idx = 1, score = 1, text = "a.lua", file = "/tmp/a.lua" }

io.write("\n--- Enter ---\n")
assert_eq("Enter on a message row keeps the picker open", press(msg, "<CR>"), true)
assert_eq("and opens nothing", #opened_urls, 0)
assert_eq("Enter on a url row closes the picker", press(pr, "<CR>"), false)
assert_eq("and opens the url in the browser", opened_urls[1], pr.url)

io.write("\n--- Ctrl-y ---\n")
vim.fn.setreg("+", "untouched")
assert_eq("Ctrl-y keeps the picker open", press(pr, "<C-y>"), true)
assert_eq("and copies the url", vim.fn.getreg("+"), pr.url)
assert_test("and confirms with a toast", toasts[#toasts] == "Copied: " .. pr.url, vim.inspect(toasts))
vim.fn.setreg("+", "untouched")
press(msg, "<C-y>")
assert_eq("Ctrl-y on a message row copies nothing", vim.fn.getreg("+"), "untouched")

io.write("\n--- splits ---\n")
assert_eq("Ctrl-s on a url row keeps the picker open", press(pr, "<C-s>"), true)
assert_eq("Ctrl-v on a url row keeps the picker open", press(pr, "<C-v>"), true)
assert_eq("and splits nothing", #split_calls, 0)
assert_eq("Ctrl-s on a file row closes the picker", press(file, "<C-s>"), false)
assert_eq("and splits the file", split_calls[1], "split:/tmp/a.lua")
assert_eq("Ctrl-v on a file row closes the picker", press(file, "<C-v>"), false)
assert_eq("and vsplits the file", split_calls[2], "vsplit:/tmp/a.lua")

finder.close()
vim.ui.open = orig_open
action.open_split, action.open_vsplit = orig_split, orig_vsplit

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
