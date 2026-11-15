-- =========================================================================
-- Test: finder opens a live source with a pre-filled prompt
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 2: `initial_query`
-- fills the prompt (cursor at its end) and is searched once on open, typing
-- afterwards searches again, `title`/`debounce_ms` override the defaults, and
-- `check` can veto opening.
--
-- Run as: nvim --clean --headless -l tests/test-finder-input-initial.lua
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

-- Globals normally installed by beast.setup()
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

-- finder.setup() would load highlights and spawn the bigram index watcher: neither is under test.
package.loaded["beast"] = { apply_highlights = function() end }
package.loaded["beast.libs.finder.source.live_grep.engine.index"] = { setup = function() end }

local config = require("beast.libs.finder.config")
local finder = require("beast.libs.finder")
local input = require("beast.libs.finder.ui.input")

local searches = {} ---@type string[]
local check_ok = true
local checks = 0

package.loaded["beast.libs.finder.source.fake_live"] = {
	live = true,
	async = true,
	initial_query = "is:fake ",
	run_when_empty = true,
	retain_results = true,
	debounce_ms = 20,
	title = function()
		return "Fake - o/n"
	end,
	check = function()
		checks = checks + 1
		return check_ok
	end,
	get = function(filter, cb)
		searches[#searches + 1] = filter.pattern
		cb({ idx = 1, score = 1, text = "item for " .. filter.pattern })
		cb(nil)
	end,
	cancel = function() end,
}

local function find_input_win()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "prompt" then
			return win
		end
	end
end

local function settle(ms)
	vim.wait(ms or 150, function()
		return false
	end, 10)
end

io.write("\n--- opening with a source that has an initial query ---\n")
finder.open("fake_live")
settle(300)
local win = find_input_win()
assert_test("prompt window exists", win ~= nil)
local buf = vim.api.nvim_win_get_buf(win)
local view = {
	buf = buf,
	win = win,
	is_valid = function()
		return true
	end,
}
assert_eq("prompt holds the initial query", input.get_text(view), "is:fake ")
assert_eq("check ran once", checks, 1)
assert_eq("searched exactly once on open", #searches, 1)
assert_eq("searched with the initial query", searches[1], "is:fake ")

local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
local col = vim.api.nvim_win_get_cursor(win)[2]
-- `startinsert!` appends: the cursor sits just past the last character.
assert_eq("cursor is at the end of the prefilled text", col, #line)

local title = vim.api.nvim_win_get_config(win).title
local title_text = type(title) == "table" and title[1] and title[1][1] or title
assert_test("title comes from the source", tostring(title_text):find("Fake - o/n", 1, true) ~= nil, vim.inspect(title))

io.write("\n--- an echoed change event for the unchanged initial text does not search again ---\n")
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
settle(150)
assert_eq("still one search", #searches, 1)

io.write("\n--- typing afterwards searches again ---\n")
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { config.prompt_prefix .. "is:fake hub" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
settle(200)
assert_eq("second search ran", #searches, 2)
assert_eq("second search uses the typed text", searches[2], "is:fake hub")

io.write("\n--- retyping the initial text searches again ---\n")
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { config.prompt_prefix .. "is:fake " })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
settle(200)
assert_eq("third search ran for the original text", #searches, 3)

io.write("\n--- check can veto opening ---\n")
finder.close()
settle(50)
check_ok = false
local before = #searches
finder.open("fake_live")
settle(150)
assert_eq("check ran again", checks, 2)
assert_eq("no prompt window when check fails", find_input_win(), nil)
assert_eq("no search when check fails", #searches, before)

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
