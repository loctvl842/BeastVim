local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Local branches -> files changed / commits -> grep (the git reads and the chain through the real
-- picker, over a real git repo). Needs git and rg on PATH.

t.describe("finder git branches", function()
	local dir, empty
	local tick = 0

	---Run git in the repo; every call is one second later so the commit dates (and the branch order) are stable.
	---@param ... string
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

	---@param path string
	---@param lines string[]
	local function write(path, lines)
		vim.fn.writefile(lines, dir .. "/" .. path)
	end

	t.setup(function()
		dir = vim.fn.resolve(vim.fn.tempname())
		empty = vim.fn.resolve(vim.fn.tempname())
		vim.fn.mkdir(dir .. "/lib", "p")
		vim.fn.mkdir(empty, "p")
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
	end)

	t.teardown(function()
		vim.fn.delete(dir, "rf")
		vim.fn.delete(empty, "rf")
	end)

	t.before_each(function()
		F.setup()
		n.exec_lua(function(d)
			vim.cmd("cd " .. vim.fn.fnameescape(d))
			---Call a callback-style git read `fn(args..., cb)` and wait for what `cb` gets.
			_G.read = function(fn, ...)
				local out
				local args = { ... }
				local count = select("#", ...)
				args[count + 1] = function(result)
					out = result
				end
				fn(unpack(args, 1, count + 1))
				FH.wait(function()
					return out ~= nil
				end)
				return out
			end
			_G.log = require("beast.libs.finder.source.git.log")
		end, dir)
	end)

	t.after_each(F.close)

	---@return table[] branches
	local function branches()
		return n.exec_lua(function(d)
			return _G.read(_G.log.branches, d).branches
		end, dir)
	end

	t.describe("branches", function()
		t.it("lists the current branch first, then the newest", function()
			t.eq(
				{ "main", "feat/x", "old" },
				vim.tbl_map(function(b)
					return b.name
				end, branches())
			)
		end)

		t.it("marks the current one", function()
			local b = branches()
			t.eq({ true, false }, { b[1].current, b[2].current })
		end)

		t.it("has the latest commit of the branch", function()
			t.eq("Drop b, grow new", branches()[2].subject)
		end)

		t.it("has a short id", function()
			local b = branches()[2]
			t.eq(b.sha:sub(1, 7), b.short)
		end)

		t.it("takes main as the default", function()
			t.eq(
				"main",
				n.exec_lua(function(list)
					return _G.log.default_name(list)
				end, branches())
			)
		end)

		t.it("takes master when there is no main", function()
			t.eq(
				"master",
				n.exec_lua(function()
					return _G.log.default_name({ { name = "master" }, { name = "x" } })
				end)
			)
		end)

		t.it("has no default when there is neither", function()
			t.eq(
				false,
				n.exec_lua(function()
					return _G.log.default_name({ { name = "x" } }) ~= nil
				end)
			)
		end)

		t.it("reports an error when not a repository", function()
			t.eq(
				true,
				n.exec_lua(function(d)
					return _G.read(_G.log.branches, d).error ~= nil
				end, empty)
			)
		end)
	end)

	t.describe("base", function()
		---`log.base(dir, branch, default)` for the branch at `index`; `false` when there is none.
		---@param index integer
		---@param default? string
		---@return string|false
		local function base(index, default)
			return n.exec_lua(function(a)
				local list = _G.read(_G.log.branches, a.dir).branches
				return _G.read(function(d, b, def, cb)
					_G.log.base(d, b, def, function(sha)
						cb({ base = sha or false })
					end)
				end, a.dir, list[a.index], a.default).base
			end, { dir = dir, index = index, default = default })
		end

		t.it("is the default's tip for a branch with commits of its own", function()
			t.eq(branches()[1].sha, base(2, "main"))
		end)

		t.it("is none for the default branch", function()
			t.eq(false, base(1, "main"))
		end)

		t.it("is none for a branch on the default's tip", function()
			t.eq(false, base(3, "main"))
		end)

		t.it("is none without a default branch", function()
			t.eq(false, base(2, nil))
		end)
	end)

	t.describe("commits of a range", function()
		---@param rev? string
		---@return string[] subjects
		local function subjects(rev)
			return n.exec_lua(function(a)
				local result = _G.read(function(d, r, cb)
					_G.log.commits(d, cb, r)
				end, a.dir, a.rev)
				return vim.tbl_map(function(c)
					return c.subject
				end, result.commits)
			end, { dir = dir, rev = rev })
		end

		t.it("has only the commits the branch added, newest first", function()
			t.eq({ "Drop b, grow new", "Add new, change a" }, subjects("refs/heads/main..refs/heads/feat/x"))
		end)

		t.it("walks HEAD without a revision", function()
			t.eq(2, #subjects())
		end)

		t.it("lists a whole branch", function()
			t.eq(4, #subjects("refs/heads/feat/x"))
		end)
	end)

	t.describe("diff", function()
		---@return table<string, table> by path, plus `count` and `truncated`
		local function diff()
			return n.exec_lua(function(d)
				local list = _G.read(_G.log.branches, d).branches
				local detail = _G.read(_G.log.diff, d, list[1].sha, list[2].sha).detail
				local by = { count = #detail.files, truncated = detail.truncated }
				for _, file in ipairs(detail.files) do
					by[file.path] = { status = file.status, patch_start = file.patch and file.patch:sub(1, 2) }
				end
				return by
			end, dir)
		end

		t.it("has one row per file the branch changed", function()
			t.eq(3, diff().count)
		end)

		t.it("tells modified, added and removed", function()
			local by = diff()
			t.eq("modified", by["lib/a.lua"].status)
			t.eq("added", by["lib/new.lua"].status)
			t.eq("removed", by["lib/b.lua"].status)
		end)

		t.it("starts the patch at the first hunk", function()
			t.eq("@@", diff()["lib/a.lua"].patch_start)
		end)

		t.it("is not truncated", function()
			t.eq(false, diff().truncated)
		end)

		t.it("reports an error for a bad revision", function()
			t.eq(
				true,
				n.exec_lua(function(d)
					local list = _G.read(_G.log.branches, d).branches
					return _G.read(_G.log.diff, d, "nope", list[2].sha).error ~= nil
				end, dir)
			)
		end)
	end)

	t.describe("the picker", function()
		t.before_each(function()
			F.open("git_branches", { cwd = dir })
			F.settle(300)
		end)

		t.it("titles with the count", function()
			t.eq("Git Branches (3)", F.title())
		end)

		t.it("puts the branch you are on first, marked", function()
			local row = F.rows()[1]
			t.eq(true, row:find("●", 1, true) ~= nil and row:find("main", 1, true) ~= nil)
		end)

		t.it("puts the newest next, not marked", function()
			local row = F.rows()[2]
			t.eq(true, row:find("feat/x", 1, true) ~= nil and row:find("Drop b, grow new", 1, true) ~= nil)
			t.eq(true, row:find("●", 1, true) == nil)
		end)

		t.it("filters by the latest commit", function()
			F.type("Drop")
			F.settle(200)
			t.eq(true, F.has_row("feat/x"))
			t.eq(false, F.has_row("old"))
		end)

		t.it("previews the commits over main", function()
			F.press("<C-j>")
			F.settle(500)
			local text = F.preview_text()
			t.eq(true, text:find("2 commits ahead of main", 1, true) ~= nil)
		end)

		t.it("lists the commits ahead in the preview", function()
			F.press("<C-j>")
			F.settle(500)
			local text = F.preview_text()
			t.eq(true, text:find("Add new, change a", 1, true) ~= nil)
			t.eq(true, text:find("Drop b, grow new", 1, true) ~= nil)
		end)

		t.it("shows the history of a branch on main's tip", function()
			F.press("<C-j>")
			F.press("<C-j>")
			F.settle(500)
			local text = F.preview_text()
			t.eq(true, text:find("all commits", 1, true) ~= nil)
			t.eq(true, text:find("Second on main", 1, true) ~= nil)
		end)

		t.it("opens the latest commit of the branch on Enter and never checks anything out", function()
			F.press("<C-j>")
			F.settle(300)
			F.press("<CR>")
			t.eq(
				true,
				n.exec_lua(function()
					return FH.wait(function()
						return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("Drop b, grow new", 1, true) ~= nil
					end)
				end)
			)
			t.eq("main", vim.trim(vim.system({ "git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait().stdout))
		end)
	end)

	t.describe("the chain: branch, files changed, grep", function()
		t.before_each(function()
			F.open("git_branches", { cwd = dir })
			F.settle(300)
			F.press("<C-j>")
			F.settle(300)
		end)

		t.it("offers both ways down in the hint", function()
			local hint = F.hint()
			t.eq(true, hint:find("<C-g> files changed in feat/x", 1, true) ~= nil)
			t.eq(true, hint:find("<C-t> commits in feat/x", 1, true) ~= nil)
		end)

		t.describe("files changed", function()
			t.before_each(function()
				F.press("<C-g>")
				F.settle(500)
			end)

			t.it("titles with the branch", function()
				t.eq("feat/x › Files Changed (3)", F.title())
			end)

			t.it("lists the files the branch changed", function()
				t.eq(true, F.has_row("a.lua") and F.has_row("new.lua") and F.has_row("b.lua"))
			end)

			t.it("shows the diff of the highlighted file on the right", function()
				t.eq(true, #vim.split(F.preview_text(), "\n") > 1)
			end)

			t.it("offers the grep and the way back in the hint", function()
				local hint = F.hint()
				t.eq(true, hint:find("grep your local copies", 1, true) ~= nil)
				t.eq(true, hint:find("back to Git Branches", 1, true) ~= nil)
			end)

			t.describe("grep", function()
				t.before_each(function()
					F.press("<C-g>")
					F.settle(500)
				end)

				t.it("counts the files that exist in the working tree (main is checked out: only a.lua)", function()
					t.eq("feat/x › 1 Files › Live Grep", F.title())
				end)

				t.it("searches only the branch's files that exist", function()
					F.type("needle")
					t.eq(true, F.has_row("a.lua"))
					t.eq(false, F.has_row("new.lua"))
					t.eq(false, F.has_row("b.lua"))
				end)

				t.it("goes back to the files, then to the same branch", function()
					F.type("")
					F.press("<BS>")
					F.settle(200)
					t.eq("feat/x › Files Changed (3)", F.title())
					F.press("<BS>")
					F.settle(200)
					t.eq("Git Branches (3)", F.title())
					t.eq(true, F.hint():find("feat/x", 1, true) ~= nil)
				end)
			end)
		end)
	end)

	t.describe("the chain: branch, commits, files, grep", function()
		t.before_each(function()
			F.open("git_branches", { cwd = dir })
			F.settle(300)
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-t>")
			F.settle(500)
		end)

		t.it("titles the commits", function()
			t.eq("feat/x › Commits (2)", F.title())
		end)

		t.it("lists only the commits of the branch, newest first", function()
			local rows = F.rows()
			t.eq(true, rows[1]:find("Drop b, grow new", 1, true) ~= nil)
			t.eq(true, rows[2]:find("Add new, change a", 1, true) ~= nil)
			t.eq(false, F.has_row("Second on main"))
		end)

		t.describe("files of the second commit", function()
			t.before_each(function()
				F.press("<C-j>")
				F.settle(300)
				F.press("<C-g>")
				F.settle(500)
			end)

			t.it("lists only the files of that commit", function()
				t.eq(true, F.has_row("a.lua") and F.has_row("new.lua"))
				t.eq(false, F.has_row("b.lua"))
			end)

			t.it("greps in those files that exist", function()
				F.press("<C-g>")
				F.settle(500)
				F.type("needle")
				t.eq(true, F.has_row("a.lua"))
				t.eq(false, F.has_row("new.lua"))
			end)

			t.it("goes back through the commits to the branches", function()
				F.press("<C-g>")
				F.settle(500)
				F.type("needle")
				F.type("")
				F.press("<BS>")
				F.press("<BS>")
				F.settle(200)
				t.eq("feat/x › Commits (2)", F.title())
				F.press("<BS>")
				F.settle(200)
				t.eq("Git Branches (3)", F.title())
			end)
		end)
	end)

	t.describe("a branch with nothing of its own", function()
		t.before_each(function()
			F.open("git_branches", { cwd = dir })
			F.settle(300)
		end)

		t.it("opens no files with <C-g> on main", function()
			F.press("<C-g>")
			F.settle(400)
			t.eq("Git Branches (3)", F.title())
		end)

		t.it("lists main's history with <C-t>", function()
			F.press("<C-t>")
			F.settle(500)
			t.eq("main › Commits (2)", F.title())
		end)

		t.it("opens no files for a branch on main's tip either", function()
			F.press("<C-j>")
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-g>")
			F.settle(400)
			t.eq("Git Branches (3)", F.title())
		end)
	end)

	t.it("shows a single message row when not a repository", function()
		F.open("git_branches", { cwd = empty })
		F.settle(300)
		t.eq(true, F.has_row("Not a git repository"))
	end)
end)
