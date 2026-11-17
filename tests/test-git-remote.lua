-- =========================================================================
-- Test: git remote providers
-- =========================================================================
-- Covers docs/dev-specs/git-remote.md Phase 1: URL parsing, host to provider
-- classification, per-root remote cache, providers() / has_provider() /
-- remote(). vim.system is stubbed, nothing touches a real repository.
--
-- Run as: nvim --clean --headless -l tests/test-git-remote.lua
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
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

_G.Util = {
	root = function()
		return "/proj"
	end,
}

local config = require("beast.libs.git.config")
local remote = require("beast.libs.git.remote")

-- vim.system stub: scripted `git config --get-regexp` output per root
local orig_system = vim.system
local spawns = 0
local scripts = {} ---@type table<string, vim.SystemCompleted>

---@diagnostic disable-next-line: duplicate-set-field
vim.system = function(cmd)
	spawns = spawns + 1
	local res = scripts[cmd[3]] or { code = 1, stdout = "", stderr = "not a repo" }
	return {
		wait = function()
			return res
		end,
	}
end

local function lines(...)
	return { code = 0, stdout = table.concat({ ... }, "\n") .. "\n", stderr = "" }
end

-- ---------------------------------------------------------------------------
-- parse
-- ---------------------------------------------------------------------------
local function parsed(url)
	local r = remote.parse(url)
	return r and (r.host .. "|" .. r.slug) or nil
end

assert_eq("https remote", parsed("https://github.com/loctvl842/BeastVim"), "github.com|loctvl842/BeastVim")
assert_eq("https remote with .git and newline", parsed("https://github.com/loctvl842/BeastVim.git\n"), "github.com|loctvl842/BeastVim")
assert_eq("https remote with user", parsed("https://me@github.com/o/n.git"), "github.com|o/n")
assert_eq("scp-like ssh remote", parsed("git@github.com:o/n.git"), "github.com|o/n")
assert_eq("ssh:// remote with port", parsed("ssh://git@ghe.corp.dev:2222/o/n.git"), "ghe.corp.dev|o/n")
assert_eq("enterprise https host", parsed("https://ghe.corp.dev/o/n"), "ghe.corp.dev|o/n")
assert_eq("nested path is rejected", parsed("https://git.acme.dev/group/sub/proj.git"), nil)
assert_eq("garbage is rejected", parsed("not a url"), nil)
assert_eq("empty is rejected", parsed(""), nil)

-- ---------------------------------------------------------------------------
-- provider_of
-- ---------------------------------------------------------------------------
assert_eq("github.com", remote.provider_of("github.com"), "github")
assert_eq("enterprise github host", remote.provider_of("github.acme.dev"), "github")
assert_eq("gitlab.com", remote.provider_of("gitlab.com"), "gitlab")
assert_eq("host match is case-insensitive", remote.provider_of("GitHub.com"), "github")
assert_eq("unknown host", remote.provider_of("git.acme.dev"), nil)
assert_eq("bitbucket is not a known provider", remote.provider_of("bitbucket.org"), nil)

-- ---------------------------------------------------------------------------
-- providers / has_provider / remote
-- ---------------------------------------------------------------------------
scripts["/proj"] =
	lines("remote.origin.url git@github.com:o/n.git", "remote.mirror.url https://gitlab.com/o/n.git", "remote.fork.url git@github.com:me/n.git")
remote.invalidate()
spawns = 0

assert_eq("providers lists each provider once, sorted", remote.providers(), { "github", "gitlab" })
assert_eq("has github", remote.has_provider("github"), true)
assert_eq("has gitlab", remote.has_provider("gitlab"), true)
assert_eq("no bitbucket", remote.has_provider("bitbucket"), false)
assert_eq("one spawn for three reads", spawns, 1)

local gh = remote.remote("github")
assert_eq("origin wins over another github remote", gh and gh.name, "origin")
assert_eq("remote host", gh and gh.host, "github.com")
assert_eq("remote slug", gh and gh.slug, "o/n")
assert_eq("remote of an absent provider", remote.remote("bitbucket"), nil)

-- invalidate forces a re-read
remote.invalidate("/proj")
remote.providers()
assert_eq("invalidate(root) re-spawns", spawns, 2)
remote.invalidate()
remote.providers()
assert_eq("invalidate() re-spawns", spawns, 3)

-- FocusGained drops the cache
vim.api.nvim_exec_autocmds("FocusGained", {})
remote.providers()
assert_eq("FocusGained re-spawns", spawns, 4)

-- explicit root, separate cache entry
scripts["/other"] = lines("remote.origin.url https://git.acme.dev/o/n.git")
assert_eq("unknown host has no provider", remote.providers("/other"), {})
assert_eq("other root does not leak into the default one", remote.providers(), { "github", "gitlab" })

-- non-repo / git failure
assert_eq("non-repo has no providers", remote.providers("/nowhere"), {})
assert_eq("non-repo has no remote", remote.remote("github", "/nowhere"), nil)

-- remote names may contain dots; unparsable URLs are skipped
scripts["/dots"] = lines("remote.my.fork.url git@github.com:me/n.git", "remote.junk.url not-a-url")
local dotted = remote.remote("github", "/dots")
assert_eq("dotted remote name", dotted and dotted.name, "my.fork")
assert_eq("junk url is skipped", #remote.list("/dots"), 1)

-- config.remote.hosts maps a custom host
config.setup({ remote = { hosts = { ["git.acme.dev"] = "github" } } })
assert_eq("custom host maps to its provider", remote.provider_of("git.acme.dev"), "github")
remote.invalidate()
assert_eq("custom host shows up in providers", remote.providers("/other"), { "github" })
config.setup({})

-- Git facade
vim.system = function(cmd)
	local res = scripts[cmd[3]] or { code = 1, stdout = "", stderr = "" }
	return {
		wait = function()
			return res
		end,
	}
end
remote.invalidate()
local git = require("beast.libs.git")
assert_eq("Git.providers()", git.providers("/proj"), { "github", "gitlab" })
assert_eq("Git.has_provider()", git.has_provider("gitlab", "/proj"), true)
local viaGit = git.remote("github", "/proj")
assert_eq("Git.remote()", viaGit and viaGit.slug, "o/n")

vim.system = orig_system

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
