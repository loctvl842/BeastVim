-- =========================================================================
-- Test: GitLab finder sources (gl_mr / gl_issue)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 3: what the sources feed the pipeline (items,
-- message rows, count), flag errors without a request, the unknown-user explanation, stale answers,
-- the title bar with the host and `project:`, and the pre-flight toast. vim.system is scripted.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gl-source.lua
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
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
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
_G.Git = require("beast.libs.git")
local gl = dofile("tests/helpers/gl.lua")
local source_gl = require("beast.libs.finder.source.gl")

local MR_LIST = gl.req("gitlab.com", "projects/o%2Fn/merge_requests")

--- Run source.get and collect what it emits, once the answer arrived.
---@return table[] items
---@return boolean finished
local function run(source, pattern)
	local items, finished = {}, false
	source.get({ pattern = pattern }, function(item)
		if item == nil then
			finished = true
		else
			items[#items + 1] = item
		end
	end)
	vim.wait(500, function()
		return finished
	end)
	return items, finished
end

-- ---------------------------------------------------------------------------
io.write("\n--- source shape ---\n")
gl.install()
local mr = source_gl.create("mr")
local issue = source_gl.create("issue")
assert_eq("default text", mr.initial_query, "state:opened ")
assert_eq("issue default text", issue.initial_query, "state:opened ")
assert_test("live and async", mr.live and mr.async)
assert_test("keeps results while searching", mr.retain_results)
assert_test("searches an empty prompt", mr.run_when_empty)
assert_eq("debounce", mr.debounce_ms, 400)
assert_eq("registered as a source", require("beast.libs.finder.source").gl_mr.name, "gl_mr")

-- ---------------------------------------------------------------------------
io.write("\n--- check and title ---\n")
gl.script["git -C"] = gl.ok("")
assert_eq("check fails without a remote", mr.check(), false)
assert_eq("failure is a warning toast", toasts[1] and toasts[1].msg, "No GitLab remote found for this directory")
assert_eq("toast level", toasts[1] and toasts[1].level, vim.log.levels.WARN)
gl.restore()

gl.install()
assert_eq("check passes on a gitlab.com remote", mr.check(), true)
assert_eq("title on gitlab.com has no host", mr.title(), "Merge Requests - o/n")
assert_eq("title follows project:", mr.title({ pattern = "project:a/b/c" }), "Merge Requests - a/b/c")
issue.check()
assert_eq("issue title", issue.title(), "Issues - o/n")
gl.restore()

gl.install("git@gitlab.acme.dev:platform/payments/api.git")
mr.check()
assert_eq("title on a self-hosted server names the host", mr.title(), "Merge Requests - gitlab.acme.dev/platform/payments/api")
assert_eq("project: on a self-hosted server keeps the host", mr.title({ pattern = "project:x/y" }), "Merge Requests - gitlab.acme.dev/x/y")
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- results ---\n")
gl.install()
mr.check()
gl.script[MR_LIST] = gl.http({ gl.mr(2, "Second"), gl.mr(1, "First") }, { ["X-Total"] = "2" })
local items, finished = run(mr, "state:opened ")
assert_eq("items emitted", #items, 2)
assert_eq("idx numbers the rows", items[2].idx, 2)
assert_test("finished", finished)
assert_eq("count", mr.count(items), "2/2")
assert_eq("rows keep the host's reference", items[1].ref, "!2")

gl.script[MR_LIST] = gl.http({ gl.mr(1, "First") }, { ["X-Total"] = "250" })
items = run(mr, "")
assert_eq("count says more exist when capped", mr.count(items), "1+")

gl.script[MR_LIST] = gl.http({})
items = run(mr, "label:nope")
assert_eq("empty search gives one message row", #items, 1)
assert_test("message row is flagged", items[1].message == true and not items[1].is_error)
assert_eq("message text", items[1].text, "No results for this search")
assert_eq("count of nothing", mr.count({}), "0/0")

-- ---------------------------------------------------------------------------
io.write("\n--- mistakes in the text make no request ---\n")
local before = #gl.calls
items = run(mr, "state:opened colour:red")
assert_eq("no request", #gl.calls, before)
assert_eq("two message rows", #items, 2)
assert_eq("first row", items[1].text, 'Unknown filter "colour:".')
assert_test("both are errors", items[1].is_error and items[2].is_error)
assert_test("hint lists the flags", items[2].text:find("Available: state, author", 1, true) ~= nil)
assert_eq("no count after an error", mr.count(items), "")

-- ---------------------------------------------------------------------------
io.write("\n--- failed search ---\n")
gl.script[MR_LIST] = gl.http_error(404, "404 Project Not Found")
items = run(mr, "state:opened ")
assert_eq("heading names the host", items[1].text, "GitLab could not run this search:")
assert_eq("reason", items[2].text, "project not found or no access to it")
assert_test("rows are errors", items[1].is_error and items[2].is_error)

-- ---------------------------------------------------------------------------
io.write("\n--- empty answer with a named user ---\n")
gl.script[MR_LIST] = gl.http({})
local USERS = gl.req("gitlab.com", "users")
gl.script[USERS] = gl.http({})
items = run(mr, "state:opened author:nobody-here")
assert_eq("heading", items[1].text, "GitLab could not run this search:")
assert_eq("explains the empty answer", items[2].text, 'user "nobody-here" was not found')
assert_eq("no count", mr.count(items), "")

gl.script[USERS] = gl.http({ { username = "dao" } })
items = run(mr, "state:opened author:dao")
assert_eq("a real user with no match is just empty", items[1].text, "No results for this search")

local users_before = gl.count(USERS)
gl.script[MR_LIST] = gl.http({ gl.mr(1, "t") })
run(mr, "author:dao")
assert_eq("users are only checked when the answer is empty", gl.count(USERS), users_before)
gl.script[MR_LIST] = gl.http({})
run(mr, "state:opened")
assert_eq("and only when the text names one", gl.count(USERS), users_before)
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- stale answers are dropped ---\n")
gl.install()
mr.check()
gl.script[MR_LIST] = gl.http({ gl.mr(1, "old") })
gl.hold = { MR_LIST }
local old_items, new_items = {}, {}
mr.get({ pattern = "first" }, function(item)
	old_items[#old_items + 1] = item or "end"
end)
gl.hold = {}
gl.script[MR_LIST] = gl.http({ gl.mr(9, "new") })
mr.get({ pattern = "second" }, function(item)
	new_items[#new_items + 1] = item or "end"
end)
vim.wait(500, function()
	return #new_items > 0 and new_items[#new_items] == "end"
end)
gl.release()
vim.wait(100)
assert_eq("older search emits nothing", #old_items, 0)
assert_eq("newer search emitted", new_items[1] and new_items[1].number, 9)

mr.cancel()
gl.restore()

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
