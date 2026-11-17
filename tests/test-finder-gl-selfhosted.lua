-- =========================================================================
-- Test: GitLab sources against a self-hosted server (replayed responses)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 5: responses recorded from gitlab.com
-- (tests/fixtures/gitlab) are replayed as if a server at git.acme.dev answered, with a nested project
-- path: every request must carry that host and the encoded path, the unknown-host toast must go away
-- once the host is mapped, and a server that lacks fields or answers with a gateway page must not
-- break the pickers. vim.system is scripted; nothing runs `glab`.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gl-selfhosted.lua
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
local api = require("beast.libs.finder.source.gl.api")
local git_config = require("beast.libs.git.config")

local HOST = "git.acme.dev"
local PROJECT = "platform/payments/api"
local ENC = "platform%2Fpayments%2Fapi"
local REMOTE = "git@git.acme.dev:platform/payments/api.git"

--- A recorded response, moved to the fake server and the nested project.
---@param name string fixture file
---@return table
local function fixture(name)
	local f = assert(io.open("tests/fixtures/gitlab/" .. name .. ".json"))
	local text = f:read("*a")
	f:close()
	text = text:gsub("loctvl842/glab%-finder%-test", PROJECT):gsub("https://gitlab%.com", "https://" .. HOST)
	return vim.json.decode(text)
end

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

local function req(path)
	return gl.req(HOST, "projects/" .. ENC .. "/" .. path)
end

-- ---------------------------------------------------------------------------
io.write("\n--- an unknown host is explained, then works once mapped ---\n")
gl.install(REMOTE)
local mr_source = require("beast.libs.finder.source.gl").create("mr")
assert_eq("keys are not offered", Git.has_provider("gitlab", "/proj"), false)
assert_eq("opening fails", mr_source.check(), false)
assert_eq(
	"toast names the host and the setting",
	toasts[1].msg,
	"git.acme.dev is not known as a GitLab server. Add it to the git remote hosts setting."
)

git_config.setup({ remote = { hosts = { [HOST] = "gitlab" } } })
require("beast.libs.git.remote").invalidate()
assert_eq("keys are offered after mapping", Git.has_provider("gitlab", "/proj"), true)
assert_eq("opening works after mapping", mr_source.check(), true)
assert_eq("the login check goes to the mapped host", gl.calls[#gl.calls], "glab auth status --hostname " .. HOST)
assert_eq("title names host and nested path", mr_source.title(), "Merge Requests - git.acme.dev/platform/payments/api")

-- ---------------------------------------------------------------------------
io.write("\n--- list, detail, files, commits on the fake server ---\n")
gl.script[req("merge_requests")] = gl.http(fixture("mr_list"), { ["X-Total"] = "6" })
local items = run(mr_source, { pattern = "state:all" })
assert_eq("every merge request of the fixture", #items, 6)
assert_eq(
	"states survive the replay",
	vim.tbl_map(function(i)
		return i.state
	end, items),
	{ "open", "open", "closed", "merged", "open", "draft" }
)
local mr6 = items[1]
assert_eq("the project path is the nested one", mr6.repo, PROJECT)
assert_eq("the url points at the fake server", mr6.url, "https://git.acme.dev/" .. PROJECT .. "/-/merge_requests/6")
assert_eq("host", mr6.host, HOST)
assert_test(
	"every request so far went to the fake host with the encoded path",
	(function()
		for _, line in ipairs(gl.calls) do
			if line:sub(1, 8) == "glab api" and not line:find("--hostname " .. HOST .. " --include projects/" .. ENC, 1, true) then
				return false
			end
		end
		return true
	end)()
)

gl.script[req("merge_requests/6")] = gl.http(fixture("mr_6"))
gl.script[req("merge_requests/6/notes")] = gl.http(fixture("mr_6_notes"))
local res = wait_for(function(cb)
	api.detail(mr6, cb)
end)
assert_eq("detail files", res.detail.files, 5)
assert_eq("detail branches", { res.detail.base, res.detail.head }, { "main", "retry-backoff" })
assert_eq("detail conversation has the human note only", #res.detail.conversation, 1)

gl.script[req("merge_requests/6/diffs")] = gl.http(fixture("mr_6_diffs"))
local files = run(require("beast.libs.finder.source.gh_pr_files"), { ctx = { pr = mr6 }, cwd = "/proj" })
assert_eq("files of the merge request", #files, 5)

gl.script[req("merge_requests/6/commits")] = gl.http(fixture("mr_6_commits"))
local commits = run(require("beast.libs.finder.source.gh_commits"), { ctx = { pr = mr6 }, cwd = "/proj" })
assert_eq("commits newest first", #commits, 3)
assert_eq("commit url on the fake server", commits[1].url, "https://git.acme.dev/" .. PROJECT .. "/-/commit/" .. commits[1].sha)

gl.script[req("repository/commits/" .. commits[1].sha .. "/diff")] = gl.http(fixture("commit_diff"))
require("beast.libs.finder.source.gh.commit_preview").reset()
local commit_files = run(require("beast.libs.finder.source.gh_commit_files"), { ctx = { commit = commits[1] }, cwd = "/proj" })
-- the newest commit changes settings, adds NOTES.md and removes README.md
assert_eq("files of a commit", #commit_files, 3)

gl.script[req("issues")] = gl.http(fixture("issue_list"))
local issue_source = require("beast.libs.finder.source.gl").create("issue")
issue_source.check()
local issues = run(issue_source, { pattern = "state:all" })
assert_eq("issues of the fixture", #issues, 4)
assert_eq("issue reference", issues[1].ref, "#4")

-- ---------------------------------------------------------------------------
io.write("\n--- an older server that leaves fields out ---\n")
local old = fixture("mr_6")
for _, key in ipairs({ "head_pipeline", "detailed_merge_status", "reviewers", "changes_count", "milestone", "assignees", "has_conflicts" }) do
	old[key] = nil
end
gl.script[req("merge_requests/6")] = gl.http(old)
res = wait_for(function(cb)
	api.detail(mr6, cb)
end)
assert_test("detail still answers", res.detail ~= nil, vim.inspect(res))
assert_eq("no files count means zero", res.detail.files, 0)
assert_eq("no pipeline", res.detail.pipeline, nil)
assert_eq("no merge verdict", res.detail.mergeable, nil)
local lines = require("beast.libs.finder.source.gh.preview").build(mr6, res.detail)
assert_test("the preview draws without the missing lines", table.concat(lines, "\n"):find("Pipeline:", 1, true) == nil)

-- ---------------------------------------------------------------------------
io.write("\n--- a gateway page instead of the API ---\n")
gl.script[req("merge_requests")] = gl.ok("<html><body>502 Bad Gateway</body></html>")
items = run(mr_source, { pattern = "state:opened" })
assert_eq("heading", items[1].text, "GitLab could not run this search:")
assert_eq("reason", items[2].text, "unexpected response from GitLab")

gl.script[req("merge_requests")] =
	{ code = 1, stdout = "", stderr = 'ERROR Get "https://git.acme.dev/api/v4/projects": x509: certificate signed by unknown authority' }
items = run(mr_source, { pattern = "state:opened" })
assert_test("a certificate problem shows glab's own line", items[2].text:find("x509", 1, true) ~= nil, items[2].text)

gl.restore()
git_config.setup({ remote = { hosts = {} } })
require("beast.libs.git.remote").invalidate()

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
