local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- GitLab prompt text -> request parameters (gl/query.lua): flags, free words, quoting, `project:`,
-- errors for unknown / inapplicable flags, the title scope.

---`query.parse(text, kind)` in the child.
---@param text string
---@param kind? "mr"|"issue"
---@return table
local function parse(text, kind)
	return n.exec_lua(function(tx, k)
		return require("beast.libs.finder.source.gl.query").parse(tx, k)
	end, text, kind or "mr")
end

---The request params of `parse`.
---@param text string
---@param kind? "mr"|"issue"
---@return table
local function params(text, kind)
	local parsed = parse(text, kind)
	return parsed.params or parsed
end

t.describe("finder gl query", function()
	t.before_each(h.clear)

	t.describe("defaults", function()
		t.it("has the default text", function()
			t.eq(
				{ "state:opened ", "state:opened " },
				n.exec_lua(function()
					local query = require("beast.libs.finder.source.gl.query")
					return { query.default_text("mr"), query.default_text("issue") }
				end)
			)
		end)

		t.it("parses the default text to opened", function()
			t.eq({ state = "opened" }, params("state:opened "))
		end)

		t.it("means opened for an empty text", function()
			t.eq({ state = "opened" }, params(""))
		end)
	end)

	t.describe("state", function()
		for _, case in ipairs({
			{ "open", "opened" },
			{ "merged", "merged" },
			{ "closed", "closed" },
			{ "all", "all" },
		}) do
			t.it(("maps state:%s to %s"):format(case[1], case[2]), function()
				t.eq(case[2], params("state:" .. case[1]).state)
			end)
		end

		t.it("ignores the case", function()
			t.eq("merged", params("STATE:Merged").state)
		end)

		t.it("rejects merged for issues", function()
			t.eq('"merged" is not a valid value for state:', parse("state:merged", "issue").error)
		end)

		t.it("rejects a bad value", function()
			t.eq('"wip" is not a valid value for state:', parse("state:wip").error)
		end)

		t.it("rejects an empty value", function()
			t.eq('"state:" needs a value', parse("state:").error)
		end)
	end)

	t.describe("people", function()
		local p

		t.before_each(function()
			p = parse("author:@me assignee:dao reviewer:lee")
		end)

		t.it("keeps @me for the api", function()
			t.eq("@me", p.params.author_username)
		end)

		t.it("maps assignee and reviewer", function()
			t.eq("dao", p.params.assignee_username)
			t.eq("lee", p.params.reviewer_username)
		end)

		t.it("remembers named users, not @me", function()
			t.eq({ { flag = "assignee", name = "dao" }, { flag = "reviewer", name = "lee" } }, p.users)
		end)

		t.it("maps assignee:none and reviewer:none", function()
			t.eq("None", params("assignee:none").assignee_id)
			t.eq("None", params("reviewer:none").reviewer_id)
		end)

		t.it("takes reviewer for merge requests only", function()
			t.eq('Unknown filter "reviewer:".', parse("reviewer:lee", "issue").error)
		end)
	end)

	t.describe("labels, milestone, draft, branches", function()
		t.it("maps one label", function()
			t.eq("bug", params("label:bug").labels)
		end)

		t.it("makes several labels need all", function()
			t.eq("bug,backend", params("label:bug label:backend").labels)
		end)

		t.it("takes a quoted label with a space", function()
			t.eq("good first", params('label:"good first"').labels)
		end)

		t.it("takes a scoped label as written", function()
			t.eq("priority::high", params("label:priority::high").labels)
		end)

		t.it("maps label:none", function()
			t.eq("None", params("label:none").labels)
		end)

		t.it("maps the milestone", function()
			t.eq("2026.4", params("milestone:2026.4").milestone)
		end)

		t.it("maps draft yes and false", function()
			t.eq("yes", params("draft:yes").draft)
			t.eq("no", params("draft:false").draft)
		end)

		t.it("rejects a bad draft", function()
			t.eq('"maybe" is not a valid value for draft: (yes or no)', parse("draft:maybe").error)
		end)

		t.it("takes draft for merge requests only", function()
			t.eq('Unknown filter "draft:".', parse("draft:no", "issue").error)
		end)

		t.it("maps the source and target branch", function()
			t.eq("retry-backoff", params("source:retry-backoff").source_branch)
			t.eq("main", params("target:main").target_branch)
		end)
	end)

	t.describe("sort", function()
		t.it("sorts by updated, descending", function()
			local p = params("sort:updated")
			t.eq({ "updated_at", "desc" }, { p.order_by, p.sort })
		end)

		t.it("sorts by created, ascending", function()
			local p = params("sort:created-asc")
			t.eq({ "created_at", "asc" }, { p.order_by, p.sort })
		end)

		t.it("rejects a bad sort", function()
			t.eq('"name" is not a valid value for sort: (created or updated, optionally with -asc)', parse("sort:name").error)
		end)
	end)

	t.describe("words", function()
		t.it("makes the words one search text", function()
			local w = parse("state:opened retry backoff")
			t.eq("retry backoff", w.params.search)
			t.eq("retry backoff", w.words)
		end)

		t.it("searches issues in title and description", function()
			t.eq("title,description", parse("retry", "issue").params["in"])
		end)

		t.it("does not set `in` for merge requests", function()
			t.eq(false, params("retry")["in"] ~= nil)
		end)

		t.it("drops the quotes of a quoted phrase", function()
			t.eq("exponential backoff", params('"exponential backoff"').search)
		end)

		t.it("reads a word with parentheses and a colon as a word", function()
			t.eq("feat(x): add", params("feat(x): add").search)
		end)

		t.it("takes flags and words in any order", function()
			t.eq("merged", params("retry state:merged").state)
		end)
	end)

	t.describe("errors", function()
		local bad

		t.before_each(function()
			bad = parse("state:opened colour:red")
		end)

		t.it("names an unknown flag", function()
			t.eq('Unknown filter "colour:".', bad.error)
		end)

		t.it("lists the merge request flags, one row at a time", function()
			t.eq("Available: state, author, assignee, reviewer,\n  label, milestone, draft, source, target,\n  sort, project", bad.hint)
		end)

		t.it("lists the issue flags", function()
			t.eq("Available: state, author, assignee, label,\n  milestone, sort, project", parse("x:y", "issue").hint)
		end)

		t.it("fits every hint row in a narrow list", function()
			for line in vim.gsplit(bad.hint, "\n", { plain = true }) do
				t.eq(true, #line <= 46)
			end
		end)

		t.it("gives no params", function()
			t.eq(nil, bad.params)
		end)
	end)

	t.describe("project", function()
		t.it("is not a parameter", function()
			t.eq(nil, parse("project:platform/billing/core").params.project)
		end)

		t.it("is returned", function()
			t.eq("platform/billing/core", parse("project:platform/billing/core").project)
		end)

		for _, case in ipairs({
			{ "defaults to the current project", "state:opened ", "o/n" },
			{ "follows project:", "project:a/b/c state:opened", "a/b/c" },
			{ "ignores a bare word", "project", "o/n" },
		}) do
			t.it("scope " .. case[1], function()
				t.eq(
					case[3],
					n.exec_lua(function(text)
						return require("beast.libs.finder.source.gl.query").scope(text, "o/n")
					end, case[2])
				)
			end)
		end
	end)
end)
