local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-github-source.md Phase 1: pre-flight checks, normalizing search
-- results, classifying failures, and the argv handed to `gh`. vim.system is stubbed in the child.

local SYSTEM = function(code, stdout, stderr)
	return { code = code, stdout = stdout or "", stderr = stderr or "" }
end

---A raw search/issues element; `extra` is merged over it.
---@param extra? table
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

t.describe("finder gh api", function()
	t.before_each(function()
		h.clear()
		gh.install({ bare = true })
		n.exec_lua(function()
			_G.api = require("beast.libs.finder.source.gh.api")
			---Start an api call with `start(cb)` and wait for its callback; returns what it delivered.
			_G.await = function(start)
				local got
				local handle = start(function(r)
					got = r
				end)
				vim.wait(500, function()
					return got ~= nil
				end, 5)
				return got, handle
			end
		end)
	end)

	---`api.parse(res)` in the child.
	---@param res vim.SystemCompleted
	local function parse(res)
		return n.exec_lua(function(r)
			return _G.api.parse(r, "github.com")
		end, res)
	end

	---`api.normalize(raw)` in the child.
	---@param item table
	local function normalize(item)
		return n.exec_lua(function(r)
			return _G.api.normalize(r, "github.com")
		end, item)
	end

	t.describe("check (pre-flight)", function()
		---Run `api.check("/x")`; returns slug, host and the error message.
		local function check()
			return n.exec_lua(function()
				local repo, err = _G.api.check("/x")
				return { slug = repo and repo.slug, host = repo and repo.host, err = err }
			end)
		end

		t.it("reports a missing gh", function()
			n.exec_lua(function()
				vim.fn.executable = function()
					return 0
				end
			end)
			t.eq({ err = "GitHub CLI (gh) is not installed" }, check())
		end)

		t.it("reports a missing remote", function()
			gh.set({ ["git -C /x config --get-regexp"] = SYSTEM(1) })
			t.eq({ err = "No GitHub remote found for this directory" }, check())
		end)

		t.it("reports not being logged in", function()
			gh.set({
				["git -C /x config --get-regexp"] = gh.ok("remote.origin.url git@github.com:o/n.git\n"),
				["gh auth token --hostname github.com"] = SYSTEM(1, "", "no oauth token"),
			})
			t.eq({ err = "Run `gh auth login` first" }, check())
		end)

		t.it("does not treat an unknown host as a GitHub remote", function()
			gh.set({
				["git -C /x config --get-regexp"] = gh.ok("remote.origin.url git@git.acme.dev:o/n.git\n"),
				["gh auth token --hostname git.acme.dev"] = SYSTEM(1, "", "no oauth token"),
			})
			t.eq({ err = "No GitHub remote found for this directory" }, check())
		end)

		t.it("returns the slug and host when all is well", function()
			gh.set({
				["git -C /x config --get-regexp"] = gh.ok("remote.origin.url git@github.com:o/n.git\n"),
				["gh auth token --hostname github.com"] = gh.ok("gho_x\n"),
			})
			t.eq({ slug = "o/n", host = "github.com" }, check())
		end)
	end)

	t.describe("normalize", function()
		t.it("turns a search hit with pull_request into a pr", function()
			local pr = normalize(raw({ pull_request = { url = "x" } }))
			t.eq("pr", pr.kind)
			t.eq("open", pr.state)
			t.eq("o/n", pr.repo)
			t.eq("loctvl842", pr.author)
			t.eq("https://github.com/o/n/pull/30", pr.url)
			t.eq("d73a4a", pr.labels[1].color)
			t.eq("#30 feat(cli): nodes", pr.text)
			t.eq(3, pr.comments)
		end)

		t.it("marks a draft pr", function()
			t.eq("draft", normalize(raw({ pull_request = {}, draft = true })).state)
		end)

		t.it("marks a merged pr", function()
			t.eq("merged", normalize(raw({ pull_request = { merged_at = "2026-11-02T00:00:00Z" }, state = "closed" })).state)
		end)

		t.it("marks a closed unmerged pr", function()
			t.eq("closed", normalize(raw({ pull_request = {}, state = "closed" })).state)
		end)

		t.it("marks a draft that is closed as closed", function()
			t.eq("closed", normalize(raw({ pull_request = {}, draft = true, state = "closed" })).state)
		end)

		t.it("turns a hit without pull_request into an issue", function()
			local issue = normalize(raw({ state = "open" }))
			t.eq({ "issue", "open" }, { issue.kind, issue.state })
		end)

		t.it("marks a completed closed issue as closed", function()
			t.eq("closed", normalize(raw({ state = "closed", state_reason = "completed" })).state)
		end)

		t.it("marks a not planned issue", function()
			t.eq("not_planned", normalize(raw({ state = "closed", state_reason = "not_planned" })).state)
		end)

		t.it("gives no labels as an empty list", function()
			t.eq(0, #normalize(raw({ labels = {} })).labels)
		end)
	end)

	t.describe("parse", function()
		local body = vim.json.encode({
			total_count = 250,
			items = { raw({ pull_request = {}, milestone = vim.NIL }), raw({ number = 31 }) },
		})

		t.it("keeps the items and the total, null fields do not break", function()
			local parsed = parse(gh.ok(body))
			t.eq(2, #parsed.items)
			t.eq(250, parsed.total)
			t.eq("pr", parsed.items[1].kind)
		end)

		t.it("gives an empty result", function()
			t.eq(0, #parse(gh.ok(vim.json.encode({ total_count = 0, items = {} }))).items)
		end)

		t.it("treats a garbage body as an error", function()
			t.eq("other", parse(gh.ok("<html>")).error.kind)
		end)

		t.it("classifies a 422 for a missing repo as not_found", function()
			local err = parse(SYSTEM(
				1,
				vim.json.encode({
					message = "Validation Failed",
					errors = {
						{
							message = "The listed users and repositories cannot be searched either because the resources do not exist or you do not have permission to view them.",
						},
					},
				}),
				"gh: Validation Failed (HTTP 422)"
			)).error
			t.eq({ "not_found", "repository not found or no access to it" }, { err.kind, err.message })
		end)

		t.it("keeps the API text of any other 422", function()
			t.eq(
				"The search is longer than 256 characters.",
				parse(
					SYSTEM(1, vim.json.encode({ errors = { { message = "The search is longer than 256 characters." } } }), "gh: Validation Failed (HTTP 422)")
				).error.message
			)
		end)

		t.it("classifies a 403 rate limit", function()
			t.eq(
				"rate_limit",
				parse(SYSTEM(1, vim.json.encode({ message = "API rate limit exceeded for user" }), "gh: API rate limit exceeded (HTTP 403)")).error.kind
			)
		end)

		t.it("classifies a 429 as rate limit", function()
			t.eq("rate_limit", parse(SYSTEM(1, "", "gh: Too Many Requests (HTTP 429)")).error.kind)
		end)

		t.it("does not treat a plain 403 as a rate limit", function()
			t.eq("other", parse(SYSTEM(1, "", "gh: Forbidden (HTTP 403)")).error.kind)
		end)

		t.it("classifies a 401 as auth", function()
			t.eq("auth", parse(SYSTEM(1, "", "gh: Bad credentials (HTTP 401)")).error.kind)
		end)

		t.it("classifies the login hint as auth", function()
			t.eq("auth", parse(SYSTEM(4, "", "To get started with GitHub CLI, please run:  gh auth login")).error.kind)
		end)

		t.it("classifies a connect failure as network", function()
			t.eq("network", parse(SYSTEM(1, "", "error connecting to api.github.com")).error.kind)
		end)

		t.it("shows the first stderr line of an unknown failure", function()
			t.eq("boom", parse(SYSTEM(1, "", "boom\nsecond")).error.message)
		end)

		t.it("shows the exit code of a silent failure", function()
			t.eq("gh exited with code 7", parse(SYSTEM(7)).error.message)
		end)
	end)

	t.describe("search", function()
		local body = vim.json.encode({
			total_count = 250,
			items = { raw({ pull_request = {}, milestone = vim.NIL }), raw({ number = 31 }) },
		})

		---Run `api.search(q)` in the child and wait for the callback.
		local function search(q)
			return n.exec_lua(function(query)
				local got, handle = _G.await(function(cb)
					return _G.api.search(query, "github.com", cb)
				end)
				_G.handle = handle
				return got
			end, q)
		end

		t.it("runs gh api GET search/issues with the query as one argument, the cap and the host", function()
			gh.set({ ["gh api -X GET search/issues"] = gh.ok(body) })
			local got = search("is:pr repo:o/n sort:created-desc")
			local argv = table.concat(gh.argvs()[1], "\0")
			t.eq(true, argv:find("gh\0api\0-X\0GET\0search/issues", 1, true) ~= nil)
			t.eq(true, argv:find("q=is:pr repo:o/n sort:created-desc", 1, true) ~= nil)
			t.eq(true, argv:find("per_page=100", 1, true) ~= nil)
			t.eq(true, argv:find("--hostname\0github.com", 1, true) ~= nil)
			t.eq(2, #got.items)
		end)

		t.it("lets the handle kill reach the process", function()
			gh.set({ ["gh api -X GET search/issues"] = gh.ok(body) })
			search("x")
			n.exec_lua(function()
				_G.handle.kill()
			end)
			t.eq(1, gh.killed())
		end)

		t.it("says when a rate limit resets", function()
			gh.set({
				["gh api -X GET search/issues"] = SYSTEM(1, "", "gh: API rate limit exceeded (HTTP 403)"),
				["gh api rate_limit"] = gh.ok(tostring(os.time() + 42) .. "\n"),
			})
			local err = search("x").error
			t.eq("rate_limit", err.kind)
			t.matches("resets in %d+s$", err.message)
		end)

		t.it("still reports a rate limit without the reset hint", function()
			gh.set({
				["gh api -X GET search/issues"] = SYSTEM(1, "", "gh: API rate limit exceeded (HTTP 403)"),
				["gh api rate_limit"] = SYSTEM(1, "", "x"),
			})
			t.eq("GitHub search rate limit reached", search("x").error.message)
		end)
	end)

	t.describe("detail", function()
		local pr_raw = {
			body = "Highlight other occurrences",
			baseRefName = "main",
			headRefName = "feat/x",
			additions = 97,
			deletions = 6,
			changedFiles = 7,
			mergeable = "MERGEABLE",
			mergedAt = "2026-08-08T10:29:43Z",
			closedAt = "2026-08-08T10:29:44Z",
			statusCheckRollup = {
				{ __typename = "CheckRun", status = "COMPLETED", conclusion = "SUCCESS" },
				{ __typename = "CheckRun", status = "COMPLETED", conclusion = "SKIPPED" },
				{ __typename = "CheckRun", status = "COMPLETED", conclusion = "FAILURE" },
				{ __typename = "CheckRun", status = "IN_PROGRESS", conclusion = "" },
				{ __typename = "StatusContext", state = "SUCCESS" },
				{ __typename = "StatusContext", state = "PENDING" },
			},
			comments = {
				{ author = { login = "sam" }, body = "second", createdAt = "2026-08-09T00:00:00Z" },
			},
			reviews = {
				{ author = { login = "dana" }, body = "", state = "APPROVED", submittedAt = "2026-08-08T12:00:00Z" },
				{ author = { login = "bot" }, body = "", state = "COMMENTED", submittedAt = "2026-08-08T11:00:00Z" },
				{ author = { login = "lee" }, body = "see inline", state = "COMMENTED", submittedAt = "2026-08-08T13:00:00Z" },
			},
		}
		local item = { kind = "pr", number = 30, host = "github.com", repo = "o/n" }

		---`api.normalize_detail("pr", pr_raw)` summarised in the child.
		local function normalized()
			return n.exec_lua(function(r)
				local d = _G.api.normalize_detail("pr", r)
				return {
					body = d.body,
					branches = d.base .. "<-" .. d.head,
					changes = d.files .. "/" .. d.additions .. "/" .. d.deletions,
					mergeable = d.mergeable,
					merged_closed = d.merged .. "|" .. d.closed,
					checks = { passed = d.checks.passed, failed = d.checks.failed, pending = d.checks.pending },
					conversation_len = #d.conversation,
					authors = d.conversation[1].author .. d.conversation[2].author .. d.conversation[3].author,
					first_state = d.conversation[1].state,
					second_has_state = d.conversation[2].state ~= nil,
					third_has_state = d.conversation[3].state ~= nil,
				}
			end, pr_raw)
		end

		t.it("normalizes the body, branches, changes and merge state", function()
			local d = normalized()
			t.eq("Highlight other occurrences", d.body)
			t.eq("main<-feat/x", d.branches)
			t.eq("7/97/6", d.changes)
			t.eq("MERGEABLE", d.mergeable)
			t.eq("2026-08-08T10:29:43Z|2026-08-08T10:29:44Z", d.merged_closed)
		end)

		t.it("counts checks: passed (success, skipped, status success), failed, pending", function()
			t.eq({ passed = 3, failed = 1, pending = 2 }, normalized().checks)
		end)

		t.it("drops an empty plain review and orders the conversation oldest first", function()
			local d = normalized()
			t.eq(3, d.conversation_len)
			t.eq("danaleesam", d.authors)
		end)

		t.it("keeps the verdict for approvals only", function()
			local d = normalized()
			t.eq("APPROVED", d.first_state)
			t.eq(false, d.second_has_state) -- a plain review with text has no verdict
			t.eq(false, d.third_has_state) -- a comment has no verdict
		end)

		t.it("defaults missing fields", function()
			t.eq(
				"|0|0|0",
				n.exec_lua(function()
					local bare = _G.api.normalize_detail("issue", {})
					return bare.body .. "|" .. bare.files .. "|" .. #bare.conversation .. "|" .. bare.checks.passed
				end)
			)
		end)

		---Run `api.detail(item)` in the child and wait; stores the handle.
		local function detail(it)
			return n.exec_lua(function(i)
				local got, handle = _G.await(function(cb)
					return _G.api.detail(i, cb)
				end)
				_G.handle = handle
				return got
			end, it)
		end

		t.it("runs gh pr view for host/owner/name with the pr fields", function()
			gh.set({ ["gh pr view 30"] = gh.json(pr_raw) })
			local got = detail(item)
			local argv = table.concat(gh.argvs()[1], "\0")
			t.eq(true, argv:find("gh\0pr\0view\0" .. "30", 1, true) ~= nil)
			t.eq(true, argv:find("--repo\0github.com/o/n", 1, true) ~= nil)
			t.eq(true, argv:find("statusCheckRollup", 1, true) ~= nil)
			t.eq("main", got.detail.base)
		end)

		t.it("runs gh issue view without the PR-only fields", function()
			gh.set({ ["gh issue view 41"] = gh.json({ body = "x", comments = {} }) })
			detail({ kind = "issue", number = 41, host = "github.com", repo = "o/n" })
			local argv = table.concat(gh.argvs()[1], "\0")
			t.eq(true, argv:find("gh\0issue\0view\0" .. "41", 1, true) ~= nil)
			t.eq(true, argv:find("statusCheckRollup", 1, true) == nil)
		end)

		t.it("carries the first stderr line of a failure", function()
			gh.set({ ["gh pr view 30"] = SYSTEM(1, "", "GraphQL: Could not resolve to a PullRequest\nmore") })
			t.eq("GraphQL: Could not resolve to a PullRequest", detail(item).error)
		end)

		t.it("treats garbage output as an error and lets kill reach the process", function()
			gh.set({ ["gh pr view 30"] = gh.ok("not json") })
			t.eq("unexpected response from GitHub", detail(item).error)
			n.exec_lua(function()
				_G.handle.kill()
			end)
			t.eq(1, gh.killed())
		end)
	end)
end)
