local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Local commits -> files changed -> grep (the chain through the real picker, over a real git repo).
-- Needs git and rg on PATH.

---@param dir string
---@param ... string
local function git(dir, ...)
	local res = vim.system({ "git", "-C", dir, "-c", "user.name=Zed", "-c", "user.email=z@e.x", ... }, { text = true }):wait()
	assert(res.code == 0, res.stderr)
end

t.describe("finder git commits", function()
	local dir, empty

	t.setup(function()
		dir = vim.fn.resolve(vim.fn.tempname())
		empty = vim.fn.resolve(vim.fn.tempname())
		vim.fn.mkdir(dir .. "/lib", "p")
		vim.fn.mkdir(empty, "p")
		git(dir, "init", "-q")
		vim.fn.writefile({ "alpha one", "needle here" }, dir .. "/lib/a.lua")
		vim.fn.writefile({ "beta" }, dir .. "/lib/b.lua")
		git(dir, "add", ".")
		git(dir, "commit", "-q", "-m", "First commit")
		vim.fn.writefile({ "alpha two", "needle here", "extra" }, dir .. "/lib/a.lua")
		git(dir, "mv", "lib/b.lua", "lib/c.lua")
		vim.fn.writefile({ "delta needle" }, dir .. "/lib/d.lua")
		git(dir, "add", ".")
		git(dir, "commit", "-q", "-m", "Second commit\n\nBody of the second")
	end)

	t.teardown(function()
		vim.fn.delete(dir, "rf")
		vim.fn.delete(empty, "rf")
	end)

	t.before_each(function()
		F.setup()
		n.exec_lua(function(d)
			vim.cmd("cd " .. vim.fn.fnameescape(d))
		end, dir)
	end)

	t.after_each(F.close)

	t.describe("parsing", function()
		---The commits of the repo, newest first.
		---@return table[]
		local function commits()
			return n.exec_lua(function(d)
				local got
				require("beast.libs.finder.source.git.log").commits(d, function(result)
					got = result.commits
				end)
				FH.wait(function()
					return got ~= nil
				end)
				return got
			end, dir)
		end

		---The files of the newest commit, keyed by path.
		---@return table<string, table>
		local function files()
			return n.exec_lua(function(d)
				local log = require("beast.libs.finder.source.git.log")
				local sha
				log.commits(d, function(result)
					sha = result.commits[1].sha
				end)
				FH.wait(function()
					return sha ~= nil
				end)
				local detail
				log.show(d, sha, function(result)
					detail = result.detail
				end)
				FH.wait(function()
					return detail ~= nil
				end)
				local by = { count = #detail.files }
				for _, file in ipairs(detail.files) do
					by[file.path] = {
						status = file.status,
						additions = file.additions,
						deletions = file.deletions,
						previous = file.previous,
						hunk = file.patch ~= nil and file.patch:sub(1, 2) == "@@",
						has_patch = file.patch ~= nil,
					}
				end
				return by
			end, dir)
		end

		t.it("lists the newest first", function()
			local c = commits()
			t.eq({ "Second commit", "First commit" }, { c[1].subject, c[2].subject })
		end)

		t.it("keeps the body in the message", function()
			t.eq("Second commit\n\nBody of the second", commits()[1].message)
		end)

		t.it("lists three files", function()
			t.eq(3, files().count)
		end)

		t.it("reads a modified file", function()
			local a = files()["lib/a.lua"]
			t.eq({ "modified", 2, 1 }, { a.status, a.additions, a.deletions })
		end)

		t.it("keeps the old path of a rename", function()
			local c = files()["lib/c.lua"]
			t.eq({ "renamed", "lib/b.lua" }, { c.status, c.previous })
		end)

		t.it("reads an added file", function()
			t.eq("added", files()["lib/d.lua"].status)
		end)

		t.it("starts the patch at the first hunk", function()
			t.eq(true, files()["lib/a.lua"].hunk)
		end)

		t.it("gives a pure rename no hunk", function()
			t.eq(false, files()["lib/c.lua"].has_patch)
		end)
	end)

	t.describe("the chain", function()
		local short

		t.before_each(function()
			F.open("git_commits", { cwd = dir })
			F.settle(300)
			short = n.exec_lua(function(d)
				local got
				require("beast.libs.finder.source.git.log").commits(d, function(result)
					got = result.commits[1].short
				end)
				FH.wait(function()
					return got ~= nil
				end)
				return got
			end, dir)
		end)

		t.it("titles with the count", function()
			t.eq("Commits (2)", F.title())
		end)

		t.it("lists the latest first", function()
			local rows = F.rows()
			t.eq(true, rows[1]:find("Second commit", 1, true) ~= nil)
			t.eq(true, rows[2]:find("First commit", 1, true) ~= nil)
		end)

		t.it("offers the files changed in the hint", function()
			t.eq(true, F.hint():find("<C-g> files changed", 1, true) ~= nil)
		end)

		t.it("previews the diff", function()
			F.settle(300)
			t.eq(true, F.preview_text():find("Body of the second", 1, true) ~= nil)
		end)

		t.describe("a key of another picker's chain", function()
			t.it("is muted (<C-t> would indent the prompt)", function()
				t.eq(true, F.press("<C-t>"))
			end)

			t.it("leaves the prompt and the list untouched", function()
				F.press("<C-t>")
				t.eq("", F.prompt())
				t.eq("Commits (2)", F.title())
			end)
		end)

		t.describe("files changed", function()
			t.before_each(function()
				F.press("<C-g>")
				F.settle(400)
			end)

			t.it("has the full chain in the title", function()
				t.eq(("%s Second commit › Files Changed (3)"):format(short), F.title())
			end)

			t.it("lists the files", function()
				t.eq(true, F.has_row("a.lua") and F.has_row("c.lua") and F.has_row("d.lua"))
			end)

			t.describe("grep", function()
				t.before_each(function()
					F.press("<C-g>")
					F.settle(400)
				end)

				t.it("titles the grep", function()
					t.eq(("%s Second commit › 3 Files › Live Grep"):format(short), F.title())
				end)

				t.it("searches only the commit's files", function()
					F.type("needle")
					t.eq(true, F.has_row("a.lua") and F.has_row("d.lua"))
					t.eq(false, F.has_row("b.lua"))
				end)

				t.it("goes back to the files, then to the commits", function()
					F.type("")
					F.press("<BS>")
					F.settle(200)
					t.eq(("%s Second commit › Files Changed (3)"):format(short), F.title())
					F.press("<BS>")
					F.settle(200)
					t.eq("Commits (2)", F.title())
				end)
			end)
		end)
	end)

	t.it("shows an error row when the directory is not a repository", function()
		F.open("git_commits", { cwd = empty })
		F.settle(300)
		t.eq(true, F.has_row("git could not list the commits"))
	end)
end)
