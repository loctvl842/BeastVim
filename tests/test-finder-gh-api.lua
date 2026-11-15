-- =========================================================================
-- Test: GitHub finder source API wrapper
-- =========================================================================
-- Covers docs/dev-specs/finder-github-source.md Phase 1: remote parsing,
-- pre-flight checks, normalizing search results, classifying failures,
-- and the argv handed to `gh`. vim.system is stubbed, nothing hits the network.
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-api.lua
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

local api = require("beast.libs.finder.source.gh.api")

-- ---------------------------------------------------------------------------
-- vim.system stub: scripted responses keyed by a prefix of the argv
-- ---------------------------------------------------------------------------
local orig_system = vim.system
local orig_executable = vim.fn.executable
local calls = {} ---@type string[][]
local script = {} ---@type table<string, vim.SystemCompleted>
local killed = 0

local function lookup(cmd)
	for prefix, res in pairs(script) do
		if table.concat(cmd, " "):sub(1, #prefix) == prefix then
			return res
		end
	end
	return { code = 1, stdout = "", stderr = "unscripted: " .. table.concat(cmd, " ") }
end

---@diagnostic disable-next-line: duplicate-set-field
vim.system = function(cmd, _, on_exit)
	calls[#calls + 1] = cmd
	local res = lookup(cmd)
	local obj = {
		wait = function()
			return res
		end,
		kill = function()
			killed = killed + 1
		end,
	}
	if on_exit then
		on_exit(res)
	end
	return obj
end

local function reset()
	calls, script, killed = {}, {}, 0
end

-- ---------------------------------------------------------------------------
-- parse_remote
-- ---------------------------------------------------------------------------
local function remote(url)
	local r = api.parse_remote(url)
	return r and (r.host .. "|" .. r.slug) or nil
end

assert_eq("https remote", remote("https://github.com/loctvl842/BeastVim"), "github.com|loctvl842/BeastVim")
assert_eq("https remote with .git and newline", remote("https://github.com/loctvl842/BeastVim.git\n"), "github.com|loctvl842/BeastVim")
assert_eq("https remote with user", remote("https://me@github.com/o/n.git"), "github.com|o/n")
assert_eq("scp-like ssh remote", remote("git@github.com:o/n.git"), "github.com|o/n")
assert_eq("ssh:// remote with port", remote("ssh://git@ghe.corp.dev:2222/o/n.git"), "ghe.corp.dev|o/n")
assert_eq("enterprise https host", remote("https://ghe.corp.dev/o/n"), "ghe.corp.dev|o/n")
assert_eq("nested path is rejected", remote("https://git.acme.dev/group/sub/proj.git"), nil)
assert_eq("garbage is rejected", remote("not a url"), nil)
assert_eq("empty is rejected", remote(""), nil)

-- ---------------------------------------------------------------------------
-- check (pre-flight)
-- ---------------------------------------------------------------------------
reset()
vim.fn.executable = function()
	return 0
end
local repo, err = api.check("/x")
assert_eq("no gh: no repo", repo, nil)
assert_eq("no gh: message", err, "GitHub CLI (gh) is not installed")

vim.fn.executable = function()
	return 1
end
script["git -C /x remote get-url origin"] = { code = 2, stdout = "", stderr = "fatal" }
repo, err = api.check("/x")
assert_eq("no remote: message", err, "No GitHub remote found for this directory")

reset()
script["git -C /x remote get-url origin"] = { code = 0, stdout = "git@github.com:o/n.git\n", stderr = "" }
script["gh auth token --hostname github.com"] = { code = 1, stdout = "", stderr = "no oauth token" }
repo, err = api.check("/x")
assert_eq("not logged in: message", err, "Run `gh auth login` first")

reset()
script["git -C /x remote get-url origin"] = { code = 0, stdout = "git@git.acme.dev:o/n.git\n", stderr = "" }
script["gh auth token --hostname git.acme.dev"] = { code = 1, stdout = "", stderr = "no oauth token" }
repo, err = api.check("/x")
assert_eq("unknown host is not a GitHub remote", err, "No GitHub remote found for this directory")

reset()
script["git -C /x remote get-url origin"] = { code = 0, stdout = "git@github.com:o/n.git\n", stderr = "" }
script["gh auth token --hostname github.com"] = { code = 0, stdout = "gho_x\n", stderr = "" }
repo, err = api.check("/x")
assert_eq("ok: slug", repo and repo.slug, "o/n")
assert_eq("ok: host", repo and repo.host, "github.com")
assert_eq("ok: no error", err, nil)

vim.fn.executable = orig_executable

-- ---------------------------------------------------------------------------
-- normalize
-- ---------------------------------------------------------------------------
local function raw(extra)
	return vim.tbl_extend("force", {
		number = 30,
		title = "feat(cli): nodes",
		state = "open",
		html_url = "https://github.com/o/n/pull/30",
		repository_url = "https://api.github.com/repos/o/n",
		user = { login = "loctvl842", type = "User" },
		labels = { { name = "bug", color = "d73a4a" } },
		created_at = "2026-11-01T00:00:00Z",
		updated_at = "2026-11-02T00:00:00Z",
		comments = 3,
	}, extra or {})
end

local pr = api.normalize(raw({ pull_request = { url = "x" } }), "github.com")
assert_eq("open pr kind", pr.kind, "pr")
assert_eq("open pr state", pr.state, "open")
assert_eq("repo from repository_url", pr.repo, "o/n")
assert_eq("author", pr.author, "loctvl842")
assert_eq("url", pr.url, "https://github.com/o/n/pull/30")
assert_eq("label color", pr.labels[1].color, "d73a4a")
assert_eq("text", pr.text, "#30 feat(cli): nodes")
assert_eq("comments", pr.comments, 3)
assert_eq("not a bot", pr.is_bot, false)

assert_eq("draft pr", api.normalize(raw({ pull_request = {}, draft = true }), "github.com").state, "draft")
assert_eq("merged pr", api.normalize(raw({ pull_request = { merged_at = "2026-11-02T00:00:00Z" }, state = "closed" }), "github.com").state, "merged")
assert_eq("closed unmerged pr", api.normalize(raw({ pull_request = {}, state = "closed" }), "github.com").state, "closed")
assert_eq("draft but closed is closed", api.normalize(raw({ pull_request = {}, draft = true, state = "closed" }), "github.com").state, "closed")

local issue = api.normalize(raw({ state = "open" }), "github.com")
assert_eq("issue kind", issue.kind, "issue")
assert_eq("open issue", issue.state, "open")
assert_eq("closed issue", api.normalize(raw({ state = "closed", state_reason = "completed" }), "github.com").state, "closed")
assert_eq("not planned issue", api.normalize(raw({ state = "closed", state_reason = "not_planned" }), "github.com").state, "not_planned")

local bot = api.normalize(raw({ user = { login = "dependabot[bot]", type = "Bot" } }), "github.com")
assert_eq("bot author flagged", bot.is_bot, true)
assert_eq("no labels is an empty list", #api.normalize(raw({ labels = {} }), "github.com").labels, 0)

-- ---------------------------------------------------------------------------
-- parse: success and failures
-- ---------------------------------------------------------------------------
local ok_body = vim.json.encode({
	total_count = 250,
	items = { raw({ pull_request = {}, milestone = vim.NIL }), raw({ number = 31 }) },
})
local parsed = api.parse({ code = 0, stdout = ok_body, stderr = "" }, "github.com")
assert_eq("two items", parsed.items and #parsed.items, 2)
assert_eq("total kept", parsed.total, 250)
assert_eq("null fields do not break", parsed.items[1].kind, "pr")

assert_eq("empty result", #api.parse({ code = 0, stdout = vim.json.encode({ total_count = 0, items = {} }), stderr = "" }, "github.com").items, 0)
assert_eq("garbage body is an error", api.parse({ code = 0, stdout = "<html>", stderr = "" }, "github.com").error.kind, "other")

local not_found = api.parse({
	code = 1,
	stdout = vim.json.encode({
		message = "Validation Failed",
		errors = {
			{
				message = "The listed users and repositories cannot be searched either because the resources do not exist or you do not have permission to view them.",
			},
		},
	}),
	stderr = "gh: Validation Failed (HTTP 422)",
}, "github.com")
assert_eq("422 repo not found kind", not_found.error.kind, "not_found")
assert_eq("422 repo not found message", not_found.error.message, "repository not found or no access to it")

assert_eq(
	"other 422 keeps API text",
	api.parse({
		code = 1,
		stdout = vim.json.encode({ errors = { { message = "The search is longer than 256 characters." } } }),
		stderr = "gh: Validation Failed (HTTP 422)",
	}, "github.com").error.message,
	"The search is longer than 256 characters."
)

assert_eq(
	"403 rate limit",
	api.parse(
		{ code = 1, stdout = vim.json.encode({ message = "API rate limit exceeded for user" }), stderr = "gh: API rate limit exceeded (HTTP 403)" },
		"github.com"
	).error.kind,
	"rate_limit"
)
assert_eq("429 rate limit", api.parse({ code = 1, stdout = "", stderr = "gh: Too Many Requests (HTTP 429)" }, "github.com").error.kind, "rate_limit")
assert_eq(
	"plain 403 is not a rate limit",
	api.parse({ code = 1, stdout = "", stderr = "gh: Forbidden (HTTP 403)" }, "github.com").error.kind,
	"other"
)
assert_eq("401 is auth", api.parse({ code = 1, stdout = "", stderr = "gh: Bad credentials (HTTP 401)" }, "github.com").error.kind, "auth")
assert_eq(
	"login hint is auth",
	api.parse({ code = 4, stdout = "", stderr = "To get started with GitHub CLI, please run:  gh auth login" }, "github.com").error.kind,
	"auth"
)
assert_eq(
	"connect failure is network",
	api.parse({ code = 1, stdout = "", stderr = "error connecting to api.github.com" }, "github.com").error.kind,
	"network"
)
assert_eq(
	"unknown failure shows first stderr line",
	api.parse({ code = 1, stdout = "", stderr = "boom\nsecond" }, "github.com").error.message,
	"boom"
)
assert_eq("silent failure shows exit code", api.parse({ code = 7, stdout = "", stderr = "" }, "github.com").error.message, "gh exited with code 7")

-- ---------------------------------------------------------------------------
-- search: argv, callback, kill, rate-limit hint
-- ---------------------------------------------------------------------------
local function wait_for(fn)
	vim.wait(500, fn, 5)
end

reset()
script["gh api -X GET search/issues"] = { code = 0, stdout = ok_body, stderr = "" }
local got
local handle = api.search("is:pr repo:o/n sort:created-desc", "github.com", function(r)
	got = r
end)
wait_for(function()
	return got ~= nil
end)
local argv = table.concat(calls[1], "\0")
assert_test("search uses gh api GET search/issues", argv:find("gh\0api\0-X\0GET\0search/issues", 1, true) ~= nil, vim.inspect(calls[1]))
assert_test("query passed as one argv element", argv:find("q=is:pr repo:o/n sort:created-desc", 1, true) ~= nil, vim.inspect(calls[1]))
assert_test("per_page is the cap", argv:find("per_page=100", 1, true) ~= nil, vim.inspect(calls[1]))
assert_test("host passed", argv:find("--hostname\0github.com", 1, true) ~= nil, vim.inspect(calls[1]))
assert_eq("search result delivered", got and #got.items, 2)

handle.kill()
assert_eq("kill reaches the process", killed, 1)

reset()
script["gh api -X GET search/issues"] = { code = 1, stdout = "", stderr = "gh: API rate limit exceeded (HTTP 403)" }
script["gh api rate_limit"] = { code = 0, stdout = tostring(os.time() + 42) .. "\n", stderr = "" }
got = nil
api.search("x", "github.com", function(r)
	got = r
end)
wait_for(function()
	return got ~= nil
end)
assert_eq("rate limit kind", got and got.error and got.error.kind, "rate_limit")
assert_test(
	"rate limit message says when it resets",
	got and got.error and got.error.message:match("resets in %d+s$") ~= nil,
	vim.inspect(got and got.error)
)

reset()
script["gh api -X GET search/issues"] = { code = 1, stdout = "", stderr = "gh: API rate limit exceeded (HTTP 403)" }
script["gh api rate_limit"] = { code = 1, stdout = "", stderr = "x" }
got = nil
api.search("x", "github.com", function(r)
	got = r
end)
wait_for(function()
	return got ~= nil
end)
assert_eq("rate limit without hint still reported", got and got.error and got.error.message, "GitHub search rate limit reached")

vim.system = orig_system

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
