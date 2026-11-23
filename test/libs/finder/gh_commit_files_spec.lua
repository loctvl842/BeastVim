local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Pull requests -> commits -> files changed by a commit -> grep in them (the chain through the real
-- picker, gh scripted).
t.describe("finder chain: commit files", function()
	local dir
	local FILES_TITLE = "PR Touch things › 0000001 Commit 1 subject › Files Changed (2)"

	t.before_each(function()
		F.setup()
		dir = F.tmpdir({ ["lib/c1.lua"] = "needle one", ["lib/other.lua"] = "needle other" })
		gh.install()
		local commits = gh.commits(3)
		local function commit_url(i)
			return "gh api -X GET repos/o/n/commits/" .. commits[i].sha
		end
		gh.set({
			["gh api -X GET search/issues"] = gh.json({ total_count = 1, items = { gh.pr(1, "Touch things") } }),
			["gh api -X GET repos/o/n/pulls/1/commits --hostname github.com -f per_page=100 -f page=1"] = gh.json(gh.reversed(commits)),
			[commit_url(1)] = gh.json({ commit = { message = "m" }, files = gh.files(2, "lib/c") }), -- c1 exists, c2 does not
			[commit_url(2)] = gh.json({ commit = { message = "merge" } }),
			[commit_url(3)] = gh.fail("gh: Not Found (HTTP 404)"),
		})
	end)

	t.after_each(function()
		F.close()
		gh.restore()
		F.rmdir(dir)
	end)

	---Open the pull requests and go to the commits.
	local function to_commits()
		F.open("gh_pr", { cwd = dir })
		F.settle(400)
		F.press("<C-t>")
		F.settle(400)
	end

	---Go on to the files changed by the first commit.
	local function to_files()
		to_commits()
		F.press("<C-g>")
		F.settle(400)
	end

	t.it("offers the files changed and the grep from the commits", function()
		to_commits()
		local hint = F.hint()
		t.eq(true, hint:find("<C-g> files changed", 1, true) ~= nil and hint:find("<C-f> grep", 1, true) ~= nil)
	end)

	t.describe("files changed level", function()
		t.before_each(to_files)

		t.it("is titled after the commit and lists only paths with a count", function()
			t.eq(FILES_TITLE, F.title())
			t.eq({ true, true }, { F.has_row("c1.lua"), F.has_row("c2.lua") })
			t.eq("2", F.count())
		end)

		t.it("shows the diff of the selected file and follows the selection", function()
			t.eq(true, F.preview_text():find("new 1", 1, true) ~= nil)
			F.press("<C-j>")
			F.settle(300)
			t.eq(true, F.preview_text():find("new 2", 1, true) ~= nil)
		end)

		t.it("offers the grep and the way back", function()
			local hint = F.hint()
			t.eq(true, hint:find("<C-g> grep your local copies", 1, true) ~= nil)
			t.eq(true, hint:find("<BS> back to Commits", 1, true) ~= nil)
		end)

		t.it("loses the middle of the chain on a narrow screen and gets it back with room", function()
			n.exec_lua(function()
				vim.o.columns = 90
				vim.api.nvim_exec_autocmds("VimResized", {})
			end)
			F.settle(100)
			local narrow = F.title()
			t.eq(true, narrow:find("...", 1, true) ~= nil and narrow:sub(-11) == "Changed (2)")
			n.exec_lua(function()
				vim.o.columns = 200
				vim.api.nvim_exec_autocmds("VimResized", {})
			end)
			F.settle(100)
			t.eq(FILES_TITLE, F.title())
		end)

		t.it("filters by path while typing", function()
			F.type("c2")
			t.eq(true, F.has_row("c2.lua") and not F.has_row("c1.lua"))
			t.eq("1/2", F.count())
		end)

		t.describe("grep in the local copies", function()
			t.before_each(function()
				F.press("<C-g>")
				F.settle(300)
			end)

			t.it("is scoped to the commit's files", function()
				t.eq("PR Touch things › 0000001 Commit 1 subject › 1 Files › Live Grep", F.title())
				t.eq(true, F.has_row("changed by 0000001"))
			end)

			t.it("searches the file of the commit and not the others", function()
				F.type("needle", 600)
				t.eq(true, F.has_row("c1.lua") and not F.has_row("other.lua"))
			end)

			t.it("goes back to the files of the commit, then the commits", function()
				F.type("needle", 600)
				F.type("")
				F.press("<BS>")
				F.settle(300)
				t.eq(FILES_TITLE, F.title())
				t.eq(true, F.preview_text():find("new", 1, true) ~= nil)
				F.press("<BS>")
				F.settle(300)
				t.eq("PR Touch things › Commits (3)", F.title())
			end)
		end)

		t.it("opens the commit's diff of a file on Enter", function()
			F.press("<CR>")
			F.settle(300)
			t.eq(0, F.window_count())
			local buf = n.exec_lua(function()
				local b = vim.api.nvim_get_current_buf()
				return { name = vim.api.nvim_buf_get_name(b), ft = vim.bo[b].filetype, modifiable = vim.bo[b].modifiable }
			end)
			t.eq(true, buf.name:find("o/n@0000001: lib/c1.lua", 1, true) ~= nil)
			t.eq({ "diff", false }, { buf.ft, buf.modifiable })
		end)
	end)

	t.describe("a commit without files, and an error", function()
		t.before_each(function()
			to_commits()
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-g>")
			F.settle(400)
		end)

		t.it("says so with a message row and follows no chain from it", function()
			t.eq(true, F.has_row("No files changed"))
			F.press("<C-g>")
			t.eq("Nothing to open from here", F.last_toast())
		end)

		t.it("shows an error as a message row", function()
			F.press("<BS>")
			F.settle(300)
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-g>")
			F.settle(400)
			t.eq(true, F.has_row("GitHub could not list the files"))
		end)
	end)
end)
