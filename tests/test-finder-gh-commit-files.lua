-- =========================================================================
-- Test: pull requests -> commits -> files changed by a commit -> grep in them
-- (the chain through the real picker, gh scripted)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-commit-files.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/lib", "p")
vim.fn.writefile({ "needle one" }, dir .. "/lib/c1.lua")
vim.fn.writefile({ "needle other" }, dir .. "/lib/other.lua")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({ total_count = 1, items = { gh.pr(1, "Touch things") } }))
local commits = gh.commits(3)
gh.script["gh api -X GET repos/o/n/pulls/1/commits --hostname github.com -f per_page=100 -f page=1"] = gh.ok(vim.json.encode(gh.reversed(commits)))
local files = gh.files(2, "lib/c") -- c1 exists, c2 does not
gh.script["gh api -X GET repos/o/n/commits/" .. commits[1].sha] = gh.ok(vim.json.encode({ commit = { message = "m" }, files = files }))
gh.script["gh api -X GET repos/o/n/commits/" .. commits[2].sha] = gh.ok(vim.json.encode({ commit = { message = "merge" } }))
gh.script["gh api -X GET repos/o/n/commits/" .. commits[3].sha] = gh.fail("gh: Not Found (HTTP 404)")

local function preview_text()
	return table.concat(vim.api.nvim_buf_get_lines(H.panes().preview.buf, 0, -1, false), "\n")
end

H.open("gh_pr", { cwd = dir })
H.settle(400)
H.press("<C-t>")
H.settle(400)
t.ok(
	"the commits offer files changed and the grep",
	H.hint():find("<C-g> files changed", 1, true) ~= nil and H.hint():find("<C-f> grep", 1, true) ~= nil,
	H.hint()
)

H.press("<C-g>")
H.settle(400)
t.eq("title", H.title(), "Commit 0000001 › Files Changed (2)")
t.eq("only paths are listed", { H.has_row("c1.lua"), H.has_row("c2.lua") }, { true, true })
t.eq("count", H.count(), "2")
t.ok("preview shows the diff of the first file", preview_text():find("+new 1", 1, true) ~= nil, preview_text())
H.press("<C-j>")
H.settle(300)
t.ok("moving shows the next diff", preview_text():find("+new 2", 1, true) ~= nil, preview_text())
t.ok(
	"hint offers the grep and the way back",
	H.hint():find("<C-g> grep your local copies", 1, true) ~= nil and H.hint():find("<BS> back to Commits", 1, true) ~= nil,
	H.hint()
)

H.type("c2")
t.ok("typing filters by path", H.has_row("c2.lua") and not H.has_row("c1.lua"), vim.inspect(H.rows()))
t.eq("count shows matches over total", H.count(), "1/2")
H.type("")

H.press("<C-g>")
H.settle(300)
t.eq("grep in the local copies only", H.title(), "1 Files in 0000001 › Live Grep")
t.ok("placeholder names the commit", H.has_row("changed by 0000001"), vim.inspect(H.rows()))
H.type("needle", 600)
t.ok("the file of the commit is searched, others are not", H.has_row("c1.lua") and not H.has_row("other.lua"), vim.inspect(H.rows()))
H.type("")
H.press("<BS>")
H.settle(300)
t.eq("back to the files of the commit", H.title(), "Commit 0000001 › Files Changed (2)")
t.ok("with its diff in the preview", preview_text():find("+new", 1, true) ~= nil, preview_text())
H.press("<BS>")
H.settle(300)
t.eq("back to the commits", H.title(), "PR Touch things › Commits (3)")

-- Enter on a file shows the commit's diff of it
H.press("<C-g>")
H.settle(400)
H.press("<CR>")
H.settle(300)
local buf = vim.api.nvim_get_current_buf()
t.eq("Enter closes the picker", H.window_count(), 0)
t.ok(
	"diff buffer named after the commit and the file",
	vim.api.nvim_buf_get_name(buf):find("o/n@0000001: lib/c1.lua", 1, true) ~= nil,
	vim.api.nvim_buf_get_name(buf)
)
t.eq("read-only diff", { vim.bo[buf].filetype, vim.bo[buf].modifiable }, { "diff", false })

-- a commit without files and an error
H.open("gh_pr", { cwd = dir })
H.settle(400)
H.press("<C-t>")
H.settle(400)
H.press("<C-j>")
H.settle(300)
H.press("<C-g>")
H.settle(400)
t.ok("a commit without files says so", H.has_row("No files changed"), vim.inspect(H.rows()))
H.press("<C-g>")
t.eq("no chain from a message row", toasts[#toasts], "Nothing to open from here")
H.press("<BS>")
H.settle(300)
H.press("<C-j>")
H.settle(300)
H.press("<C-g>")
H.settle(400)
t.ok("an error is a message row", H.has_row("GitHub could not list the files"), vim.inspect(H.rows()))
H.close()

gh.restore()
vim.fn.delete(dir, "rf")
t.done()
