local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Pull requests -> commits -> grep in the files of a commit (three levels, gh scripted).
-- docs/dev-specs/finder-pr-commits.md, Phase 3
t.describe("finder chain: pull requests -> commits -> grep", function()
	local dir
	local GREP_TITLE = "PR Touch things › 0000001 Commit 1 subject › 2 Files › Live Grep"
	local COMMITS_TITLE = "PR Touch things › Commits (4)"

	t.before_each(function()
		F.setup()
		dir = F.tmpdir({
			["lib/c1.lua"] = "needle one",
			["lib/c2.lua"] = "needle two",
			["lib/other.lua"] = "needle but not in the commit",
		})
		gh.install()
		local commits = gh.commits(4)
		local removed = gh.files(1, "lib/gone")
		removed[1].status = "removed"
		local c1 = gh.files(2, "lib/c")
		c1[3] = removed[1]
		local function commit_url(i)
			return "gh api -X GET repos/o/n/commits/" .. commits[i].sha
		end
		gh.set({
			["gh api -X GET search/issues"] = gh.json({ total_count = 1, items = { gh.pr(1, "Touch things") } }),
			["gh api -X GET repos/o/n/pulls/1/commits --hostname github.com -f per_page=100 -f page=1"] = gh.json(gh.reversed(commits)),
			[commit_url(1)] = gh.json({ commit = { message = "m" }, files = c1 }),
			[commit_url(2)] = gh.json({ commit = { message = "m" }, files = gh.files(1, "lib/missing") }),
			[commit_url(3)] = gh.json({ commit = { message = "merge" } }),
			[commit_url(4)] = gh.fail("gh: Not Found (HTTP 404)"),
		})
	end)

	t.after_each(function()
		F.close()
		gh.restore()
		F.rmdir(dir)
	end)

	---Open the pull requests and go to the commits (level 2).
	local function to_commits()
		F.open("gh_pr", { cwd = dir })
		F.settle(400)
		F.press("<C-t>")
		F.settle(400)
	end

	---Move down `count` commits and press <C-f> (grep its files).
	---@param count integer
	local function grep_commit(count)
		for _ = 1, count do
			F.press("<C-j>")
			F.settle(300)
		end
		F.press("<C-f>")
		F.settle(300)
	end

	t.describe("happy path", function()
		t.before_each(to_commits)

		t.it("shows the commits with the grep and the way back in the hint", function()
			t.eq(COMMITS_TITLE, F.title())
			local hint = F.hint()
			t.eq(true, hint:find("<C-f> grep its files", 1, true) ~= nil)
			t.eq(true, hint:find("<BS> back to Pull Requests", 1, true) ~= nil)
		end)

		t.it("opens level 3 without the removed files", function()
			F.press("<C-f>")
			F.settle(300)
			t.eq(GREP_TITLE, F.title())
			t.eq(true, F.has_row("local copies of the 2 files changed by 0000001"))
			t.eq(true, F.hint():find("<BS> back to Commits", 1, true) ~= nil)
		end)

		t.it("searches both files of the commit and not the others", function()
			F.press("<C-f>")
			F.settle(300)
			F.type("needle", 600)
			t.eq(true, F.has_row("c1.lua") and F.has_row("c2.lua"))
			t.eq(false, F.has_row("other.lua"))
		end)

		t.it("goes back to the commits with the diff in the preview, then the pull requests, then again", function()
			F.press("<C-f>")
			F.settle(300)
			F.type("needle", 600)
			F.type("")
			F.press("<BS>")
			F.settle(300)
			t.eq(COMMITS_TITLE, F.title())
			F.settle(300)
			t.eq(true, F.preview_text():find("new 1", 1, true) ~= nil)
			F.press("<BS>")
			F.settle(300)
			t.eq(true, F.has_row("Touch things"))
			F.settle(300)
			t.eq(true, F.preview_text():find("+new 1", 1, true) == nil)
			F.press("<C-t>")
			F.settle(400)
			t.eq(true, F.preview_text():find("new 1", 1, true) ~= nil)
		end)
	end)

	t.describe("refusals", function()
		t.before_each(to_commits)

		t.it("says none of the files exist and stays on the commits", function()
			grep_commit(1)
			t.eq({ "None of these files exist in your working tree", COMMITS_TITLE }, { F.last_toast(), F.title() })
		end)

		t.it("says nothing to open for a commit without files", function()
			grep_commit(2)
			t.eq({ "Nothing to open from here", true }, { F.last_toast(), F.title():match("^PR") ~= nil })
		end)

		t.it("shows an error of GitHub", function()
			grep_commit(3)
			t.eq(true, F.last_toast():find("Not Found", 1, true) ~= nil)
		end)
	end)

	t.describe("waiting for the commit", function()
		t.before_each(function()
			gh.hold({ "gh api -X GET repos/o/n/commits/" })
			to_commits()
		end)

		t.it("says a second press is loading and the answer then opens the grep", function()
			F.press("<C-f>")
			F.settle(100)
			F.press("<C-f>")
			t.eq("Still loading - try again in a moment", F.last_toast())
			t.eq(COMMITS_TITLE, F.title())
			gh.release()
			F.settle(300)
			t.eq(GREP_TITLE, F.title())
		end)

		t.it("opens nothing when the selection moved while waiting", function()
			F.press("<C-f>")
			F.settle(100)
			F.press("<C-j>")
			F.settle(100)
			gh.release()
			F.settle(300)
			t.eq(COMMITS_TITLE, F.title())
		end)

		t.it("opens nothing when the user went back while waiting", function()
			F.press("<C-f>")
			F.settle(100)
			F.press("<BS>")
			F.settle(200)
			t.eq(true, F.has_row("Touch things"))
			gh.release()
			F.settle(300)
			t.eq(true, F.has_row("Touch things") and F.title():match("^Pull Requests") ~= nil)
		end)

		t.it("brings no picker back when closed while waiting", function()
			F.press("<C-f>")
			F.settle(100)
			F.close()
			gh.release()
			F.settle(300)
			t.eq(0, F.window_count())
		end)
	end)

	t.describe("a remapped key", function()
		t.before_each(function()
			n.exec_lua(function()
				require("beast.libs.finder").setup({ chains = { edges = { ["gh_commits|live_grep"] = { key = "<C-x>" } } } })
			end)
			to_commits()
		end)

		t.it("shows the key in the hint", function()
			t.eq(true, F.hint():find("<C-x> grep its files", 1, true) ~= nil)
		end)

		t.it("follows the edge", function()
			F.press("<C-x>")
			F.settle(300)
			t.eq(GREP_TITLE, F.title())
		end)
	end)
end)
