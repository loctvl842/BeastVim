-- =========================================================================
-- Test: pull requests -> commits (the chain through the real picker, gh scripted)
-- (docs/dev-specs/finder-pr-commits.md, Phase 2)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-commits.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({
	total_count = 2,
	items = { gh.pr(1, "Short title"), gh.pr(2, "Refactor the finder so that every picker can lead to the next one") },
}))
local commits = gh.commits(4)
commits[2].commit.message = "Scoped grep\n\nonly the files you found"
commits[2].commit.author.name = "Zed"
commits[2].author = { login = "zed" }
gh.script["gh api -X GET repos/o/n/pulls/1/commits --hostname github.com -f per_page=100 -f page=1"] = gh.ok(vim.json.encode(commits))
local sha2 = commits[2].sha
gh.script["gh api -X GET repos/o/n/commits/" .. commits[1].sha] = gh.ok(vim.json.encode({ commit = { message = "m" }, files = gh.files(2, "lib/c") }))
gh.script["gh api -X GET repos/o/n/commits/" .. sha2] = gh.ok(vim.json.encode({ commit = { message = "m" }, files = gh.files(1, "lib/z") }))

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

H.open("gh_pr")
H.settle(400)
t.ok(
	"hint offers both ways down",
	H.hint():find("<C-g> files changed in #1", 1, true) ~= nil and H.hint():find("<C-t> commits in #1", 1, true) ~= nil,
	H.hint()
)
local searches = gh.count("gh api -X GET search/issues")

H.press("<C-t>")
H.settle(400)
t.eq("title", H.title(), "PR Short title › Commits (4)")
t.eq("count", H.count(), "4")
local rows = H.rows()
t.ok(
	"oldest first, with the id and the subject",
	rows[1]:find("0000001", 1, true) ~= nil and rows[1]:find("Commit 1 subject", 1, true) ~= nil and rows[4]:find("Commit 4 subject", 1, true) ~= nil,
	vim.inspect(rows)
)
local parts = require("beast.libs.finder.format").gh_commit({ short = "abc1234", subject = "Fix", author = "zed", date = "2026-11-01T10:00:00Z" })
t.ok(
	"author and age are at the right edge of the row",
	parts[#parts].right_align and parts[#parts].text:find("zed", 1, true) ~= nil,
	vim.inspect(parts)
)
t.ok("hint goes back", H.hint():find("<BS> back to Pull Requests", 1, true) ~= nil, H.hint())

local preview = H.panes().preview
local function preview_text()
	return table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
end
t.ok(
	"preview shows the first commit's diff",
	preview_text():find("lib/c1.lua", 1, true) ~= nil and preview_text():find("+new 1", 1, true) ~= nil,
	preview_text()
)
t.eq("preview is a diff", vim.bo[preview.buf].filetype, "diff")
H.press("<C-j>")
H.settle(300)
t.ok(
	"moving shows that commit's message and diff",
	preview_text():find("only the files you found", 1, true) ~= nil and preview_text():find("lib/z1.lua", 1, true) ~= nil,
	preview_text()
)
local fetched = gh.count("gh api -X GET repos/o/n/commits/")
H.press("<C-k>")
H.settle(300)
H.press("<C-j>")
H.settle(300)
t.eq("a commit already seen is not fetched again", gh.count("gh api -X GET repos/o/n/commits/"), fetched)

H.type("scoped")
t.ok("typing filters by subject", H.has_row("Scoped grep") and not H.has_row("Commit 1 subject"), vim.inspect(H.rows()))
t.eq("count shows matches over total", H.count(), "1/4")
H.type("zed")
t.ok("and by author", H.has_row("Scoped grep"), vim.inspect(H.rows()))
H.type(string.sub(sha2, 1, 7))
t.ok("and by id", H.has_row("Scoped grep") and not H.has_row("Commit 3 subject"), vim.inspect(H.rows()))

H.type("")
H.press("<BS>")
H.settle(300)
t.ok("back to the pull requests", H.has_row("Short title"), vim.inspect(H.rows()))
t.eq("no new search", gh.count("gh api -X GET search/issues"), searches)

-- Enter opens the whole commit
H.press("<C-t>")
H.settle(400)
H.press("<CR>")
H.settle(400)
local buf = vim.api.nvim_get_current_buf()
t.eq("Enter closes the picker", H.window_count(), 0)
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
t.ok("the commit buffer has the message and the diff", text:find("Commit 1 subject", 1, true) ~= nil and text:find("+new 1", 1, true) ~= nil, text)
t.eq("it is a read-only diff", { vim.bo[buf].filetype, vim.bo[buf].modifiable }, { "diff", false })
t.ok("named after the commit", vim.api.nvim_buf_get_name(buf):find("o/n@0000001", 1, true) ~= nil, vim.api.nvim_buf_get_name(buf))

-- Errors and a cut list
gh.script["gh api -X GET repos/o/n/pulls/2/commits --hostname github.com -f per_page=100 -f page=1"] = gh.fail("gh: Not Found (HTTP 404)")
H.open("gh_pr")
H.settle(400)
H.press("<C-j>")
H.settle(200)
H.press("<C-t>")
H.settle(400)
t.ok("an error is a message row", H.has_row("GitHub could not list the commits"), vim.inspect(H.rows()))
H.press("<C-t>")
H.close()

local many = "gh api -X GET repos/o/n/pulls/2/commits --hostname github.com -f per_page=100 -f page="
gh.script[many .. "1"] = gh.ok(vim.json.encode(gh.commits(100, 1)))
gh.script[many .. "2"] = gh.ok(vim.json.encode(gh.commits(100, 101)))
gh.script[many .. "3"] = gh.ok(vim.json.encode(gh.commits(100, 201)))
gh.script[many .. "4"] = gh.ok(vim.json.encode(gh.commits(1, 301)))
H.open("gh_pr")
H.settle(400)
H.press("<C-j>")
H.settle(200)
H.press("<C-t>")
H.settle(800)
t.eq("a pull request with more commits is cut and says so", H.title():match("%(300, partial%)$") ~= nil, true)
H.close()

gh.restore()
t.done()
