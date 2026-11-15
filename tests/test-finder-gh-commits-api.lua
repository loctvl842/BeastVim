-- =========================================================================
-- Test: commits of a pull request and one commit with its files (gh api, paging, errors)
-- (docs/dev-specs/finder-pr-commits.md, Phase 2)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-commits-api.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()
local api = require("beast.libs.finder.source.gh.api")

local pr = { number = 7, repo = "o/n", host = "github.com" }
local function page(n)
	return ("gh api -X GET repos/o/n/pulls/7/commits --hostname github.com -f per_page=100 -f page=%d"):format(n)
end

local function wait_for(start)
	local result
	start(function(r)
		result = r
	end)
	H.wait(function()
		return result ~= nil
	end, 1000)
	return result
end

gh.install()

gh.script[page(1)] = gh.ok(vim.json.encode(gh.commits(3)))
local r = wait_for(function(cb)
	api.commits(pr, cb)
end)
t.eq("three commits, one call", { #r.commits, gh.count("gh api") }, { 3, 1 })
t.eq("short id and subject", { #r.commits[1].short, r.commits[1].subject }, { 7, "Commit 1 subject" })
t.eq(
	"author is the login, the full message is kept",
	{ r.commits[2].author, r.commits[2].message:find("Body of commit 2", 1, true) ~= nil },
	{ "dev2", true }
)
t.eq("not truncated", r.truncated, nil)

gh.calls = {}
gh.script[page(1)] = gh.ok(vim.json.encode(gh.commits(100, 1)))
gh.script[page(2)] = gh.ok(vim.json.encode(gh.commits(100, 101)))
gh.script[page(3)] = gh.ok(vim.json.encode(gh.commits(50, 201)))
r = wait_for(function(cb)
	api.commits(pr, cb)
end)
t.eq("a short third page ends the listing", { #r.commits, r.truncated, gh.count("gh api") }, { 250, nil, 3 })

gh.calls = {}
gh.script[page(3)] = gh.ok(vim.json.encode(gh.commits(100, 201)))
gh.script[page(4)] = gh.ok(vim.json.encode(gh.commits(1, 301)))
r = wait_for(function(cb)
	api.commits(pr, cb)
end)
t.eq("more than three full pages is truncated", { #r.commits, r.truncated }, { 300, true })

gh.script[page(1)] = gh.fail("gh: Not Found (HTTP 404)")
r = wait_for(function(cb)
	api.commits(pr, cb)
end)
t.ok("an error comes back as an error", r.commits == nil and r.error ~= nil and r.error.message:find("Not Found", 1, true) ~= nil)

-- One commit
local sha = "abc1234def"
local url = "gh api -X GET repos/o/n/commits/" .. sha
gh.script[url] = gh.ok(vim.json.encode({
	commit = { message = "Subject\n\nBody" },
	files = gh.files(2),
}))
r = wait_for(function(cb)
	api.commit(pr, sha, cb)
end)
t.eq("commit message and files", { r.detail.message, #r.detail.files, r.detail.truncated }, { "Subject\n\nBody", 2, false })
t.eq("a file keeps its patch", r.detail.files[1].patch ~= nil, true)

gh.script[url] = gh.ok(vim.json.encode({ commit = { message = "Merge" } }))
r = wait_for(function(cb)
	api.commit(pr, sha, cb)
end)
t.eq("a commit without files has an empty list", #r.detail.files, 0)

gh.script[url] = gh.fail("gh: Not Found (HTTP 404)")
r = wait_for(function(cb)
	api.commit(pr, sha, cb)
end)
t.ok("commit error", r.detail == nil and r.error ~= nil)

gh.restore()
t.done()
