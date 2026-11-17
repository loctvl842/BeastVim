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

vim.fn.delete(dir, "rf")
t.done()
