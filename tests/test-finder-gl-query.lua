-- =========================================================================
-- Test: GitLab prompt text -> request parameters (gl/query.lua)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 3: flags, free words,
-- quoting, `project:`, errors for unknown / inapplicable flags, the title scope.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gl-query.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local query = require("beast.libs.finder.source.gl.query")
local function params(text, kind)
	local parsed = query.parse(text, kind or "mr")
	return parsed.params or parsed
end

io.write("\n--- defaults ---\n")
assert_eq("default text", query.default_text("mr"), "state:opened ")
assert_eq("same for issues", query.default_text("issue"), "state:opened ")
assert_eq("default text parses to opened", params("state:opened "), { state = "opened" })
assert_eq("empty text means opened", params(""), { state = "opened" })

io.write("\n--- state ---\n")
assert_eq("open is opened", params("state:open").state, "opened")
assert_eq("merged", params("state:merged").state, "merged")
assert_eq("closed", params("state:closed").state, "closed")
assert_eq("all", params("state:all").state, "all")
assert_eq("case does not matter", params("STATE:Merged").state, "merged")
assert_eq("merged does not apply to issues", query.parse("state:merged", "issue").error, '"merged" is not a valid value for state:')
assert_eq("bad value", query.parse("state:wip", "mr").error, '"wip" is not a valid value for state:')
assert_eq("empty value", query.parse("state:", "mr").error, '"state:" needs a value')

io.write("\n--- people ---\n")
local p = query.parse("author:@me assignee:dao reviewer:lee", "mr")
assert_eq("author keeps @me for the api", p.params.author_username, "@me")
assert_eq("assignee", p.params.assignee_username, "dao")
assert_eq("reviewer", p.params.reviewer_username, "lee")
assert_eq("named users are remembered, @me is not", p.users, { { flag = "assignee", name = "dao" }, { flag = "reviewer", name = "lee" } })
assert_eq("assignee none", params("assignee:none").assignee_id, "None")
assert_eq("reviewer none", params("reviewer:none").reviewer_id, "None")
assert_eq("reviewer is for merge requests only", query.parse("reviewer:lee", "issue").error, 'Unknown filter "reviewer:".')

io.write("\n--- labels, milestone, draft, branches ---\n")
assert_eq("one label", params("label:bug").labels, "bug")
assert_eq("several labels need all", params("label:bug label:backend").labels, "bug,backend")
assert_eq("quoted label with a space", params('label:"good first"').labels, "good first")
assert_eq("scoped label as written", params("label:priority::high").labels, "priority::high")
assert_eq("label none", params("label:none").labels, "None")
assert_eq("milestone", params("milestone:2026.4").milestone, "2026.4")
assert_eq("draft yes", params("draft:yes").draft, "yes")
assert_eq("draft false", params("draft:false").draft, "no")
assert_eq("bad draft", query.parse("draft:maybe", "mr").error, '"maybe" is not a valid value for draft: (yes or no)')
assert_eq("draft is for merge requests only", query.parse("draft:no", "issue").error, 'Unknown filter "draft:".')
assert_eq("source branch", params("source:retry-backoff").source_branch, "retry-backoff")
assert_eq("target branch", params("target:main").target_branch, "main")

io.write("\n--- sort ---\n")
assert_eq("sort updated", { params("sort:updated").order_by, params("sort:updated").sort }, { "updated_at", "desc" })
assert_eq("sort created asc", { params("sort:created-asc").order_by, params("sort:created-asc").sort }, { "created_at", "asc" })
assert_eq("bad sort", query.parse("sort:name", "mr").error, '"name" is not a valid value for sort: (created or updated, optionally with -asc)')

io.write("\n--- words ---\n")
local w = query.parse("state:opened retry backoff", "mr")
assert_eq("words are one search text", w.params.search, "retry backoff")
assert_eq("words field", w.words, "retry backoff")
assert_eq("issues search title and description", query.parse("retry", "issue").params["in"], "title,description")
assert_eq("merge requests do not set `in`", params("retry")["in"], nil)
assert_eq("quoted phrase loses its quotes", params('"exponential backoff"').search, "exponential backoff")
assert_eq("a word with parentheses and a colon is a word", params("feat(x): add").search, "feat(x): add")
assert_eq("flags and words in any order", params("retry state:merged").state, "merged")

io.write("\n--- errors ---\n")
local bad = query.parse("state:opened colour:red", "mr")
assert_eq("unknown flag", bad.error, 'Unknown filter "colour:".')
assert_eq(
	"hint lists the merge request flags, one row at a time",
	bad.hint,
	"Available: state, author, assignee, reviewer,\n  label, milestone, draft, source, target,\n  sort, project"
)
assert_eq("hint lists the issue flags", query.parse("x:y", "issue").hint, "Available: state, author, assignee, label,\n  milestone, sort, project")
for line in vim.gsplit(bad.hint, "\n", { plain = true }) do
	assert_eq("a hint row fits a narrow list: " .. line, #line <= 46, true)
end
assert_eq("no params on error", bad.params, nil)

io.write("\n--- project ---\n")
assert_eq("project is not a parameter", query.parse("project:platform/billing/core", "mr").params.project, nil)
assert_eq("project is returned", query.parse("project:platform/billing/core", "mr").project, "platform/billing/core")
assert_eq("scope defaults to the current project", query.scope("state:opened ", "o/n"), "o/n")
assert_eq("scope follows project:", query.scope("project:a/b/c state:opened", "o/n"), "a/b/c")
assert_eq("scope ignores a bare word", query.scope("project", "o/n"), "o/n")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
