local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder forge helper", function()
	t.before_each(h.clear)

	---Evaluate `forge[fn](item)` in the child; `item` is plain data.
	---@param fn string
	---@param item table
	local function forge(fn, item)
		return n.exec_lua(function(f, it)
			return require("beast.libs.finder.source.forge")[f](it)
		end, fn, item)
	end

	local gh_item = { number = 7 }
	local gl_item = { provider = "gitlab", number = 7, ref = "!7" }

	t.it("treats an item without provider as GitHub's api", function()
		t.eq(
			true,
			n.exec_lua(function()
				local forge = require("beast.libs.finder.source.forge")
				return forge.api({ number = 7 }) == require("beast.libs.finder.source.gh.api")
			end)
		)
	end)

	t.it("names the forge", function()
		t.eq("GitHub", forge("name", gh_item))
		t.eq("GitLab", forge("name", gl_item))
	end)

	t.it("falls back to #number for the ref, else uses the item's own", function()
		t.eq("#7", forge("ref", gh_item))
		t.eq("!7", forge("ref", gl_item))
	end)

	t.it("calls a review PR or MR", function()
		t.eq("PR", forge("review", gh_item))
		t.eq("MR", forge("review", gl_item))
	end)

	t.it("calls the project Repo or Project", function()
		t.eq("Repo", forge("project", gh_item))
		t.eq("Project", forge("project", gl_item))
	end)

	t.it("makes pr_label say MR for GitLab", function()
		t.eq(
			"MR t",
			n.exec_lua(function()
				return require("beast.libs.finder.format").pr_label({ provider = "gitlab", title = "t" })
			end)
		)
	end)
end)
