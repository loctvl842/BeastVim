-- =========================================================================
-- Test: GitHub finder source query builder
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 1: the prompt text is
-- sent as-is, plus the current repo as scope and newest-first order unless
-- the user already said otherwise.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-query.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local query = require("beast.libs.finder.source.gh.query")
local REPO = "loctvl842/jarvix"

assert_eq("default text pr", query.default_text("pr"), "is:pr state:open ")
assert_eq("default text issue", query.default_text("issue"), "is:issue state:open ")

assert_eq(
	"default pr text gets repo and sort",
	query.build(query.default_text("pr"), REPO),
	"is:pr state:open repo:loctvl842/jarvix sort:created-desc"
)
assert_eq("empty text still scoped and sorted", query.build("", REPO), "repo:loctvl842/jarvix sort:created-desc")
assert_eq("words are kept", query.build("is:pr hub fix", REPO), "is:pr hub fix repo:loctvl842/jarvix sort:created-desc")

assert_eq("own repo: wins", query.build("repo:neovim/neovim is:issue", REPO), "repo:neovim/neovim is:issue sort:created-desc")
assert_eq("org: counts as scope", query.build("org:neovim is:pr", REPO), "org:neovim is:pr sort:created-desc")
assert_eq("user: counts as scope", query.build("user:tjdevries is:pr", REPO), "user:tjdevries is:pr sort:created-desc")
assert_eq("negated repo is not a scope", query.build("-repo:foo/bar is:pr", REPO), "-repo:foo/bar is:pr repo:loctvl842/jarvix sort:created-desc")

assert_eq("qualifier keys are case-insensitive", query.build("Repo:a/b SORT:updated-asc", REPO), "Repo:a/b SORT:updated-asc")
assert_eq("own sort: wins", query.build("is:pr sort:updated-asc", REPO), "is:pr sort:updated-asc repo:loctvl842/jarvix")
assert_eq("both given", query.build("repo:a/b sort:comments-desc", REPO), "repo:a/b sort:comments-desc")

assert_eq(
	"quoted value with a space",
	query.build('is:pr label:"help wanted"', REPO),
	'is:pr label:"help wanted" repo:loctvl842/jarvix sort:created-desc'
)
assert_eq(
	"repo: inside quotes is not a qualifier",
	query.build('"fix repo:a/b" is:pr', REPO),
	'"fix repo:a/b" is:pr repo:loctvl842/jarvix sort:created-desc'
)
assert_eq("word containing colon mid-token is not a qualifier", query.build("foo:bar", REPO), "foo:bar repo:loctvl842/jarvix sort:created-desc")
assert_eq(
	"sort word inside text is not a qualifier",
	query.build("how to sort things", REPO),
	"how to sort things repo:loctvl842/jarvix sort:created-desc"
)
assert_eq("surrounding whitespace trimmed", query.build("  is:pr  ", REPO), "is:pr repo:loctvl842/jarvix sort:created-desc")

assert_eq("scope defaults to the repo", query.scope("is:pr state:open ", REPO), REPO)
assert_eq("scope follows repo:", query.scope("repo:neovim/neovim is:issue", REPO), "neovim/neovim")
assert_eq("scope follows org:", query.scope("is:pr org:neovim", REPO), "neovim")
assert_eq("empty value is not a scope", query.scope("repo: is:pr", REPO), REPO)
assert_eq("negated repo is not a scope for the title", query.scope("-repo:foo/bar", REPO), REPO)

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
