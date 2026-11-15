-- =========================================================================
-- Test: GitHub finder sources (gh_pr / gh_issue) and their row format
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 3: what the source feeds
-- the pipeline (items, message rows, count), dropping stale responses, the
-- title following `repo:`, the pre-flight toast, and how rows are drawn.
-- The API module is faked; nothing runs `gh`.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-source.lua
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

_G.Util = {
	root = function()
		return "/proj"
	end,
}
local toasts = {}
_G.Toast = function(msg, level)
	toasts[#toasts + 1] = { msg = msg, level = level }
end

-- Fake API: records searches and lets the test answer them in any order.
local searches = {} ---@type { q: string, host: string, cb: fun(r: table), killed: boolean }[]
local check_result = { repo = { host = "github.com", slug = "o/n" } }
package.loaded["beast.libs.finder.source.gh.api"] = {
	check = function()
		return check_result.repo, check_result.err
	end,
	search = function(q, host, cb)
		local s = { q = q, host = host, cb = cb, killed = false }
		searches[#searches + 1] = s
		return {
			kill = function()
				s.killed = true
			end,
		}
	end,
}

local format = require("beast.libs.finder.format")
local gh = require("beast.libs.finder.source.gh")

local function gh_item(n, extra)
	return vim.tbl_extend("force", {
		text = "#" .. n .. " t",
		kind = "pr",
		state = "open",
		number = n,
		title = "title " .. n,
		author = "dana",
		labels = {},
		url = "https://github.com/o/n/pull/" .. n,
	}, extra or {})
end

--- Run source.get and collect what it emits.
---@return table[] items
---@return boolean finished
local function run(source, pattern, answer)
	local items, finished = {}, false
	source.get({ pattern = pattern }, function(item)
		if item == nil then
			finished = true
		else
			items[#items + 1] = item
		end
	end)
	if answer then
		searches[#searches].cb(answer)
	end
	return items, finished
end

-- ---------------------------------------------------------------------------
io.write("\n--- source shape ---\n")
local pr = gh.create("pr")
local issue = gh.create("issue")
assert_eq("pr default text", pr.initial_query, "is:pr state:open ")
assert_eq("issue default text", issue.initial_query, "is:issue state:open ")
assert_test("live and async", pr.live and pr.async)
assert_test("keeps results while searching", pr.retain_results)
assert_test("searches an empty prompt", pr.run_when_empty)
assert_eq("debounce respects the search rate limit", pr.debounce_ms, 400)

-- ---------------------------------------------------------------------------
io.write("\n--- check ---\n")
check_result = { repo = nil, err = "No GitHub remote found for this directory" }
assert_eq("check fails without a repo", pr.check(), false)
assert_eq("failure is a warning toast", toasts[1] and toasts[1].msg, "No GitHub remote found for this directory")
assert_eq("toast level", toasts[1] and toasts[1].level, vim.log.levels.WARN)
check_result = { repo = { host = "github.com", slug = "o/n" } }
assert_eq("check passes with a repo", pr.check(), true)
assert_eq("title names the kind and repo", pr.title(), "Pull Requests - o/n")
assert_eq(
	"issue title",
	(function()
		issue.check()
		return issue.title()
	end)(),
	"Issues - o/n"
)
assert_eq("title follows repo: in the prompt", pr.title({ pattern = "repo:neovim/neovim is:pr" }), "Pull Requests - neovim/neovim")

-- ---------------------------------------------------------------------------
io.write("\n--- results ---\n")
local items, finished = run(pr, "is:pr state:open ", { items = { gh_item(2), gh_item(1) }, total = 2 })
assert_eq("query is built with repo and sort", searches[#searches].q, "is:pr state:open repo:o/n sort:created-desc")
assert_eq("host passed through", searches[#searches].host, "github.com")
assert_eq("items emitted", #items, 2)
assert_eq("idx numbers the rows", items[2].idx, 2)
assert_test("finished", finished)
assert_eq("count", pr.count(items), "2/2")

items = run(pr, "", { items = { gh_item(1) }, total = 250 })
assert_eq("count says more exist when capped", pr.count(items), "1+")

items, finished = run(pr, "label:nope", { items = {}, total = 0 })
assert_eq("empty search gives one message row", #items, 1)
assert_test("message row is flagged", items[1].message == true and not items[1].is_error)
assert_eq("message text", items[1].text, "No results for this search")
assert_test("finished", finished)
assert_eq("count ignores message rows", pr.count(items), "0/0")

items = run(pr, "repo:x/y", { error = { kind = "not_found", message = "repository not found or no access to it" } })
assert_eq("error gives two message rows", #items, 2)
assert_eq("error headline", items[1].text, "GitHub could not run this search:")
assert_eq("error reason", items[2].text, "repository not found or no access to it")
assert_test("error rows are error colored", items[1].is_error and items[2].is_error)
assert_eq("no count after an error", pr.count(items), "")

-- ---------------------------------------------------------------------------
io.write("\n--- stale responses ---\n")
local before = #searches
local first_items, first_finished = {}, false
pr.get({ pattern = "a" }, function(item)
	if item == nil then
		first_finished = true
	else
		first_items[#first_items + 1] = item
	end
end)
local first = searches[#searches]
local second_items = run(pr, "ab")
assert_test("starting a search kills the previous process", first.killed)
first.cb({ items = { gh_item(9) }, total = 1 })
assert_eq("late answer of the older search is dropped", #first_items, 0)
assert_test("and it never reports finished", not first_finished)
searches[#searches].cb({ items = { gh_item(3) }, total = 1 })
assert_eq("the newer answer still arrives", #second_items, 1)

local cancelled_items = {}
pr.get({ pattern = "c" }, function(item)
	if item then
		cancelled_items[#cancelled_items + 1] = item
	end
end)
local live = searches[#searches]
pr.cancel()
assert_test("cancel kills the process", live.killed)
live.cb({ items = { gh_item(4) }, total = 1 })
assert_eq("answers after cancel are dropped", #cancelled_items, 0)

-- ---------------------------------------------------------------------------
io.write("\n--- row format ---\n")
local function texts(chunks)
	return table.concat(vim.tbl_map(function(c)
		return c.text
	end, chunks))
end
local function hls(chunks)
	return vim.tbl_map(function(c)
		return c.hl or "-"
	end, chunks)
end

local row = format.gh_pr(gh_item(30, { labels = { { name = "bug", color = "d73a4a" } } }))
assert_test(
	"row has number, title, author and label",
	texts(row):find("#30", 1, true) and texts(row):find("title 30", 1, true) and texts(row):find("@dana", 1, true) and texts(row):find(" bug ", 1, true),
	texts(row)
)
assert_eq("open pr icon color", row[1].hl, "BeastFinderGhOpen")
assert_eq("draft pr icon color", format.gh_pr(gh_item(1, { state = "draft" }))[1].hl, "BeastFinderGhDraft")
assert_eq("merged pr icon color", format.gh_pr(gh_item(1, { state = "merged" }))[1].hl, "BeastFinderGhMerged")
assert_eq("closed pr icon color", format.gh_pr(gh_item(1, { state = "closed" }))[1].hl, "BeastFinderGhClosed")
assert_eq("closed issue is purple", format.gh_issue(gh_item(1, { kind = "issue", state = "closed" }))[1].hl, "BeastFinderGhMerged")
assert_eq("not planned issue is grey", format.gh_issue(gh_item(1, { kind = "issue", state = "not_planned" }))[1].hl, "BeastFinderGhDraft")
assert_test("issue and pr icons differ", format.gh_pr(gh_item(1))[1].text ~= format.gh_issue(gh_item(1, { kind = "issue" }))[1].text)
assert_test("label badge uses its own group", hls(row)[#row]:find("^BeastFinderGhLabel") ~= nil, vim.inspect(hls(row)))
local ghost = gh_item(1)
ghost.author = nil
local no_author = format.gh_pr(ghost)
assert_test("no author, no @", not texts(no_author):find("@", 1, true))

local msg = format.gh_pr({ message = true, text = "No results for this search" })
assert_eq("message row text", texts(msg), "No results for this search")
assert_eq("message row dim", msg[1].hl, "BeastFinderGhMessage")
assert_eq("error row color", format.gh_pr({ message = true, is_error = true, text = "x" })[1].hl, "BeastFinderGhError")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
