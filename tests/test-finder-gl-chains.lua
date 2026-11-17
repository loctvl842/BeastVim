-- =========================================================================
-- Test: GitLab drill-down (files, commits, commit files, issue grep, chain edges)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 4: the glab requests behind the shared sources,
-- their normalization (status from flags, line counts from hunks, newest-first commits reversed),
-- truncation, the sources run on a merge request item, and the new edges. vim.system is scripted.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gl-chains.lua
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

local mr =
	api.normalize("mr", gl.mr(6, "Retry failed webhooks with backoff", { references = { full = "platform/payments/api!6" } }), "gitlab.acme.dev")
local HOST = "gitlab.acme.dev"
local BASE = "projects/platform%2Fpayments%2Fapi"

local function wait_for(start)
	local out
	start(function(r)
		out = r
	end)
	vim.wait(1000, function()
		return out ~= nil
	end)
	return out
end

--- Run source.get and collect what it emits.
local function run(source, filter)
	local items, finished = {}, false
	source.get(filter, function(item)
		if item == nil then
			finished = true
		else
			items[#items + 1] = item
		end
	end)
	vim.wait(1000, function()
		return finished
	end)
	return items
end

-- ---------------------------------------------------------------------------
io.write("\n--- normalize_file ---\n")
local f = api.normalize_file(gl.diffs(1)[1])
assert_eq("path", f.path, "src/f1.lua")
assert_eq("modified", f.status, "modified")
assert_eq("additions counted from the hunk", f.additions, 2)
assert_eq("deletions counted from the hunk", f.deletions, 1)
assert_test("patch kept", f.patch ~= nil and f.patch:find("^@@") ~= nil)
assert_eq("new file", api.normalize_file({ new_path = "a", old_path = "a", new_file = true, diff = "@@ -0,0 +1 @@\n+x\n" }).status, "added")
assert_eq("deleted file", api.normalize_file({ new_path = "a", old_path = "a", deleted_file = true, diff = "@@ -1 +0,0 @@\n-x\n" }).status, "removed")
local renamed = api.normalize_file({ new_path = "b.lua", old_path = "a.lua", renamed_file = true, diff = "" })
assert_eq("renamed", renamed.status, "renamed")
assert_eq("previous path", renamed.previous, "a.lua")
assert_eq("an empty diff is no patch", renamed.patch, nil)
assert_eq(
	"too large is no patch",
	api.normalize_file({ new_path = "a", old_path = "a", too_large = true, diff = "@@ -1 +1 @@\n-a\n+b\n" }).patch,
	nil
)
assert_eq(
	"collapsed is no patch",
	api.normalize_file({ new_path = "a", old_path = "a", collapsed = true, diff = "@@ -1 +1 @@\n-a\n+b\n" }).patch,
	nil
)
assert_eq("a path is not previous when not renamed", f.previous, nil)

-- ---------------------------------------------------------------------------
io.write("\n--- files ---\n")
gl.install()
local DIFFS = gl.req(HOST, BASE .. "/merge_requests/6/diffs")
gl.script[DIFFS] = gl.http(gl.diffs(3))
local res = wait_for(function(cb)
	api.files(mr, cb)
end)
assert_eq("three files", #res.files, 3)
assert_eq("not truncated", res.truncated, nil)
assert_eq("request: host, nested project, paging", gl.calls[#gl.calls], DIFFS .. " -f page=1 -f per_page=100")

-- 3 full pages and a fourth with something in it
gl.script[DIFFS .. " -f page=1"] = gl.http(gl.diffs(100, "a", 1))
gl.script[DIFFS .. " -f page=2"] = gl.http(gl.diffs(100, "b", 1))
gl.script[DIFFS .. " -f page=3"] = gl.http(gl.diffs(100, "c", 1))
gl.script[DIFFS .. " -f page=4"] = gl.http(gl.diffs(1, "d", 1))
res = wait_for(function(cb)
	api.files(mr, cb)
end)
assert_eq("three pages are kept", #res.files, 300)
assert_eq("a fourth page with files says it was cut short", res.truncated, true)
gl.script[DIFFS .. " -f page=4"] = gl.http({})
res = wait_for(function(cb)
	api.files(mr, cb)
end)
assert_eq("an empty fourth page is not truncated", res.truncated, false)

gl.script[DIFFS .. " -f page=1"] = gl.http_error(404, "404 Not Found")
res = wait_for(function(cb)
	api.files(mr, cb)
end)
assert_eq("an error is returned", res.error and res.error.kind, "not_found")
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- commits ---\n")
gl.install()
local COMMITS = gl.req(HOST, BASE .. "/merge_requests/6/commits")
gl.script[COMMITS] = gl.http(gl.commits(3))
res = wait_for(function(cb)
	api.commits(mr, cb)
end)
assert_eq(
	"GitLab answers newest first, we hand them over oldest first",
	{ res.commits[1].subject, res.commits[3].subject },
	{ "Commit 1 subject", "Commit 3 subject" }
)
assert_eq("short id", res.commits[1].short, "00000001")
assert_eq("author", res.commits[1].author, "Author 1")
assert_eq("message keeps the body", res.commits[1].message, "Commit 1 subject\n\nBody of commit 1")
assert_eq("sha", #res.commits[1].sha, 40)
assert_eq("date keeps its offset", res.commits[1].date, "2026-11-11T17:00:00.000+07:00")

-- the shared source lists them newest first again, with GitLab's commit url
local commits_source = require("beast.libs.finder.source.gh_commits")
local items = run(commits_source, { ctx = { pr = mr }, cwd = "/proj" })
assert_eq("three rows", #items, 3)
assert_eq("newest first", items[1].subject, "Commit 3 subject")
assert_eq("idx follows the row order", items[1].idx, 1)
assert_eq("gitlab commit url", items[1].url, "https://gitlab.acme.dev/platform/payments/api/-/commit/" .. items[1].sha)
assert_eq("title says MR", commits_source.title({ ctx = { pr = mr } }, items), "MR Retry failed webhooks with backoff › Commits (3)")

gl.script[COMMITS] = gl.http_error(404, "404 Not Found")
items = run(commits_source, { ctx = { pr = mr }, cwd = "/proj" })
assert_eq("failure heading names GitLab", items[1].text, "GitLab could not list the commits:")
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- files source on a merge request ---\n")
gl.install()
gl.script[DIFFS] = gl.http({
	{ old_path = "a.lua", new_path = "a.lua", diff = "@@ -1 +1 @@\n-a\n+b\n" },
	{ old_path = "old.lua", new_path = "new.lua", renamed_file = true, diff = "" },
})
local files_source = require("beast.libs.finder.source.gh_pr_files")
local filter = { ctx = { pr = mr }, cwd = "/proj" }
items = run(files_source, filter)
assert_eq("rows", #items, 2)
assert_eq("file", items[1].file, "a.lua")
assert_eq("owner is the merge request", items[1].pr.ref, "!6")
assert_eq("rename keeps its previous path", items[2].previous, "old.lua")
assert_eq("title", files_source.title(filter, items), "MR Retry failed webhooks with backoff › Files Changed (2)")
gl.script[DIFFS] = gl.http({})
items = run(files_source, { ctx = { pr = mr }, cwd = "/proj" })
assert_eq("no files", items[1].text, "No files changed")
gl.script[DIFFS] = gl.http_error(401, "401 Unauthorized")
items = run(files_source, { ctx = { pr = mr }, cwd = "/proj" })
assert_eq("failure heading names GitLab", items[1].text, "GitLab could not list the files:")
assert_eq("failure reason names the host's login", items[2].text, "GitLab login expired, run `glab auth login --hostname gitlab.acme.dev`")
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- commit files ---\n")
gl.install()
local sha = ("%08dabcdef0123456789abcdef0123456789"):format(2):sub(1, 40)
local commit_item =
	{ sha = sha, short = "00000002", subject = "Commit 2 subject", body = "Commit 2 subject", author = "Author 2", date = "", pr = mr, cwd = "/proj" }
local CDIFF = gl.req(HOST, BASE .. "/repository/commits/" .. sha .. "/diff")
gl.script[CDIFF] = gl.http(gl.diffs(2, "c"))
local commit_preview = require("beast.libs.finder.source.gh.commit_preview")
commit_preview.reset()
res = wait_for(function(cb)
	commit_preview.detail(commit_item, cb)
end)
assert_eq("the commit's files", #res.detail.files, 2)
assert_eq("not truncated", res.detail.truncated, false)
local cached = wait_for(function(cb)
	commit_preview.detail(commit_item, cb)
end)
assert_eq("a second look comes from the cache", gl.count(CDIFF), 1)
assert_eq("same answer", #cached.detail.files, 2)

local commit_files = require("beast.libs.finder.source.gh_commit_files")
items = run(commit_files, { ctx = { commit = commit_item }, cwd = "/proj" })
assert_eq("commit files rows", #items, 2)
assert_eq("each row is a file of the commit", items[1].file, "c1.lua")
commit_preview.reset()
gl.script[CDIFF] = gl.http_error(404, "404 Not Found")
items = run(commit_files, { ctx = { commit = commit_item }, cwd = "/proj" })
assert_eq("failure heading names GitLab", items[1].text, "GitLab could not list the files:")
gl.restore()

-- ---------------------------------------------------------------------------
io.write("\n--- issue grep on GitLab issues ---\n")
local issue = api.normalize("issue", gl.issue(207, "Webhook signature", { description = "Steps\nretry fails" }), "gitlab.com")
local grep = require("beast.libs.finder.source.gh_issue_grep")
items = run(grep, { pattern = "retry", ctx = { issues = { issue } } })
assert_eq("one hit", #items, 1)
-- line 1 is the title, so the description's second line is line 3
assert_eq("row text uses the issue's own reference", items[1].text, "#207:3: retry fails")
local gl_header = require("beast.libs.finder.format").gh_issue_grep_header(items[1])
assert_eq("header shows the reference", vim.trim(gl_header[2].text), "#207")

-- ---------------------------------------------------------------------------
io.write("\n--- edges ---\n")
local edges = {}
for _, edge in ipairs(require("beast.libs.finder.chains")) do
	edges[edge.id] = edge
end
assert_eq("mr -> files, default key", edges["gl_mr|gh_pr_files"] and edges["gl_mr|gh_pr_files"].key, "<C-g>")
assert_eq("mr -> commits", edges["gl_mr|gh_commits"] and edges["gl_mr|gh_commits"].key, "<C-t>")
assert_eq("issue -> grep", edges["gl_issue|gh_issue_grep"] and edges["gl_issue|gh_issue_grep"].key, "<C-g>")
assert_eq("crumb", edges["gl_mr|gh_pr_files"].crumb, "Merge Requests")
assert_eq("hint names the merge request's reference", edges["gl_mr|gh_pr_files"].hint({ selected = mr, total = 1 }), "files changed in !6")
assert_eq("commits hint", edges["gl_mr|gh_commits"].hint({ selected = mr, total = 1 }), "commits in !6")
assert_eq("the GitHub edges are still there", edges["gh_pr|gh_pr_files"] ~= nil and edges["gh_issue|gh_issue_grep"] ~= nil, true)
local opened = edges["gl_mr|gh_commits"].open({ selected = mr, total = 1 })
assert_eq("opening carries the merge request", opened.ctx.pr.ref, "!6")
assert_eq("and its title", opened.title, "MR Retry failed webhooks with backoff › Commits")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
