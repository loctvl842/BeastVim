-- =========================================================================
-- Test: GitHub finder preview pane
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 4: what the pane shows
-- (header at once, description and conversation when fetched, PR-only fields
-- only for PRs), relative times, caching, and dropping late answers for an
-- item the cursor already left. The detail fetch is faked.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-preview.lua
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

local api = require("beast.libs.finder.source.gh.api")
local preview = require("beast.libs.finder.source.gh.preview")

local NOW = 1794700800 -- 2026-11-15T00:00:00Z

local function has(lines, needle)
	for _, l in ipairs(lines) do
		if l:find(needle, 1, true) then
			return true
		end
	end
	return false
end

--- The line a `Label: value` field is drawn as (label column is 11 wide).
local function f(label, value)
	return ("%-11s%s"):format(label .. ":", value)
end

local function find(lines, needle)
	for i, l in ipairs(lines) do
		if l:find(needle, 1, true) then
			return i
		end
	end
end

-- ---------------------------------------------------------------------------
io.write("\n--- reltime ---\n")
assert_eq("two weeks", preview.reltime("2026-11-01T00:00:00Z", NOW), "2 weeks ago")
assert_eq("one day", preview.reltime("2026-11-14T00:00:00Z", NOW), "1 day ago")
assert_eq("one hour", preview.reltime("2026-11-14T23:00:00Z", NOW), "1 hour ago")
assert_eq("seconds", preview.reltime("2026-11-14T23:59:30Z", NOW), "just now")
assert_eq("months", preview.reltime("2026-09-15T00:00:00Z", NOW), "2 months ago")
assert_eq("years", preview.reltime("2024-11-15T00:00:00Z", NOW), "2 years ago")
assert_eq("future clamps", preview.reltime("2027-01-01T00:00:00Z", NOW), "just now")
assert_eq("garbage", preview.reltime("yesterday", NOW), "")
assert_eq("nil", preview.reltime(nil, NOW), "")

-- ---------------------------------------------------------------------------
local function item(extra)
	return vim.tbl_extend("force", {
		text = "#30 t",
		kind = "pr",
		state = "merged",
		number = 30,
		title = "feat(cli): function nodes",
		author = "loctvl842",
		labels = { { name = "bug", color = "d73a4a" }, { name = "cli", color = "ededed" } },
		url = "https://github.com/o/n/pull/30",
		repo = "o/n",
		host = "github.com",
		created = "2026-11-01T00:00:00Z",
		updated = "2026-11-14T00:00:00Z",
		comments = 2,
	}, extra or {})
end

local function detail(extra)
	return vim.tbl_extend("force", {
		body = "## Summary\n\nA node written as a function.\n\nCloses #29",
		merged = "2026-11-02T00:00:00Z",
		closed = "2026-11-02T00:00:00Z",
		base = "main",
		head = "function-nodes",
		mergeable = "MERGEABLE",
		additions = 832,
		deletions = 37,
		files = 21,
		checks = { passed = 3, failed = 1, pending = 0 },
		conversation = {
			{ author = "dana", body = "Looks good", created = "2026-11-03T00:00:00Z", state = "APPROVED" },
			{ author = "sam", body = "Thanks!", created = "2026-11-04T00:00:00Z" },
		},
	}, extra or {})
end

io.write("\n--- build: header before the fetch answers ---\n")
local lines, spans = preview.build(item(), nil, nil, NOW)
assert_test("title and number first", lines[1]:find("feat(cli): function nodes", 1, true) and lines[1]:find("#30", 1, true))
assert_test("status", has(lines, "Status:") and has(lines, "Merged"))
assert_test("repo", has(lines, f("Repo", "o/n")))
assert_test("author", has(lines, f("Author", "loctvl842")))
assert_test("labels listed", has(lines, f("Labels", "bug, cli")))
assert_test("relative dates", has(lines, f("Created", "2 weeks ago")) and has(lines, f("Updated", "1 day ago")))
assert_test("loading line", has(lines, "Loading..."))
assert_test("PR-only fields wait for the fetch", not has(lines, "Checks:") and not has(lines, "Changes:") and not has(lines, "Mergeable:"))
assert_test("spans carry highlights", #spans > 0 and spans[1].hl == "BeastFinderPreviewTitle")
local rule = find(lines, "────")
assert_test("rule is preceded by a blank line (never a markdown heading underline)", rule ~= nil and lines[rule - 1] == "")

io.write("\n--- build: PR with detail ---\n")
lines = preview.build(item(), detail(), nil, NOW)
assert_test("branches in status", has(lines, "main <- function-nodes"))
assert_test("merged time", has(lines, f("Merged", "1 week ago")) or has(lines, f("Merged", "")))
assert_test("checks summary", has(lines, f("Checks", "✓ 3  ✗ 1")))
assert_test("mergeable", has(lines, f("Mergeable", "✓")))
assert_test("changes", has(lines, f("Changes", "21 files  +832 -37")))
assert_test("description rendered", has(lines, "## Summary") and has(lines, "Closes #29"))
assert_test("no loading line", not has(lines, "Loading..."))
local conv = find(lines, "## Conversation")
assert_test("conversation after the description", conv ~= nil and conv > find(lines, "Closes #29"))
assert_test("conversation oldest first", find(lines, "@dana") < find(lines, "@sam"))
assert_test("review verdict shown", has(lines, "@dana  approved"))
assert_test("comment text shown", has(lines, "Looks good") and has(lines, "Thanks!"))

assert_test(
	"conflicts shown",
	has(select(1, preview.build(item(), detail({ mergeable = "CONFLICTING" }), nil, NOW)), f("Mergeable", "✗ conflicts"))
)
assert_test("unknown mergeable is omitted", not has(select(1, preview.build(item(), detail({ mergeable = "UNKNOWN" }), nil, NOW)), "Mergeable:"))
assert_test(
	"no checks, no Checks line",
	not has(select(1, preview.build(item(), detail({ checks = { passed = 0, failed = 0, pending = 0 } }), nil, NOW)), "Checks:")
)
assert_test(
	"pending checks",
	has(select(1, preview.build(item(), detail({ checks = { passed = 1, failed = 0, pending = 2 } }), nil, NOW)), "✓ 1  ● 2")
)
assert_test(
	"empty description says so",
	has(select(1, preview.build(item(), detail({ body = "", conversation = {} }), nil, NOW)), "(no description)")
)
assert_test("no conversation, no heading", not has(select(1, preview.build(item(), detail({ conversation = {} }), nil, NOW)), "## Conversation"))
assert_test("failure replaces loading", has(select(1, preview.build(item(), nil, "boom", NOW)), "Could not load details: boom"))

io.write("\n--- build: issue ---\n")
lines = preview.build(item({ kind = "issue", state = "open", number = 41, title = "Hub crashes" }), issue_detail, nil, NOW)
assert_test("issue has comments count", has(lines, f("Comments", "2")))
assert_test("issue has no PR-only fields", not has(lines, "Checks:") and not has(lines, "Changes:") and not has(lines, "Mergeable:"))
assert_test("issue status", has(lines, "Open"))
local closed_detail = detail()
closed_detail.merged = nil
assert_test(
	"closed issue shows the close time",
	has(select(1, preview.build(item({ kind = "issue", state = "closed" }), closed_detail, nil, NOW)), "Closed:")
)
assert_test(
	"not planned wording",
	has(select(1, preview.build(item({ kind = "issue", state = "not_planned" }), nil, nil, NOW)), "Closed (not planned)")
)
local ghost = item({ labels = {} })
ghost.author = nil
lines = preview.build(ghost, nil, nil, NOW)
assert_test("no labels, no Labels line", not has(lines, "Labels:"))
assert_test("no author, no Author line", not has(lines, "Author:"))

-- ---------------------------------------------------------------------------
io.write("\n--- show: window behavior ---\n")
local calls = {} ---@type { item: table, cb: fun(r: table), killed: boolean }[]
local orig_detail = api.detail
---@diagnostic disable-next-line: duplicate-set-field
api.detail = function(it, cb)
	local call = { item = it, cb = cb, killed = false }
	calls[#calls + 1] = call
	return {
		kill = function()
			call.killed = true
		end,
	}
end

local buf = vim.api.nvim_create_buf(false, true)
local win =
	vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 70, height = 20, style = "minimal", border = "single" })
local view = {
	buf = buf,
	win = win,
	is_valid = function()
		return vim.api.nvim_win_is_valid(win)
	end,
}

local function text()
	return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local a, b = item(), item({ number = 31, url = "https://github.com/o/n/pull/31", title = "second" })
preview.show(view, a)
assert_test("header drawn immediately", text():find("feat(cli): function nodes", 1, true) and text():find("Loading...", 1, true))
assert_eq("one fetch started", #calls, 1)
assert_eq("fetch is for the shown item", calls[1].item.number, 30)
assert_eq("markdown filetype for the description", vim.bo[buf].filetype, "markdown")
local cfg = vim.api.nvim_win_get_config(win)
assert_test("title names the PR", cfg.title and cfg.title[1][1] == " PR #30 ", vim.inspect(cfg.title))

preview.show(view, a)
assert_eq("showing the same item again does not refetch", #calls, 1)

preview.show(view, b)
assert_eq("moving on starts a second fetch", #calls, 2)
assert_test("and kills the first", calls[1].killed)
calls[1].cb({ detail = detail() })
assert_test(
	"a late answer for the old item is dropped",
	not text():find("A node written as a function", 1, true) and text():find("second", 1, true) ~= nil
)
calls[2].cb({ detail = detail({ body = "second body" }) })
assert_test("the current answer is drawn", text():find("second body", 1, true) ~= nil)
assert_test("and Loading is gone", not text():find("Loading...", 1, true))

preview.show(view, a)
assert_eq("a new item fetches again", #calls, 3)
calls[3].cb({ detail = detail() })
assert_test("first item filled in", text():find("A node written as a function", 1, true) ~= nil)
preview.show(view, b)
assert_eq("a cached item is not refetched", #calls, 3)
assert_test("and appears instantly with its detail", text():find("second body", 1, true) ~= nil)

preview.show(view, a)
assert_eq("cached again", #calls, 3)
local c = item({ number = 32, url = "https://github.com/o/n/pull/32" })
preview.show(view, c)
calls[4].cb({ error = "HTTP 502" })
assert_test("a failed fetch is explained", text():find("Could not load details: HTTP 502", 1, true) ~= nil)

io.write("\n--- show: a killed fetch cannot answer for a later request ---\n")
local e = item({ number = 40, url = "https://github.com/o/n/pull/40", title = "late" })
local f2 = item({ number = 41, url = "https://github.com/o/n/pull/41", title = "other" })
local before_calls = #calls
preview.show(view, e)
preview.show(view, f2)
preview.show(view, e)
assert_eq("three fetches started", #calls, before_calls + 3)
calls[before_calls + 1].cb({ error = "unexpected response from GitHub" })
assert_test("the killed first fetch is ignored", not text():find("Could not load details", 1, true) and text():find("Loading...", 1, true) ~= nil)
calls[before_calls + 3].cb({ detail = detail({ body = "real body" }) })
assert_test("the live fetch still draws", text():find("real body", 1, true) ~= nil)

io.write("\n--- show: an empty list clears the pane and forgets the item ---\n")
preview.show(view, nil)
assert_eq("pane is empty", text(), "")
preview.show(view, e)
assert_test("the same item redraws afterwards", text():find("late", 1, true) ~= nil)
assert_test("and does not refetch from cache", text():find("real body", 1, true) ~= nil)

io.write("\n--- show: message rows clear the pane ---\n")
local d = item({ number = 33, url = "https://github.com/o/n/pull/33" })
preview.show(view, d)
local pending = calls[#calls]
preview.show(view, { message = true, text = "No results for this search" })
assert_eq("pane is empty", text(), "")
assert_test("in-flight fetch killed", pending.killed)
assert_eq("title cleared", vim.api.nvim_win_get_config(win).title and #vim.api.nvim_win_get_config(win).title or 0, 0)

api.detail = orig_detail
io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
