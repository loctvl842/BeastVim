local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local t = require("test.testutil")

-- Pull requests -> files changed -> grep in the local copies (three levels), gh scripted.
t.describe("finder chain: pull requests -> files changed -> grep", function()
	local dir
	local page1 = "gh api -X GET repos/o/n/pulls/5/files --hostname github.com -f per_page=100 -f page=1"
	local files = {
		{ filename = "src/here.lua", status = "modified", additions = 1, deletions = 0, patch = "@@ -1 +1 @@\n+x" },
		{ filename = "src/also.lua", status = "added", additions = 1, deletions = 0, patch = "@@ -0,0 +1 @@\n+x" },
		{ filename = "src/gone.lua", status = "removed", additions = 0, deletions = 1, patch = "@@ -1 +0,0 @@\n-x" },
		{ filename = "src/missing.lua", status = "modified", additions = 1, deletions = 0, patch = "@@ -1 +1 @@\n+x" },
	}

	t.before_each(function()
		F.setup()
		dir = F.tmpdir({
			["src/here.lua"] = "needle here",
			["src/also.lua"] = "needle again",
			["src/other.lua"] = "needle but not in the pull request",
		})
		gh.install()
		gh.set({
			["gh api -X GET search/issues"] = gh.json({ total_count = 1, items = { gh.pr(5, "Touch things") } }),
			[page1] = gh.json(files),
		})
	end)

	t.after_each(function()
		F.close()
		gh.restore()
		F.rmdir(dir)
	end)

	---Open the pull requests and go to the files changed (level 2).
	local function to_files()
		F.open("gh_pr", { cwd = dir })
		F.settle(400)
		F.press("<C-g>")
		F.settle(400)
	end

	t.it("lists all four changed files at level 2 and offers the local grep", function()
		to_files()
		t.eq("PR Touch things › Files Changed (4)", F.title())
		t.eq(true, F.hint():find("<C-g> grep your local copies", 1, true) ~= nil)
	end)

	t.describe("level 3", function()
		t.before_each(function()
			to_files()
			F.press("<C-g>")
			F.settle(300)
		end)

		t.it("drops removed and missing files", function()
			t.eq("2 PR Files › Live Grep", F.title())
		end)

		t.it("says the grep is over local copies and the way back", function()
			t.eq(true, F.has_row("your local copies of the 2 files"))
			t.eq(true, F.hint():find("<BS> back to Files Changed", 1, true) ~= nil)
		end)

		t.it("searches only the files of the pull request", function()
			F.type("needle", 600)
			t.eq(true, F.has_row("here.lua"))
			t.eq(true, F.has_row("also.lua"))
			t.eq(false, F.has_row("other.lua"))
		end)

		t.it("goes back to level 2 with its count, then to level 1 without repeating a gh call", function()
			F.type("needle", 600)
			F.type("")
			F.press("<BS>")
			F.settle(300)
			t.eq("PR Touch things › Files Changed (4)", F.title())
			t.eq("4", F.count())
			F.press("<BS>")
			F.settle(300)
			t.matches("^Pull Requests", F.title())
			t.eq({ 1, 1 }, { gh.count("gh api -X GET search/issues"), gh.count(page1) })
		end)
	end)

	t.it("refuses when none of the files exist locally: a message, the level stays", function()
		gh.set({ [page1] = gh.json({ files[3], files[4] }) })
		to_files()
		F.press("<C-g>")
		F.settle(200)
		t.eq("None of these files exist in your working tree", F.last_toast())
		t.matches("^PR Touch", F.title())
	end)
end)
