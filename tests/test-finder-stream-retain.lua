-- =========================================================================
-- Test: stream pipeline keeps the old list while a retain_results source searches
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 2: a source with
-- `retain_results` keeps its previous list on screen until the first new item
-- (or an empty finish) replaces it, `run_when_empty` searches an empty prompt,
-- `count` fills the prompt row only when a search finishes, and a plain live
-- source (live_grep-style) still clears the list at the start of every search.
--
-- Run as: nvim --clean --headless -l tests/test-finder-stream-retain.lua
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
package.loaded["beast"] = { apply_highlights = function() end }
package.loaded["beast.libs.finder.source.live_grep.engine.index"] = { setup = function() end }

local config = require("beast.libs.finder.config")
local finder = require("beast.libs.finder")
local ui = require("beast.libs.finder.ui")

-- Spy on list renders: what the list was last told to show.
local last_rendered = {} ---@type string[]
local render_count = 0
local orig_render = ui.list.render
---@diagnostic disable-next-line: duplicate-set-field
ui.list.render = function(view, items, ...)
	render_count = render_count + 1
	last_rendered = vim.tbl_map(function(it)
		return it.text
	end, items)
	return orig_render(view, items, ...)
end

-- Source whose callbacks the test drives by hand.
local pending ---@type fun(item: table?)?
local function make_source(extra)
	return vim.tbl_extend("force", {
		live = true,
		async = true,
		debounce_ms = 10,
		get = function(_, cb)
			pending = cb
		end,
		cancel = function() end,
	}, extra)
end

local function count_text(buf)
	local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
	for _, m in ipairs(marks) do
		local vt = m[4].virt_text
		if vt and m[4].virt_text_pos == "right_align" and vt[1][2] == "BeastFinderListDir" then
			return vt[1][1]
		end
	end
end

local function find_input()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "prompt" then
			return win, buf
		end
	end
end

local function settle(ms)
	vim.wait(ms or 120, function()
		return false
	end, 10)
end

local function type_text(buf, text)
	vim.api.nvim_buf_set_lines(buf, 0, 1, false, { config.prompt_prefix .. text })
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	settle(120)
end

local function item(text)
	return { idx = 1, score = 1, text = text }
end

-- ---------------------------------------------------------------------------
io.write("\n--- retain_results + run_when_empty + count ---\n")
package.loaded["beast.libs.finder.source.fake_retain"] = make_source({
	initial_query = "q0",
	retain_results = true,
	run_when_empty = true,
	count = function(items)
		return ("%d/%d"):format(#items, #items)
	end,
})
finder.open("fake_retain")
settle(150)
local _, buf = find_input()
assert_test("opening searched immediately", pending ~= nil)
assert_eq("count is empty while the first search runs", count_text(buf), nil)

pending(item("a"))
pending(item("b"))
pending(nil)
settle(150)
assert_eq("first results rendered", table.concat(last_rendered, ","), "a,b")
assert_eq("count shows once the search finished", count_text(buf), "2/2")

-- second search: the old list must stay until something new arrives
local first_run = pending
pending = nil
local renders_before = render_count
type_text(buf, "q1")
assert_test("second search started", pending ~= nil)
assert_eq("old list still on screen while searching", table.concat(last_rendered, ","), "a,b")
assert_eq("no render happened at search start", render_count, renders_before)
assert_eq("count is hidden while searching", count_text(buf), nil)

-- the cancelled first run finishing late must not disturb the second one
first_run(item("stale"))
first_run(nil)
settle(150)
assert_eq("a stale callback does not replace the retained list", table.concat(last_rendered, ","), "a,b")
assert_eq("a stale finish does not bring the count back", count_text(buf), nil)

pending(item("c"))
settle(150)
assert_eq("first new item replaces the old list", table.concat(last_rendered, ","), "c")
pending(nil)
settle(150)
assert_eq("count after the second search", count_text(buf), "1/1")

-- third search finds nothing: the retained list must be cleared at the end
pending = nil
type_text(buf, "q2")
assert_eq("still showing the previous results during the third search", table.concat(last_rendered, ","), "c")
pending(nil)
settle(150)
assert_eq("an empty finish clears the list", #last_rendered, 0)
assert_eq("count reads 0/0", count_text(buf), "0/0")

-- empty prompt still searches for run_when_empty
pending = nil
type_text(buf, "")
assert_test("empty prompt triggers a search", pending ~= nil)
finder.close()
settle(50)

-- ---------------------------------------------------------------------------
io.write("\n--- a plain live source is unchanged ---\n")
package.loaded["beast.libs.finder.source.fake_plain"] = make_source({})
pending = nil
finder.open("fake_plain")
settle(150)
assert_eq("no search on open without initial_query", pending, nil)
_, buf = find_input()

type_text(buf, "x")
assert_test("typing searches", pending ~= nil)
pending(item("a"))
pending(nil)
settle(150)
assert_eq("results rendered", table.concat(last_rendered, ","), "a")

pending = nil
renders_before = render_count
type_text(buf, "xy")
assert_test("new search cleared the list immediately", #last_rendered == 0, vim.inspect(last_rendered))
assert_test("and rendered the clear", render_count > renders_before)
assert_eq("no count label for sources without one", count_text(buf), nil)

pending = nil
type_text(buf, "")
assert_eq("empty prompt does not search", pending, nil)
assert_eq("empty prompt clears the list", #last_rendered, 0)
finder.close()

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
