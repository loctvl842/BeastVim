local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- The GitHub search text: the prompt is sent as-is, plus the current repo as scope and newest-first
-- order unless the user already said otherwise.

local REPO = "loctvl842/jarvix"

---@param fn "default_text"|"build"|"scope"
---@param ... any
---@return string
local function q(fn, ...)
	return n.exec_lua(function(name, ...)
		return require("beast.libs.finder.source.gh.query")[name](...)
	end, fn, ...)
end

t.describe("finder gh query", function()
	t.before_each(h.clear)

	t.describe("default text", function()
		t.it("is open pull requests", function()
			t.eq("is:pr state:open ", q("default_text", "pr"))
		end)

		t.it("is open issues", function()
			t.eq("is:issue state:open ", q("default_text", "issue"))
		end)
	end)

	t.describe("build", function()
		for _, case in ipairs({
			{
				"adds the repo and the sort to the default pr text",
				"is:pr state:open ",
				"is:pr state:open repo:loctvl842/jarvix sort:created-desc",
			},
			{ "scopes and sorts an empty text", "", "repo:loctvl842/jarvix sort:created-desc" },
			{ "keeps the words", "is:pr hub fix", "is:pr hub fix repo:loctvl842/jarvix sort:created-desc" },
			{ "lets an own repo: win", "repo:neovim/neovim is:issue", "repo:neovim/neovim is:issue sort:created-desc" },
			{ "counts org: as a scope", "org:neovim is:pr", "org:neovim is:pr sort:created-desc" },
			{ "counts user: as a scope", "user:tjdevries is:pr", "user:tjdevries is:pr sort:created-desc" },
			{
				"does not take a negated repo as a scope",
				"-repo:foo/bar is:pr",
				"-repo:foo/bar is:pr repo:loctvl842/jarvix sort:created-desc",
			},
			{ "reads qualifier keys case-insensitively", "Repo:a/b SORT:updated-asc", "Repo:a/b SORT:updated-asc" },
			{ "lets an own sort: win", "is:pr sort:updated-asc", "is:pr sort:updated-asc repo:loctvl842/jarvix" },
			{ "adds nothing when both are given", "repo:a/b sort:comments-desc", "repo:a/b sort:comments-desc" },
			{
				"keeps a quoted value with a space",
				'is:pr label:"help wanted"',
				'is:pr label:"help wanted" repo:loctvl842/jarvix sort:created-desc',
			},
			{
				"does not read repo: inside quotes as a qualifier",
				'"fix repo:a/b" is:pr',
				'"fix repo:a/b" is:pr repo:loctvl842/jarvix sort:created-desc',
			},
			{
				"does not read a word with a colon mid-token as a qualifier",
				"foo:bar",
				"foo:bar repo:loctvl842/jarvix sort:created-desc",
			},
			{
				"does not read the word sort in text as a qualifier",
				"how to sort things",
				"how to sort things repo:loctvl842/jarvix sort:created-desc",
			},
			{ "trims surrounding whitespace", "  is:pr  ", "is:pr repo:loctvl842/jarvix sort:created-desc" },
		}) do
			t.it(case[1], function()
				t.eq(case[3], q("build", case[2], REPO))
			end)
		end
	end)

	t.describe("scope", function()
		for _, case in ipairs({
			{ "defaults to the repo", "is:pr state:open ", REPO },
			{ "follows repo:", "repo:neovim/neovim is:issue", "neovim/neovim" },
			{ "follows org:", "is:pr org:neovim", "neovim" },
			{ "ignores an empty value", "repo: is:pr", REPO },
			{ "ignores a negated repo for the title", "-repo:foo/bar", REPO },
		}) do
			t.it(case[1], function()
				t.eq(case[3], q("scope", case[2], REPO))
			end)
		end
	end)
end)
