local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/git-remote.md Phase 1: URL parsing, host to provider classification,
-- per-root remote cache, providers() / has_provider() / remote().
-- `git config --get-regexp` is stubbed in the child (scripted output per root), nothing touches a real repo.

t.describe("git remote providers", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			local rm = { spawns = 0, scripts = {} }
			vim.system = function(cmd)
				rm.spawns = rm.spawns + 1
				local res = rm.scripts[cmd[3]] or { code = 1, stdout = "", stderr = "not a repo" }
				return {
					wait = function()
						return res
					end,
				}
			end
			function rm.lines(...)
				return { code = 0, stdout = table.concat({ ... }, "\n") .. "\n", stderr = "" }
			end
			rm.remote = require("beast.libs.git.remote")
			rm.config = require("beast.libs.git.config")
			_G.rm = rm
		end)
	end)

	t.describe("parse", function()
		---@param url string
		---@return string?
		local function parsed(url)
			return n.exec_lua(function(u)
				local r = _G.rm.remote.parse(u)
				return r and (r.host .. "|" .. r.slug) or nil
			end, url)
		end

		t.it("https remote", function()
			t.eq("github.com|loctvl842/BeastVim", parsed("https://github.com/loctvl842/BeastVim"))
		end)
		t.it("https remote with .git and newline", function()
			t.eq("github.com|loctvl842/BeastVim", parsed("https://github.com/loctvl842/BeastVim.git\n"))
		end)
		t.it("https remote with user", function()
			t.eq("github.com|o/n", parsed("https://me@github.com/o/n.git"))
		end)
		t.it("scp-like ssh remote", function()
			t.eq("github.com|o/n", parsed("git@github.com:o/n.git"))
		end)
		t.it("ssh:// remote with port", function()
			t.eq("ghe.corp.dev|o/n", parsed("ssh://git@ghe.corp.dev:2222/o/n.git"))
		end)
		t.it("enterprise https host", function()
			t.eq("ghe.corp.dev|o/n", parsed("https://ghe.corp.dev/o/n"))
		end)
		t.it("nested group path", function()
			t.eq("git.acme.dev|group/sub/proj", parsed("https://git.acme.dev/group/sub/proj.git"))
		end)
		t.it("nested group path over scp-like ssh", function()
			t.eq("git.acme.dev|a/b/c/d", parsed("git@git.acme.dev:a/b/c/d.git"))
		end)
		t.it("nested group path over ssh:// with port", function()
			t.eq("host|g/sub/p", parsed("ssh://git@host:2222/g/sub/p.git"))
		end)
		t.it("nested group path with token in the url", function()
			t.eq("gitlab.acme.dev|platform/payments/api", parsed("https://oauth2:tok@gitlab.acme.dev/platform/payments/api.git"))
		end)
		t.it("single segment is rejected", function()
			t.eq(nil, parsed("https://github.com/only"))
		end)
		t.it("garbage is rejected", function()
			t.eq(nil, parsed("not a url"))
		end)
		t.it("empty is rejected", function()
			t.eq(nil, parsed(""))
		end)
	end)

	t.describe("provider_of", function()
		---@param host string
		---@return string?
		local function provider_of(host)
			return n.exec_lua(function(hs)
				return _G.rm.remote.provider_of(hs)
			end, host)
		end

		t.it("github.com", function()
			t.eq("github", provider_of("github.com"))
		end)
		t.it("enterprise github host", function()
			t.eq("github", provider_of("github.acme.dev"))
		end)
		t.it("gitlab.com", function()
			t.eq("gitlab", provider_of("gitlab.com"))
		end)
		t.it("host match is case-insensitive", function()
			t.eq("github", provider_of("GitHub.com"))
		end)
		t.it("unknown host", function()
			t.eq(nil, provider_of("git.acme.dev"))
		end)
		t.it("bitbucket is not a known provider", function()
			t.eq(nil, provider_of("bitbucket.org"))
		end)
	end)

	t.describe("providers / has_provider / remote", function()
		-- Scripts the default root (whatever Util.root() resolves to) with three remotes.
		t.before_each(function()
			n.exec_lua(function()
				local rm = _G.rm
				rm.root = Util.root()
				rm.scripts[rm.root] = rm.lines(
					"remote.origin.url git@github.com:o/n.git",
					"remote.mirror.url https://gitlab.com/o/n.git",
					"remote.fork.url git@github.com:me/n.git"
				)
				rm.remote.invalidate()
				rm.spawns = 0
			end)
		end)

		t.it("providers lists each provider once, sorted", function()
			t.eq(
				{ "github", "gitlab" },
				n.exec_lua(function()
					return _G.rm.remote.providers()
				end)
			)
		end)

		t.it("has_provider answers per provider, with one spawn for three reads", function()
			t.eq(
				{ true, true, false, 1 },
				n.exec_lua(function()
					local r = _G.rm.remote
					return { r.has_provider("github"), r.has_provider("gitlab"), r.has_provider("bitbucket"), _G.rm.spawns }
				end)
			)
		end)

		t.it("origin wins over another github remote", function()
			t.eq(
				{ "origin", "github.com", "o/n" },
				n.exec_lua(function()
					local gh = _G.rm.remote.remote("github")
					return { gh.name, gh.host, gh.slug }
				end)
			)
		end)

		t.it("remote of an absent provider is nil", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.rm.remote.remote("bitbucket") == nil
				end)
			)
		end)

		t.it("invalidate(root) re-spawns", function()
			t.eq(
				{ 1, 2 },
				n.exec_lua(function()
					local rm = _G.rm
					rm.remote.providers()
					local first = rm.spawns
					rm.remote.invalidate(rm.root)
					rm.remote.providers()
					return { first, rm.spawns }
				end)
			)
		end)

		t.it("invalidate() re-spawns", function()
			t.eq(
				{ 1, 2 },
				n.exec_lua(function()
					local rm = _G.rm
					rm.remote.providers()
					local first = rm.spawns
					rm.remote.invalidate()
					rm.remote.providers()
					return { first, rm.spawns }
				end)
			)
		end)

		t.it("FocusGained drops the cache", function()
			t.eq(
				{ 1, 2 },
				n.exec_lua(function()
					local rm = _G.rm
					rm.remote.providers()
					local first = rm.spawns
					vim.api.nvim_exec_autocmds("FocusGained", {})
					rm.remote.providers()
					return { first, rm.spawns }
				end)
			)
		end)

		t.it("an explicit root has its own cache entry", function()
			t.eq(
				{ {}, { "github", "gitlab" } },
				n.exec_lua(function()
					local rm = _G.rm
					rm.scripts["/other"] = rm.lines("remote.origin.url https://git.acme.dev/o/n.git")
					return { rm.remote.providers("/other"), rm.remote.providers() }
				end)
			)
		end)

		t.it("a non-repo has no providers and no remote", function()
			t.eq(
				{ {}, true },
				n.exec_lua(function()
					local r = _G.rm.remote
					return { r.providers("/nowhere"), r.remote("github", "/nowhere") == nil }
				end)
			)
		end)

		t.it("remote names may contain dots, and unparsable URLs are skipped", function()
			t.eq(
				{ "my.fork", 1 },
				n.exec_lua(function()
					local rm = _G.rm
					rm.scripts["/dots"] = rm.lines("remote.my.fork.url git@github.com:me/n.git", "remote.junk.url not-a-url")
					return { rm.remote.remote("github", "/dots").name, #rm.remote.list("/dots") }
				end)
			)
		end)

		t.it("config.remote.hosts maps a custom host", function()
			t.eq(
				{ "github", { "github" } },
				n.exec_lua(function()
					local rm = _G.rm
					rm.scripts["/other"] = rm.lines("remote.origin.url https://git.acme.dev/o/n.git")
					rm.config.setup({ remote = { hosts = { ["git.acme.dev"] = "github" } } })
					local provider = rm.remote.provider_of("git.acme.dev")
					rm.remote.invalidate()
					return { provider, rm.remote.providers("/other") }
				end)
			)
		end)
	end)

	t.describe("Git facade", function()
		t.before_each(function()
			n.exec_lua(function()
				local rm = _G.rm
				rm.scripts["/proj"] = rm.lines(
					"remote.origin.url git@github.com:o/n.git",
					"remote.mirror.url https://gitlab.com/o/n.git",
					"remote.fork.url git@github.com:me/n.git"
				)
				rm.remote.invalidate()
			end)
		end)

		t.it("Git.providers()", function()
			t.eq(
				{ "github", "gitlab" },
				n.exec_lua(function()
					return require("beast.libs.git").providers("/proj")
				end)
			)
		end)
		t.it("Git.has_provider()", function()
			t.eq(
				true,
				n.exec_lua(function()
					return require("beast.libs.git").has_provider("gitlab", "/proj")
				end)
			)
		end)
		t.it("Git.remote()", function()
			t.eq(
				"o/n",
				n.exec_lua(function()
					return require("beast.libs.git").remote("github", "/proj").slug
				end)
			)
		end)
	end)
end)
