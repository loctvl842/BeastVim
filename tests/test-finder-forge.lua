-- =========================================================================
-- Test: forge helper (which code host an item belongs to)
-- =========================================================================
-- Covers docs/dev-specs/finder-gitlab-source.md Phase 2: an item without
-- `provider` is GitHub's; the api module, names and references follow it.
--
-- Run as: nvim --clean --headless -l tests/test-finder-forge.lua
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

local forge = require("beast.libs.finder.source.forge")
local gh_item = { number = 7 }
local gl_item = { provider = "gitlab", number = 7, ref = "!7" }

assert_eq("no provider is GitHub's api", forge.api(gh_item), require("beast.libs.finder.source.gh.api"))
assert_eq("github name", forge.name(gh_item), "GitHub")
assert_eq("gitlab name", forge.name(gl_item), "GitLab")
assert_eq("ref falls back to #number", forge.ref(gh_item), "#7")
assert_eq("ref is the item's own", forge.ref(gl_item), "!7")
assert_eq("PR", forge.review(gh_item), "PR")
assert_eq("MR", forge.review(gl_item), "MR")
assert_eq("Repo", forge.project(gh_item), "Repo")
assert_eq("Project", forge.project(gl_item), "Project")
assert_eq("pr_label says MR for GitLab", require("beast.libs.finder.format").pr_label({ provider = "gitlab", title = "t" }), "MR t")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
