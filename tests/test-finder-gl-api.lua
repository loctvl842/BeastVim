-- =========================================================================
-- Test: `glab` wrapper for the GitLab finder sources (gl/api.lua)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 3: check(), argv of the list request (host, encoded
-- project path, parameters), --include parsing, totals, @me, normalization, error classes, detail, user_exists.
-- vim.system is scripted (tests/helpers/gl.lua); nothing runs `glab`.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gl-api.lua
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
_G.Git = require("beast.libs.git")
local gl = dofile("tests/helpers/gl.lua")
local api = require("beast.libs.finder.source.gl.api")

--- Run one search and wait for its answer.
---@return table result
local function search(kind, project, params, host)
	local result
	api.search(kind, project, params, host or "gitlab.com", function(r)
		result = r
	end)
	vim.wait(500, function()
		return result ~= nil
	end)
	return result
end

local MR_LIST = gl.req("gitlab.com", "projects/o%2Fn/merge_requests")

-- ---------------------------------------------------------------------------
io.write("\n--- project_id ---\n")
assert_eq("slash becomes %2F", api.project_id("platform/payments/api"), "platform%2Fpayments%2Fapi")

-- ---------------------------------------------------------------------------
io.write("\n--- check ---\n")
gl.install()
local repo, err = api.check("/x")
assert_eq("a gitlab.com remote passes", repo and repo.slug, "o/n")
assert_eq("no error", err, nil)
assert_test("login is asked for the remote's host", gl.calls[#gl.calls] == "glab auth status --hostname gitlab.com")

gl.script["glab auth status"] = gl.fail("not logged in")
repo, err = api.check("/x")
assert_eq("not logged in", repo, nil)
assert_eq("login hint names the host", err, "Run `glab auth login --hostname gitlab.com` first")
gl.restore()

gl.install("git@git.acme.dev:platform/payments/api.git")
repo, err = api.check("/x")
assert_eq("unknown host: no gitlab remote", repo, nil)
assert_eq("unknown host: names it and the setting", err, "git.acme.dev is not known as a GitLab server. Add it to the git remote hosts setting.")
gl.restore()

gl.install("git@github.com:o/n.git")
repo, err = api.check("/x")
assert_eq("a GitHub-only repo has no GitLab remote", err, "No GitLab remote found for this directory")
gl.restore()

gl.install("git@gitlab.acme.dev:platform/payments/api.git")
repo, err = api.check("/x")
assert_eq("self-hosted nested remote passes", repo and (repo.host .. "|" .. repo.slug), "gitlab.acme.dev|platform/payments/api")
assert_test("login check uses the self-hosted host", gl.calls[#gl.calls] == "glab auth status --hostname gitlab.acme.dev")
gl.restore()

local real_executable = vim.fn.executable
gl.install()
vim.fn.executable = function()
	return 0
end
repo, err = api.check("/x")
assert_eq("glab missing", err, "GitLab CLI (glab) is not installed")
gl.restore()
vim.fn.executable = real_executable

-- ---------------------------------------------------------------------------
io.write("\n--- search: request ---\n")
gl.install()
gl.script[MR_LIST] = gl.http({ gl.mr(2, "Second"), gl.mr(1, "First") }, { ["X-Total"] = "2" })
local result = search("mr", "o/n", { state = "opened", search = "retry", labels = "bug,backend" })
assert_eq(
	"argv: host, encoded project, sorted parameters, defaults",
	gl.calls[#gl.calls],
	MR_LIST .. " -f labels=bug,backend -f order_by=created_at -f per_page=100 -f search=retry -f sort=desc -f state=opened -f with_labels_details=true"
)
assert_eq("two items", #result.items, 2)
assert_eq("total from the header", result.total, 2)
gl.restore()

gl.install("git@git.acme.dev:platform/payments/api.git")
gl.script[gl.req("git.acme.dev", "projects/platform%2Fpayments%2Fapi/issues")] = gl.http({})
search("issue", "platform/payments/api", { state = "opened", ["in"] = "title,description" }, "git.acme.dev")
assert_test(
	"self-hosted: --hostname and nested path",
	gl.calls[#gl.calls]:find("--hostname git.acme.dev --include projects/platform%2Fpayments%2Fapi/issues", 1, true) ~= nil
)
assert_test("issues: title and description are searched", gl.calls[#gl.calls]:find("-f in=title,description", 1, true) ~= nil)
gl.restore()

gl.install()
gl.script[MR_LIST] = gl.http({ gl.mr(1, "t") }, { ["X-Next-Page"] = "2" })
assert_eq("no total but a next page says there is more", search("mr", "o/n", { state = "opened" }).total, 2)
gl.script[MR_LIST] = gl.http({ gl.mr(1, "t") }, { ["X-Next-Page"] = "" })
assert_eq("no total and no next page counts the items", search("mr", "o/n", { state = "opened" }).total, 1)

-- ---------------------------------------------------------------------------
io.write("\n--- search: @me ---\n")
gl.install()
gl.script[gl.req("gitlab.com", "user")] = gl.http({ username = "loctvl842" })
gl.script[MR_LIST] = gl.http({})
search("mr", "o/n", { state = "opened", author_username = "@me", assignee_username = "@me" })
assert_test("@me is replaced by the logged-in user", gl.calls[#gl.calls]:find("-f author_username=loctvl842", 1, true) ~= nil)
assert_test("in every flag", gl.calls[#gl.calls]:find("-f assignee_username=loctvl842", 1, true) ~= nil)
assert_eq("the user was asked for once", gl.count(gl.req("gitlab.com", "user")), 1)
search("mr", "o/n", { author_username = "@me" })
assert_eq("and remembered", gl.count(gl.req("gitlab.com", "user")), 1)
gl.script[gl.req("gitlab.com", "user")] = gl.http_error(401, "401 Unauthorized")
api.reset()
result = search("mr", "o/n", { author_username = "@me" })
assert_eq("a failing user lookup is the search's error", result.error and result.error.kind, "auth")

-- ---------------------------------------------------------------------------
io.write("\n--- normalize ---\n")
local item = api.normalize(
	"mr",
	gl.mr(412, "Retry", {
		draft = true,
		labels = { { name = "backend", color = "#428BCA" }, { name = "priority::high", color = "#ff8800" } },
		user_notes_count = 3,
		references = { full = "platform/payments/api!412" },
	}),
	"git.acme.dev"
)
assert_eq("provider", item.provider, "gitlab")
assert_eq("kind stays pr", item.kind, "pr")
assert_eq("ref", item.ref, "!412")
assert_eq("number is the iid", item.number, 412)
assert_eq("draft state", item.state, "draft")
assert_eq("text", item.text, "!412 Retry")
assert_eq("repo is the full project path", item.repo, "platform/payments/api")
assert_eq("host", item.host, "git.acme.dev")
assert_eq("author", item.author, "dao")
assert_eq("comments", item.comments, 3)
assert_eq("url", item.url, "https://gitlab.com/o/n/-/merge_requests/412")
assert_eq("label colors lose the #", item.labels, { { name = "backend", color = "428BCA" }, { name = "priority::high", color = "ff8800" } })
assert_eq(
	"plain label names get a grey",
	api.normalize("issue", gl.issue(1, "t", { labels = { "bug" } }), "h").labels,
	{ { name = "bug", color = "888888" } }
)
assert_eq("merged", api.normalize("mr", gl.mr(1, "t", { state = "merged" }), "h").state, "merged")
assert_eq("closed", api.normalize("mr", gl.mr(1, "t", { state = "closed" }), "h").state, "closed")
assert_eq("locked reads as closed", api.normalize("mr", gl.mr(1, "t", { state = "locked" }), "h").state, "closed")
assert_eq("open", api.normalize("mr", gl.mr(1, "t"), "h").state, "open")
local issue = api.normalize("issue", gl.issue(207, "Bug"), "h")
assert_eq("issue kind", issue.kind, "issue")
assert_eq("issue ref", issue.ref, "#207")
assert_eq("issue never draft", api.normalize("issue", gl.issue(1, "t", { draft = true }), "h").state, "open")
assert_eq("issue body for the grep", issue.body, "desc 207")

-- ---------------------------------------------------------------------------
io.write("\n--- search: errors ---\n")
gl.install()
gl.script[MR_LIST] = gl.http_error(404, "404 Project Not Found")
assert_eq("404", search("mr", "o/n", {}).error, { kind = "not_found", message = "project not found or no access to it" })
gl.script[MR_LIST] = gl.http_error(401, "401 Unauthorized")
assert_eq(
	"401 names the host in the login hint",
	search("mr", "o/n", {}).error.message,
	"GitLab login expired, run `glab auth login --hostname gitlab.com`"
)
gl.script[MR_LIST] = gl.http_error(429, "Retry later", { ["Retry-After"] = "42" })
result = search("mr", "o/n", {})
assert_eq("429 kind", result.error.kind, "rate_limit")
assert_eq("429 says when it lifts", result.error.message, "GitLab rate limit reached, resets in 42s")
gl.script[MR_LIST] = gl.http_error(429, "Retry later", { ["RateLimit-Reset"] = tostring(os.time() + 30) })
assert_test("429 without Retry-After uses the reset time", search("mr", "o/n", {}).error.message:match("resets in %d+s$") ~= nil)
gl.script[MR_LIST] = gl.http_error(429, "Retry later")
assert_eq("429 with no hint", search("mr", "o/n", {}).error.message, "GitLab rate limit reached")
gl.script[MR_LIST] = { code = 1, stdout = "", stderr = 'ERROR Get "https://git.acme.dev/api/v4/x": dial tcp: lookup git.acme.dev: no such host' }
assert_eq("unknown host is a network error", search("mr", "o/n", {}).error, { kind = "network", message = "cannot reach gitlab.com" })
gl.script[MR_LIST] = gl.http_error(400, "400 Bad request - invalid labels")
assert_eq("other errors keep GitLab's message", search("mr", "o/n", {}).error.message, "400 Bad request - invalid labels")
gl.script[MR_LIST] = gl.ok("<html>502 Bad Gateway</html>")
assert_eq("a non-JSON answer", search("mr", "o/n", {}).error.message, "unexpected response from GitLab")
gl.script[MR_LIST] = gl.ok("HTTP/2.0 200 OK\r\n\r\n<html>502</html>")
assert_eq("a non-JSON answer after headers", search("mr", "o/n", {}).error.message, "unexpected response from GitLab")

-- ---------------------------------------------------------------------------
io.write("\n--- search: kill ---\n")
gl.install()
gl.script[MR_LIST] = gl.http({ gl.mr(1, "t") })
gl.hold = { MR_LIST }
local answered = false
local handle = api.search("mr", "o/n", { state = "opened" }, "gitlab.com", function()
	answered = true
end)
assert_test("kill does not raise", pcall(handle.kill))
gl.release()
vim.wait(100)
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- user_exists ---\n")
gl.install()
local USERS = gl.req("gitlab.com", "users")
local function exists(name)
	local out
	api.user_exists("gitlab.com", name, function(v)
		out = v
	end)
	vim.wait(500, function()
		return out ~= nil
	end)
	return out
end
gl.script[USERS] = gl.http({ { username = "dao" } })
assert_eq("known user", exists("dao"), true)
assert_test("asks by username", gl.calls[#gl.calls]:find("-f username=dao", 1, true) ~= nil)
gl.script[USERS] = gl.http({})
assert_eq("unknown user", exists("nobody"), false)
gl.script[USERS] = gl.http_error(403, "403 Forbidden")
assert_eq("a failing check gives the benefit of the doubt", exists("x"), true)

-- ---------------------------------------------------------------------------
io.write("\n--- detail ---\n")
gl.install()
local mr_item = api.normalize("mr", gl.mr(412, "Retry", { references = { full = "platform/payments/api!412" } }), "gitlab.com")
local base = "projects/platform%2Fpayments%2Fapi/merge_requests/412"
gl.script[gl.req("gitlab.com", base)] = gl.http({
	description = "Retry with backoff",
	source_branch = "retry-backoff",
	target_branch = "main",
	changes_count = "6",
	has_conflicts = false,
	detailed_merge_status = "mergeable",
	head_pipeline = { status = "success" },
	reviewers = { { username = "mina" }, { username = "lee" } },
	assignees = { { username = "dao" } },
	milestone = { title = "2026.4" },
	merged_at = nil,
})
gl.script[gl.req("gitlab.com", base .. "/notes")] = gl.http({
	{ system = true, author = { username = "bot" }, body = "added label ~bug", created_at = "2026-11-11T00:00:00.000Z" },
	{ system = false, author = { username = "mina" }, body = "Looks good", created_at = "2026-11-12T00:00:00.000Z" },
})
local out
api.detail(mr_item, function(r)
	out = r
end)
vim.wait(500, function()
	return out ~= nil
end)
local d = out.detail
assert_eq("body", d.body, "Retry with backoff")
assert_eq("branches", { d.base, d.head }, { "main", "retry-backoff" })
assert_eq("file count from a string", d.files, 6)
assert_eq("no line totals", { d.additions, d.deletions }, { nil, nil })
assert_eq("no checks", d.checks, nil)
assert_eq("pipeline", d.pipeline, "✓ passed")
assert_eq("mergeable", d.mergeable, "MERGEABLE")
assert_eq("reviewers", d.reviewers, { "mina", "lee" })
assert_eq("assignees", d.assignees, { "dao" })
assert_eq("milestone", d.milestone, "2026.4")
assert_eq("system notes are left out", #d.conversation, 1)
assert_eq("conversation entry", d.conversation[1], { author = "mina", body = "Looks good", created = "2026-11-12T00:00:00.000Z" })
assert_eq("notes are asked oldest first", select(2, gl.calls[#gl.calls]:gsub("sort=asc", "")), 1)

local N = api.normalize_detail
assert_eq("more than a thousand files", N("mr", { changes_count = "1000+" }, {}).files, 1000)
assert_eq("conflicts", N("mr", { has_conflicts = true }, {}).mergeable, "CONFLICTING")
assert_eq("conflict status", N("mr", { detailed_merge_status = "conflict" }, {}).mergeable, "CONFLICTING")
assert_eq("other merge statuses are left out", N("mr", { detailed_merge_status = "ci_must_pass" }, {}).mergeable, nil)
assert_eq("failed pipeline", N("mr", { head_pipeline = { status = "failed" } }, {}).pipeline, "✗ failed")
assert_eq("running pipeline", N("mr", { head_pipeline = { status = "running" } }, {}).pipeline, "● running")
assert_eq("waiting pipeline", N("mr", { head_pipeline = { status = "waiting_for_resource" } }, {}).pipeline, "● waiting for resource")
assert_eq("canceled pipeline", N("mr", { head_pipeline = { status = "canceled" } }, {}).pipeline, "canceled")
assert_eq("issue has no branches or files", N("issue", { description = "x" }, {}).base, nil)

gl.script[gl.req("gitlab.com", base)] = gl.http_error(404, "404 Not Found")
out = nil
api.detail(mr_item, function(r)
	out = r
end)
vim.wait(500, function()
	return out ~= nil
end)
assert_eq("a failed request is a message", out.error, "project not found or no access to it")

assert_eq("commit url has the /-/ segment", api.commit_url(mr_item, "abc"), "https://gitlab.com/platform/payments/api/-/commit/abc")
gl.restore()

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
