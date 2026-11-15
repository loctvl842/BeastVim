-- =========================================================================
-- Test: pull requests -> commits -> grep in the files of a commit (three levels, gh scripted)
-- (docs/dev-specs/finder-pr-commits.md, Phase 3)
--
-- Run as: nvim --clean --headless -l tests/test-finder-chain-commit-grep.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/lib", "p")
vim.fn.writefile({ "needle one" }, dir .. "/lib/c1.lua")
vim.fn.writefile({ "needle two" }, dir .. "/lib/c2.lua")
vim.fn.writefile({ "needle but not in the commit" }, dir .. "/lib/other.lua")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({ total_count = 1, items = { gh.pr(1, "Touch things") } }))
local commits = gh.commits(4)
gh.script["gh api -X GET repos/o/n/pulls/1/commits --hostname github.com -f per_page=100 -f page=1"] = gh.ok(vim.json.encode(commits))
local function commit_url(i)
	return "gh api -X GET repos/o/n/commits/" .. commits[i].sha
end
local removed = gh.files(1, "lib/gone")
removed[1].status = "removed"
local c1 = gh.files(2, "lib/c")
c1[3] = removed[1]
gh.script[commit_url(1)] = gh.ok(vim.json.encode({ commit = { message = "m" }, files = c1 }))
gh.script[commit_url(2)] = gh.ok(vim.json.encode({ commit = { message = "m" }, files = gh.files(1, "lib/missing") }))
gh.script[commit_url(3)] = gh.ok(vim.json.encode({ commit = { message = "merge" } }))
gh.script[commit_url(4)] = gh.fail("gh: Not Found (HTTP 404)")

local function to_commits()
	H.open("gh_pr", { cwd = dir })
	H.settle(400)
	H.press("<C-t>")
	H.settle(400)
end

t.section("happy path")
to_commits()
t.eq("level 2", H.title(), "PR Touch things › Commits (4)")
t.ok(
	"hint offers the grep and the way back",
	H.hint():find("<C-f> grep its files", 1, true) ~= nil and H.hint():find("<BS> back to Pull Requests", 1, true) ~= nil,
	H.hint()
)
H.press("<C-f>")
H.settle(300)
t.eq("level 3: removed files are dropped", H.title(), "2 Files in 0000001 › Live Grep")
t.ok("placeholder names the commit", H.has_row("local copies of the 2 files changed by 0000001"), vim.inspect(H.rows()))
t.ok("hint goes back to the commits", H.hint():find("<BS> back to Commits", 1, true) ~= nil, H.hint())
H.type("needle", 600)
t.ok("both files of the commit are searched", H.has_row("c1.lua") and H.has_row("c2.lua"), vim.inspect(H.rows()))
t.ok("other files are not", not H.has_row("other.lua"), vim.inspect(H.rows()))
H.type("")
H.press("<BS>")
H.settle(300)
t.eq("back to the commits", H.title(), "PR Touch things › Commits (4)")
H.settle(300)
local function preview_text()
	return table.concat(vim.api.nvim_buf_get_lines(H.panes().preview.buf, 0, -1, false), "\n")
end
t.ok("the commit's diff is in the preview again", preview_text():find("+new 1", 1, true) ~= nil, preview_text())
H.press("<BS>")
H.settle(300)
t.ok("back to the pull requests", H.has_row("Touch things"), vim.inspect(H.rows()))
H.settle(300)
t.ok("the pull request preview is not the diff of the commit", preview_text():find("+new 1", 1, true) == nil, preview_text())
H.press("<C-t>")
H.settle(400)
t.ok("entering the commits again shows the diff", preview_text():find("+new 1", 1, true) ~= nil, preview_text())
H.close()

t.section("refusals")
to_commits()
H.press("<C-j>")
H.settle(300)
H.press("<C-f>")
H.settle(300)
t.eq(
	"none of the files exist: a message, the level stays",
	{ toasts[#toasts], H.title() },
	{ "None of these files exist in your working tree", "PR Touch things › Commits (4)" }
)
H.press("<C-j>")
H.settle(300)
H.press("<C-f>")
H.settle(300)
t.eq("a commit without files", { toasts[#toasts], H.title():match("^PR") ~= nil }, { "Nothing to open from here", true })
H.press("<C-j>")
H.settle(300)
H.press("<C-f>")
H.settle(300)
t.ok("an error of GitHub is shown", toasts[#toasts]:find("Not Found", 1, true) ~= nil, toasts[#toasts])
H.close()

t.section("waiting for the commit")
require("beast.libs.finder.source.gh.commit_preview").reset()
gh.hold = { "gh api -X GET repos/o/n/commits/" }
to_commits()
H.press("<C-f>")
H.settle(100)
H.press("<C-f>")
t.eq("a second press says it is loading", toasts[#toasts], "Still loading - try again in a moment")
t.eq("still on the commits", H.title(), "PR Touch things › Commits (4)")
gh.release()
H.settle(300)
t.eq("the answer opens the grep", H.title(), "2 Files in 0000001 › Live Grep")
H.close()

require("beast.libs.finder.source.gh.commit_preview").reset()
to_commits()
H.press("<C-f>")
H.settle(100)
H.press("<C-j>")
H.settle(100)
gh.release()
H.settle(300)
t.eq("moving while waiting: the answer opens nothing", H.title(), "PR Touch things › Commits (4)")
H.close()

require("beast.libs.finder.source.gh.commit_preview").reset()
to_commits()
H.press("<C-f>")
H.settle(100)
H.press("<BS>")
H.settle(200)
t.ok("back while waiting: the pull request list", H.has_row("Touch things"), vim.inspect(H.rows()))
gh.release()
H.settle(300)
t.ok("the late answer opens nothing", H.has_row("Touch things") and H.title():match("^Pull Requests") ~= nil, H.title())
H.close()

require("beast.libs.finder.source.gh.commit_preview").reset()
to_commits()
H.press("<C-f>")
H.settle(100)
H.close()
gh.release()
H.settle(300)
t.eq("closing while waiting: no picker comes back", H.window_count(), 0)
gh.hold = {}

t.section("remapped key")
H.finder().setup({ chains = { edges = { ["gh_commits|live_grep"] = { key = "<C-x>" } } } })
to_commits()
t.ok("hint shows the key", H.hint():find("<C-x> grep its files", 1, true) ~= nil, H.hint())
H.press("<C-x>")
H.settle(300)
t.eq("it follows the edge", H.title(), "2 Files in 0000001 › Live Grep")
H.close()
H.finder().setup({})

gh.restore()
vim.fn.delete(dir, "rf")
t.done()
