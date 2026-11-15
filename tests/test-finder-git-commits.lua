-- =========================================================================
-- Test: local commits -> files changed -> grep (the chain through the real picker, over a real git repo)
--
-- Run as: nvim --clean --headless -l tests/test-finder-git-commits.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()
local log = require("beast.libs.finder.source.git.log")

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/lib", "p")
local function git(...)
	local res = vim.system({ "git", "-C", dir, "-c", "user.name=Zed", "-c", "user.email=z@e.x", ... }, { text = true }):wait()
	assert(res.code == 0, res.stderr)
end
local function write(path, lines)
	vim.fn.writefile(lines, dir .. "/" .. path)
end
git("init", "-q")
write("lib/a.lua", { "alpha one", "needle here" })
write("lib/b.lua", { "beta" })
git("add", ".")
git("commit", "-q", "-m", "First commit")
write("lib/a.lua", { "alpha two", "needle here", "extra" })
git("mv", "lib/b.lua", "lib/c.lua")
write("lib/d.lua", { "delta needle" })
git("add", ".")
git("commit", "-q", "-m", "Second commit\n\nBody of the second")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

t.section("parsing")
local commits
log.commits(dir, function(result)
	commits = result.commits
end)
H.wait(function()
	return commits ~= nil
end)
t.eq("newest first", { commits[1].subject, commits[2].subject }, { "Second commit", "First commit" })
t.eq("message keeps the body", commits[1].message, "Second commit\n\nBody of the second")
local detail
log.show(dir, commits[1].sha, function(result)
	detail = result.detail
end)
H.wait(function()
	return detail ~= nil
end)
local by = {}
for _, file in ipairs(detail.files) do
	by[file.path] = file
end
t.eq("three files", #detail.files, 3)
t.eq("modified", { by["lib/a.lua"].status, by["lib/a.lua"].additions, by["lib/a.lua"].deletions }, { "modified", 2, 1 })
t.eq("renamed keeps the old path", { by["lib/c.lua"].status, by["lib/c.lua"].previous }, { "renamed", "lib/b.lua" })
t.eq("added", by["lib/d.lua"].status, "added")
t.ok("the patch starts at the first hunk", by["lib/a.lua"].patch:sub(1, 2) == "@@", tostring(by["lib/a.lua"].patch))
t.ok("a pure rename has no hunk", by["lib/c.lua"].patch == nil)

t.section("the chain")
H.open("git_commits", { cwd = dir })
H.settle(300)
t.eq("title", H.title(), "Commits (2)")
local rows = H.rows()
t.ok("latest first", rows[1]:find("Second commit", 1, true) ~= nil and rows[2]:find("First commit", 1, true) ~= nil, vim.inspect(rows))
t.ok("hint", H.hint():find("<C-g> files changed", 1, true) ~= nil, H.hint())
local preview = H.panes().preview
H.settle(300)
t.ok(
	"the preview shows the diff",
	table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n"):find("Body of the second", 1, true) ~= nil
)

t.ok("a key of another picker's chain is muted here (<C-t> would indent the prompt)", H.press("<C-t>"))
t.eq("the prompt is untouched", H.prompt(), "")
t.eq("the list is untouched", H.title(), "Commits (2)")

H.press("<C-g>")
H.settle(400)
t.eq("full chain in the title", H.title(), ("%s Second commit › Files Changed (3)"):format(commits[1].short))
t.ok("files listed", H.has_row("a.lua") and H.has_row("c.lua") and H.has_row("d.lua"), vim.inspect(H.rows()))

H.press("<C-g>")
H.settle(400)
t.eq("grep title", H.title(), ("%s Second commit › 3 Files › Live Grep"):format(commits[1].short))
H.type("needle")
t.ok("only the commit's files are searched", H.has_row("a.lua") and H.has_row("d.lua") and not H.has_row("b.lua"), vim.inspect(H.rows()))

H.type("")
H.press("<BS>")
H.settle(200)
t.eq("back to the files", H.title(), ("%s Second commit › Files Changed (3)"):format(commits[1].short))
H.press("<BS>")
H.settle(200)
t.eq("back to the commits", H.title(), "Commits (2)")
H.close()

t.section("not a repository")
local empty = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(empty, "p")
H.open("git_commits", { cwd = empty })
H.settle(300)
t.ok("an error row", H.has_row("git could not list the commits"), vim.inspect(H.rows()))
H.close()

vim.fn.delete(dir, "rf")
vim.fn.delete(empty, "rf")
t.done()
