-- =========================================================================
-- Test: local branches -> files changed / commits -> grep (the git reads and the chain through the real
-- picker, over a real git repo)
--
-- Run as: nvim --clean --headless -l tests/test-finder-git-branches.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()
local log = require("beast.libs.finder.source.git.log")

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/lib", "p")
local tick = 0
--- Run git in the repo; every call is one second later so the commit dates (and the branch order) are stable.
local function git(...)
	tick = tick + 1
	local date = ("2026-01-01T00:00:%02d"):format(tick)
	local res = vim
		.system(
			{ "git", "-C", dir, "-c", "user.name=Zed", "-c", "user.email=z@e.x", ... },
			{ text = true, env = { GIT_COMMITTER_DATE = date, GIT_AUTHOR_DATE = date } }
		)
		:wait()
	assert(res.code == 0, res.stderr)
end
local function write(path, lines)
	vim.fn.writefile(lines, dir .. "/" .. path)
end
git("init", "-q", "-b", "main")
write("lib/a.lua", { "alpha one", "needle here" })
write("lib/b.lua", { "beta needle" })
git("add", ".")
git("commit", "-q", "-m", "First on main")
write("lib/a.lua", { "alpha two", "needle here" })
git("add", ".")
git("commit", "-q", "-m", "Second on main")
git("branch", "old")
git("checkout", "-q", "-b", "feat/x")
write("lib/a.lua", { "alpha three", "needle here", "extra" })
write("lib/new.lua", { "new needle" })
git("add", ".")
git("commit", "-q", "-m", "Add new, change a")
git("rm", "-q", "lib/b.lua")
write("lib/new.lua", { "new needle", "more" })
git("add", ".")
git("commit", "-q", "-m", "Drop b, grow new")
git("checkout", "-q", "main")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

--- Wait for a callback-style git read and return its first argument.
local function read(fn, ...)
	local out
	local args = { ... }
	local n = select("#", ...)
	args[n + 1] = function(result)
		out = result
	end
	fn(unpack(args, 1, n + 1))
	H.wait(function()
		return out ~= nil
	end)
	return out
end

local function commits(rev)
	return read(function(cb)
		log.commits(dir, cb, rev)
	end)
end

t.section("branches")
local branches = read(log.branches, dir).branches
local names = vim.tbl_map(function(b)
	return b.name
end, branches)
t.eq("the current branch first, then the newest", names, { "main", "feat/x", "old" })
t.eq("current is marked", { branches[1].current, branches[2].current }, { true, false })
t.eq("the latest commit of the branch", branches[2].subject, "Drop b, grow new")
t.eq("short id", branches[2].short, branches[2].sha:sub(1, 7))
t.eq("default is main", log.default_name(branches), "main")
t.eq("master when there is no main", log.default_name({ { name = "master" }, { name = "x" } }), "master")
t.eq("nil when there is neither", log.default_name({ { name = "x" } }), nil)
t.ok("not a repository is an error", read(log.branches, vim.fn.resolve(vim.fn.tempname())).error ~= nil)

t.section("base")
local feat, old = branches[2], branches[3]
local main_sha = branches[1].sha
t.eq(
	"a branch with commits of its own starts at the default's tip",
	read(function(cb)
		log.base(dir, feat, "main", function(base)
			cb({ base = base })
		end)
	end).base,
	main_sha
)
t.eq(
	"the default branch has no base",
	read(function(cb)
		log.base(dir, branches[1], "main", function(base)
			cb({ base = base or false })
		end)
	end).base,
	false
)
t.eq(
	"a branch on the default's tip has no base",
	read(function(cb)
		log.base(dir, old, "main", function(base)
			cb({ base = base or false })
		end)
	end).base,
	false
)
t.eq(
	"no default branch, no base",
	read(function(cb)
		log.base(dir, feat, nil, function(base)
			cb({ base = base or false })
		end)
	end).base,
	false
)

t.section("commits of a range")
local range = commits("refs/heads/main..refs/heads/feat/x")
t.eq(
	"only the commits the branch added, newest first",
	vim.tbl_map(function(c)
		return c.subject
	end, range.commits),
	{ "Drop b, grow new", "Add new, change a" }
)
t.eq("no revision walks HEAD", #commits().commits, 2)
t.eq("a whole branch", #commits("refs/heads/feat/x").commits, 4)

t.section("diff")
local diff = read(log.diff, dir, main_sha, feat.sha).detail
local by = {}
for _, file in ipairs(diff.files) do
	by[file.path] = file
end
t.eq("one row per file the branch changed", vim.tbl_count(by), 3)
t.eq("modified", by["lib/a.lua"].status, "modified")
t.eq("added", by["lib/new.lua"].status, "added")
t.eq("removed", by["lib/b.lua"].status, "removed")
t.ok("the patch starts at the first hunk", by["lib/a.lua"].patch:sub(1, 2) == "@@", tostring(by["lib/a.lua"].patch))
t.eq("not truncated", diff.truncated, false)
t.ok("a bad revision is an error", read(log.diff, dir, "nope", feat.sha).error ~= nil)

t.section("the picker")
local function head()
	return vim.trim(vim.system({ "git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait().stdout)
end
H.open("git_branches", { cwd = dir })
H.settle(300)
t.eq("title", H.title(), "Git Branches (3)")
local rows = H.rows()
t.ok("the branch you are on first, marked", rows[1]:find("●", 1, true) and rows[1]:find("main", 1, true), vim.inspect(rows))
t.ok("then the newest", rows[2]:find("feat/x", 1, true) and rows[2]:find("Drop b, grow new", 1, true), vim.inspect(rows))
t.ok("the others are not marked", not rows[2]:find("●", 1, true))

H.type("Drop")
H.settle(200)
t.ok("typing filters by the latest commit: only the matching branch", H.has_row("feat/x") and not H.has_row("old"), vim.inspect(H.rows()))
H.type("")
H.settle(200)

H.press("<C-j>")
H.settle(500)
local preview = H.panes().preview
local text = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
t.ok("the preview counts the commits over main", text:find("2 commits ahead of main", 1, true) ~= nil, text)
t.ok("and lists them", text:find("Add new, change a", 1, true) ~= nil and text:find("Drop b, grow new", 1, true) ~= nil, text)
H.press("<C-j>")
H.settle(500)
text = table.concat(vim.api.nvim_buf_get_lines(H.panes().preview.buf, 0, -1, false), "\n")
t.ok(
	"a branch on main's tip has nothing ahead, its history is shown",
	text:find("all commits", 1, true) ~= nil and text:find("Second on main", 1, true) ~= nil,
	text
)

H.press("<C-k>")
H.settle(300)
H.press("<CR>")
H.wait(function()
	return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("Drop b, grow new", 1, true) ~= nil
end)
t.ok("Enter opens the latest commit of the branch", true)
t.eq("and never checks anything out", head(), "main")

t.section("the chain: branch, files changed, grep")
H.open("git_branches", { cwd = dir })
H.settle(300)
H.press("<C-j>")
H.settle(300)
t.ok(
	"the hint offers both ways down",
	H.hint():find("<C-g> files changed in feat/x", 1, true) and H.hint():find("<C-t> commits in feat/x", 1, true),
	H.hint()
)
H.press("<C-g>")
H.settle(500)
t.eq("files title", H.title(), "feat/x › Files Changed (3)")
t.ok("the files the branch changed", H.has_row("a.lua") and H.has_row("new.lua") and H.has_row("b.lua"), vim.inspect(H.rows()))
t.ok("the diff of the highlighted file is on the right", #vim.api.nvim_buf_get_lines(H.panes().preview.buf, 0, -1, false) > 1)
t.ok("hint: grep and back", H.hint():find("grep your local copies", 1, true) and H.hint():find("back to Git Branches", 1, true), H.hint())
H.press("<C-g>")
H.settle(500)
t.eq("grep title counts the files that exist in the working tree (main is checked out: only a.lua)", H.title(), "feat/x › 1 Files › Live Grep")
H.type("needle")
t.ok(
	"only the branch's files that exist are searched",
	H.has_row("a.lua") and not H.has_row("new.lua") and not H.has_row("b.lua"),
	vim.inspect(H.rows())
)
H.type("")
H.press("<BS>")
H.settle(200)
t.eq("back to the files", H.title(), "feat/x › Files Changed (3)")
H.press("<BS>")
H.settle(200)
t.eq("back to the branches", H.title(), "Git Branches (3)")
t.ok("on the same branch", H.hint():find("feat/x", 1, true) ~= nil, H.hint())
H.close()

t.section("the chain: branch, commits, files, grep")
H.open("git_branches", { cwd = dir })
H.settle(300)
H.press("<C-j>")
H.settle(300)
H.press("<C-t>")
H.settle(500)
t.eq("commits title", H.title(), "feat/x › Commits (2)")
local commit_rows = H.rows()
t.ok(
	"only the commits of the branch, newest first",
	commit_rows[1]:find("Drop b, grow new", 1, true) and commit_rows[2]:find("Add new, change a", 1, true) and not H.has_row("Second on main"),
	vim.inspect(commit_rows)
)
H.press("<C-j>")
H.settle(300)
H.press("<C-g>")
H.settle(500)
t.ok("only the files of that commit", H.has_row("a.lua") and H.has_row("new.lua") and not H.has_row("b.lua"), vim.inspect(H.rows()))
H.press("<C-g>")
H.settle(500)
H.type("needle")
t.ok("grep in those files that exist", H.has_row("a.lua") and not H.has_row("new.lua"), vim.inspect(H.rows()))
H.type("")
H.press("<BS>")
H.press("<BS>")
H.settle(200)
t.eq("back to the commits", H.title(), "feat/x › Commits (2)")
H.press("<BS>")
H.settle(200)
t.eq("back to the branches", H.title(), "Git Branches (3)")
H.close()

t.section("a branch with nothing of its own")
H.open("git_branches", { cwd = dir })
H.settle(300)
H.press("<C-g>")
H.settle(400)
t.eq("<C-g> on main opens nothing", H.title(), "Git Branches (3)")
H.press("<C-t>")
H.settle(500)
t.eq("<C-t> on main lists its history", H.title(), "main › Commits (2)")
H.press("<BS>")
H.settle(200)
H.press("<C-j>")
H.press("<C-j>")
H.settle(300)
H.press("<C-g>")
H.settle(400)
t.eq("a branch on main's tip opens no files either", H.title(), "Git Branches (3)")
H.close()

t.section("not a repository")
local empty = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(empty, "p")
H.open("git_branches", { cwd = empty })
H.settle(300)
t.ok("a single message row", H.has_row("Not a git repository"), vim.inspect(H.rows()))
H.close()

vim.fn.delete(dir, "rf")
vim.fn.delete(empty, "rf")
t.done()
