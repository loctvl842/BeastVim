-- =========================================================================
-- Test: pull requests -> files changed -> grep in the local copies (three levels)
-- (docs/dev-specs/finder-continuous.md, Phase 5)
--
-- Run as: nvim --clean --headless -l tests/test-finder-chain-pr-grep.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/src", "p")
vim.fn.writefile({ "needle here" }, dir .. "/src/here.lua")
vim.fn.writefile({ "needle again" }, dir .. "/src/also.lua")
vim.fn.writefile({ "needle but not in the pull request" }, dir .. "/src/other.lua")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({ total_count = 1, items = { gh.pr(5, "Touch things") } }))
local files = {
	{ filename = "src/here.lua", status = "modified", additions = 1, deletions = 0, patch = "@@ -1 +1 @@\n+x" },
	{ filename = "src/also.lua", status = "added", additions = 1, deletions = 0, patch = "@@ -0,0 +1 @@\n+x" },
	{ filename = "src/gone.lua", status = "removed", additions = 0, deletions = 1, patch = "@@ -1 +0,0 @@\n-x" },
	{ filename = "src/missing.lua", status = "modified", additions = 1, deletions = 0, patch = "@@ -1 +1 @@\n+x" },
}
local page1 = "gh api -X GET repos/o/n/pulls/5/files --hostname github.com -f per_page=100 -f page=1"
gh.script[page1] = gh.ok(vim.json.encode(files))

H.open("gh_pr", { cwd = dir })
H.settle(400)
H.press("<C-g>")
H.settle(400)
t.eq("level 2: all four changed files", H.title(), "PR Touch things › Files Changed (4)")
t.ok("hint offers the local grep", H.hint():find("<C-g> grep your local copies", 1, true) ~= nil, H.hint())

H.press("<C-g>")
H.settle(300)
t.eq("level 3: removed and missing files are dropped", H.title(), "2 PR Files › Live Grep")
t.ok("placeholder says local copies", H.has_row("your local copies of the 2 files"), vim.inspect(H.rows()))
t.ok("hint goes back to the files changed", H.hint():find("<BS> back to Files Changed", 1, true) ~= nil, H.hint())
H.type("needle", 600)
t.ok("here.lua found", H.has_row("here.lua"), vim.inspect(H.rows()))
t.ok("also.lua found", H.has_row("also.lua"), vim.inspect(H.rows()))
t.ok("other.lua is not part of the pull request", not H.has_row("other.lua"), vim.inspect(H.rows()))

H.type("")
H.press("<BS>")
H.settle(300)
t.eq("back to level 2", H.title(), "PR Touch things › Files Changed (4)")
t.eq("level 2 count is still there", H.count(), "4")
H.press("<BS>")
H.settle(300)
t.eq("back to level 1", H.title():match("^Pull Requests") ~= nil, true)
t.eq("no gh call was repeated", { gh.count("gh api -X GET search/issues"), gh.count(page1) }, { 1, 1 })

-- None of the files exist locally
gh.script[page1] = gh.ok(vim.json.encode({ files[3], files[4] }))
H.close()
H.open("gh_pr", { cwd = dir })
H.settle(400)
H.press("<C-g>")
H.settle(400)
H.press("<C-g>")
H.settle(200)
t.eq(
	"none exist: a message, the level stays",
	{ toasts[#toasts], H.title():match("^PR Touch") ~= nil },
	{ "None of these files exist in your working tree", true }
)
H.close()

gh.restore()
vim.fn.delete(dir, "rf")
t.done()
