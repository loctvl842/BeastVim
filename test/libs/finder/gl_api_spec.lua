local gl = require("test.libs.finder.helpers.gl")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- `glab` wrapper for the GitLab finder sources (gl/api.lua): check(), argv of the list request (host,
-- encoded project path, parameters), --include parsing, totals, @me, normalization, error classes,
-- detail, user_exists. vim.system is scripted in the child (helpers/gl.lua); nothing runs `glab`.

local MR_LIST = gl.req("gitlab.com", "projects/o%2Fn/merge_requests")

---The last command the scripted `vim.system` was asked to run.
---@return string
local function last_call()
	local calls = gl.calls()
	return calls[#calls]
end

---@param haystack string
---@param needle string
---@return boolean
local function has(haystack, needle)
	return haystack:find(needle, 1, true) ~= nil
end

t.describe("finder gl api", function()
	t.before_each(function()
		h.clear()
		gl.install()
		n.exec_lua(function()
			_G.api = require("beast.libs.finder.source.gl.api")
		end)
	end)

	---`api.check("/x")` in the child.
	---@return { slug?: string, host?: string, err?: string }
	local function check()
		return n.exec_lua(function()
			local repo, err = _G.api.check("/x")
			return { slug = repo and repo.slug, host = repo and repo.host, err = err }
		end)
	end

	---Run one search in the child and wait for its answer.
	---@param kind "mr"|"issue"
	---@param project string
	---@param params table
	---@param host? string
	---@return { count?: integer, total?: integer, error?: table, items?: table[] }
	local function search(kind, project, params, host)
		return n.exec_lua(function(a)
			local result
			_G.api.search(a.kind, a.project, a.params, a.host or "gitlab.com", function(r)
				result = r
			end)
			vim.wait(500, function()
				return result ~= nil
			end)
			return { count = result.items and #result.items, total = result.total, error = result.error }
		end, { kind = kind, project = project, params = params, host = host })
	end

	t.describe("project_id", function()
		t.it("turns a slash into %2F", function()
			t.eq(
				"platform%2Fpayments%2Fapi",
				n.exec_lua(function()
					return _G.api.project_id("platform/payments/api")
				end)
			)
		end)
	end)

	t.describe("check", function()
		t.it("passes a gitlab.com remote", function()
			local r = check()
			t.eq("o/n", r.slug)
			t.eq(nil, r.err)
		end)

		t.it("asks for the login of the remote's host", function()
			check()
			t.eq("glab auth status --hostname gitlab.com", last_call())
		end)

		t.it("reports not being logged in, naming the host", function()
			gl.set({ ["glab auth status"] = gl.fail("not logged in") })
			local r = check()
			t.eq(nil, r.slug)
			t.eq("Run `glab auth login --hostname gitlab.com` first", r.err)
		end)

		t.it("does not take an unknown host for a gitlab remote, and names the setting", function()
			gl.install("git@git.acme.dev:platform/payments/api.git")
			local r = check()
			t.eq(nil, r.slug)
			t.eq("git.acme.dev is not known as a GitLab server. Add it to the git remote hosts setting.", r.err)
		end)

		t.it("finds no GitLab remote in a GitHub-only repo", function()
			gl.install("git@github.com:o/n.git")
			t.eq("No GitLab remote found for this directory", check().err)
		end)

		t.it("passes a self-hosted nested remote", function()
			gl.install("git@gitlab.acme.dev:platform/payments/api.git")
			local r = check()
			t.eq("gitlab.acme.dev|platform/payments/api", r.host .. "|" .. r.slug)
		end)

		t.it("checks the login of the self-hosted host", function()
			gl.install("git@gitlab.acme.dev:platform/payments/api.git")
			check()
			t.eq("glab auth status --hostname gitlab.acme.dev", last_call())
		end)

		t.it("reports a missing glab", function()
			n.exec_lua(function()
				vim.fn.executable = function()
					return 0
				end
			end)
			t.eq("GitLab CLI (glab) is not installed", check().err)
		end)
	end)

	t.describe("search: request", function()
		t.it("builds the argv: host, encoded project, sorted parameters, defaults", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(2, "Second"), gl.mr(1, "First") }, { ["X-Total"] = "2" }) })
			search("mr", "o/n", { state = "opened", search = "retry", labels = "bug,backend" })
			t.eq(
				MR_LIST
					.. " -f labels=bug,backend -f order_by=created_at -f per_page=100 -f search=retry -f sort=desc -f state=opened -f with_labels_details=true",
				last_call()
			)
		end)

		t.it("returns the items and the total from the header", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(2, "Second"), gl.mr(1, "First") }, { ["X-Total"] = "2" }) })
			local r = search("mr", "o/n", { state = "opened" })
			t.eq(2, r.count)
			t.eq(2, r.total)
		end)

		t.it("uses --hostname and the nested path on a self-hosted server", function()
			gl.install("git@git.acme.dev:platform/payments/api.git")
			gl.set({ [gl.req("git.acme.dev", "projects/platform%2Fpayments%2Fapi/issues")] = gl.http({}) })
			search("issue", "platform/payments/api", { state = "opened", ["in"] = "title,description" }, "git.acme.dev")
			t.eq(true, has(last_call(), "--hostname git.acme.dev --include projects/platform%2Fpayments%2Fapi/issues"))
		end)

		t.it("searches title and description of issues", function()
			gl.install("git@git.acme.dev:platform/payments/api.git")
			gl.set({ [gl.req("git.acme.dev", "projects/platform%2Fpayments%2Fapi/issues")] = gl.http({}) })
			search("issue", "platform/payments/api", { state = "opened", ["in"] = "title,description" }, "git.acme.dev")
			t.eq(true, has(last_call(), "-f in=title,description"))
		end)

		t.it("takes a next page without a total as more to come", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "t") }, { ["X-Next-Page"] = "2" }) })
			t.eq(2, search("mr", "o/n", { state = "opened" }).total)
		end)

		t.it("counts the items with no total and no next page", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "t") }, { ["X-Next-Page"] = "" }) })
			t.eq(1, search("mr", "o/n", { state = "opened" }).total)
		end)
	end)

	t.describe("search: @me", function()
		local USER = gl.req("gitlab.com", "user")

		t.before_each(function()
			gl.set({ [USER] = gl.http({ username = "loctvl842" }), [MR_LIST] = gl.http({}) })
		end)

		t.it("replaces @me with the logged-in user, in every flag", function()
			search("mr", "o/n", { state = "opened", author_username = "@me", assignee_username = "@me" })
			t.eq(true, has(last_call(), "-f author_username=loctvl842"))
			t.eq(true, has(last_call(), "-f assignee_username=loctvl842"))
		end)

		t.it("asks for the user once and remembers", function()
			search("mr", "o/n", { state = "opened", author_username = "@me", assignee_username = "@me" })
			t.eq(1, gl.count(USER))
			search("mr", "o/n", { author_username = "@me" })
			t.eq(1, gl.count(USER))
		end)

		t.it("makes a failing user lookup the search's error", function()
			gl.set({ [USER] = gl.http_error(401, "401 Unauthorized") })
			local result = search("mr", "o/n", { author_username = "@me" })
			t.eq("auth", result.error.kind)
		end)
	end)

	t.describe("normalize", function()
		---`api.normalize(kind, raw, host)` in the child.
		---@param kind "mr"|"issue"
		---@param raw table
		---@param host? string
		---@return table
		local function normalize(kind, raw, host)
			return n.exec_lua(function(a)
				return _G.api.normalize(a.kind, a.raw, a.host)
			end, { kind = kind, raw = raw, host = host or "h" })
		end

		local item

		t.before_each(function()
			item = normalize(
				"mr",
				gl.mr(412, "Retry", {
					draft = true,
					labels = { { name = "backend", color = "#428BCA" }, { name = "priority::high", color = "#ff8800" } },
					user_notes_count = 3,
					references = { full = "platform/payments/api!412" },
				}),
				"git.acme.dev"
			)
		end)

		t.it("sets the provider", function()
			t.eq("gitlab", item.provider)
		end)

		t.it("keeps the kind as pr", function()
			t.eq("pr", item.kind)
		end)

		t.it("sets the ref and the number", function()
			t.eq("!412", item.ref)
			t.eq(412, item.number)
		end)

		t.it("reads a draft", function()
			t.eq("draft", item.state)
		end)

		t.it("writes the text", function()
			t.eq("!412 Retry", item.text)
		end)

		t.it("takes the full project path as the repo, and the host", function()
			t.eq("platform/payments/api", item.repo)
			t.eq("git.acme.dev", item.host)
		end)

		t.it("takes the author, the comments and the url", function()
			t.eq("dao", item.author)
			t.eq(3, item.comments)
			t.eq("https://gitlab.com/o/n/-/merge_requests/412", item.url)
		end)

		t.it("drops the # of label colours", function()
			t.eq({ { name = "backend", color = "428BCA" }, { name = "priority::high", color = "ff8800" } }, item.labels)
		end)

		t.it("gives plain label names a grey", function()
			t.eq({ { name = "bug", color = "888888" } }, normalize("issue", gl.issue(1, "t", { labels = { "bug" } })).labels)
		end)

		for _, case in ipairs({
			{ "merged", "merged", "merged" },
			{ "closed", "closed", "closed" },
			{ "locked (reads as closed)", "locked", "closed" },
			{ "opened (reads as open)", "opened", "open" },
		}) do
			t.it("reads " .. case[1], function()
				t.eq(case[3], normalize("mr", gl.mr(1, "t", { state = case[2] })).state)
			end)
		end

		t.it("gives an issue its kind and ref", function()
			local issue = normalize("issue", gl.issue(207, "Bug"))
			t.eq("issue", issue.kind)
			t.eq("#207", issue.ref)
		end)

		t.it("never makes an issue a draft", function()
			t.eq("open", normalize("issue", gl.issue(1, "t", { draft = true })).state)
		end)

		t.it("keeps the issue body for the grep", function()
			t.eq("desc 207", normalize("issue", gl.issue(207, "Bug")).body)
		end)
	end)

	t.describe("search: errors", function()
		---@param res vim.SystemCompleted
		---@return table error
		local function failing(res)
			gl.set({ [MR_LIST] = res })
			return search("mr", "o/n", {}).error
		end

		t.it("classifies a 404", function()
			t.eq({ kind = "not_found", message = "project not found or no access to it" }, failing(gl.http_error(404, "404 Project Not Found")))
		end)

		t.it("names the host in the login hint of a 401", function()
			t.eq("GitLab login expired, run `glab auth login --hostname gitlab.com`", failing(gl.http_error(401, "401 Unauthorized")).message)
		end)

		t.it("classifies a 429 and says when it lifts", function()
			local err = failing(gl.http_error(429, "Retry later", { ["Retry-After"] = "42" }))
			t.eq("rate_limit", err.kind)
			t.eq("GitLab rate limit reached, resets in 42s", err.message)
		end)

		t.it("uses the reset time for a 429 without Retry-After", function()
			local err = failing(gl.http_error(429, "Retry later", { ["RateLimit-Reset"] = tostring(os.time() + 30) }))
			t.eq(true, err.message:match("resets in %d+s$") ~= nil)
		end)

		t.it("gives a 429 with no hint", function()
			t.eq("GitLab rate limit reached", failing(gl.http_error(429, "Retry later")).message)
		end)

		t.it("calls an unknown host a network error", function()
			t.eq(
				{ kind = "network", message = "cannot reach gitlab.com" },
				failing({
					code = 1,
					stdout = "",
					stderr = 'ERROR Get "https://git.acme.dev/api/v4/x": dial tcp: lookup git.acme.dev: no such host',
				})
			)
		end)

		t.it("reports a request that never answers", function()
			t.eq({ kind = "network", message = "GitLab did not answer in time" }, failing({ code = 124, stdout = "", stderr = "" }))
		end)

		t.it("keeps GitLab's message for other errors", function()
			t.eq("400 Bad request - invalid labels", failing(gl.http_error(400, "400 Bad request - invalid labels")).message)
		end)

		t.it("reports a non-JSON answer", function()
			t.eq("unexpected response from GitLab", failing(gl.ok("<html>502 Bad Gateway</html>")).message)
		end)

		t.it("reports a non-JSON answer after headers", function()
			t.eq("unexpected response from GitLab", failing(gl.ok("HTTP/2.0 200 OK\r\n\r\n<html>502</html>")).message)
		end)
	end)

	t.describe("search: kill", function()
		t.it("does not raise", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "t") }) })
			gl.hold({ MR_LIST })
			t.eq(
				true,
				n.exec_lua(function()
					local handle = _G.api.search("mr", "o/n", { state = "opened" }, "gitlab.com", function() end)
					return (pcall(handle.kill))
				end)
			)
			gl.release()
		end)
	end)

	t.describe("user_exists", function()
		local USERS = gl.req("gitlab.com", "users")

		---@param name string
		---@return boolean
		local function exists(name)
			return n.exec_lua(function(user)
				local out
				_G.api.user_exists("gitlab.com", user, function(v)
					out = v
				end)
				vim.wait(500, function()
					return out ~= nil
				end)
				return out
			end, name)
		end

		t.it("knows a user, asking by username", function()
			gl.set({ [USERS] = gl.http({ { username = "dao" } }) })
			t.eq(true, exists("dao"))
			t.eq(true, has(last_call(), "-f username=dao"))
		end)

		t.it("knows an unknown user", function()
			gl.set({ [USERS] = gl.http({}) })
			t.eq(false, exists("nobody"))
		end)

		t.it("gives the benefit of the doubt when the check fails", function()
			gl.set({ [USERS] = gl.http_error(403, "403 Forbidden") })
			t.eq(true, exists("x"))
		end)
	end)

	t.describe("detail", function()
		local BASE = "projects/platform%2Fpayments%2Fapi/merge_requests/412"

		---`api.detail(mr_item)` in the child.
		---@return { detail?: table, error?: string }
		local function detail()
			return n.exec_lua(function(raw)
				local item = _G.api.normalize("mr", raw, "gitlab.com")
				local out
				_G.api.detail(item, function(r)
					out = r
				end)
				vim.wait(500, function()
					return out ~= nil
				end)
				return out
			end, gl.mr(412, "Retry", { references = { full = "platform/payments/api!412" } }))
		end

		t.before_each(function()
			gl.set({
				[gl.req("gitlab.com", BASE)] = gl.http({
					description = "Retry with backoff",
					source_branch = "retry-backoff",
					target_branch = "main",
					changes_count = "6",
					has_conflicts = false,
					detailed_merge_status = "mergeable",
					head_pipeline = { status = "success" },
					reviewers = { { username = "mina" }, { username = "lee" } },
					assignees = { { username = "dao" } },
					milestone = { title = "2026.4" },
				}),
				[gl.req("gitlab.com", BASE .. "/notes")] = gl.http({
					{
						system = true,
						author = { username = "bot" },
						body = "added label ~bug",
						created_at = "2026-11-11T00:00:00.000Z",
					},
					{
						system = false,
						author = { username = "mina" },
						body = "Looks good",
						created_at = "2026-11-12T00:00:00.000Z",
					},
				}),
			})
		end)

		t.it("has the body and the branches", function()
			local d = detail().detail
			t.eq("Retry with backoff", d.body)
			t.eq({ "main", "retry-backoff" }, { d.base, d.head })
		end)

		t.it("reads the file count from a string", function()
			t.eq(6, detail().detail.files)
		end)

		t.it("has no line totals and no checks", function()
			local d = detail().detail
			t.eq({ false, false, false }, { d.additions ~= nil, d.deletions ~= nil, d.checks ~= nil })
		end)

		t.it("has the pipeline, mergeable, people and milestone", function()
			local d = detail().detail
			t.eq("✓ passed", d.pipeline)
			t.eq("MERGEABLE", d.mergeable)
			t.eq({ "mina", "lee" }, d.reviewers)
			t.eq({ "dao" }, d.assignees)
			t.eq("2026.4", d.milestone)
		end)

		t.it("leaves system notes out", function()
			t.eq(1, #detail().detail.conversation)
		end)

		t.it("has the conversation entry", function()
			t.eq({ author = "mina", body = "Looks good", created = "2026-11-12T00:00:00.000Z" }, detail().detail.conversation[1])
		end)

		t.it("asks for the notes oldest first", function()
			detail()
			t.eq(1, select(2, last_call():gsub("sort=asc", "")))
		end)

		t.it("makes a failed request a message", function()
			gl.set({ [gl.req("gitlab.com", BASE)] = gl.http_error(404, "404 Not Found") })
			t.eq("project not found or no access to it", detail().error)
		end)

		t.it("builds a commit url with the /-/ segment", function()
			t.eq(
				"https://gitlab.com/platform/payments/api/-/commit/abc",
				n.exec_lua(function(raw)
					return _G.api.commit_url(_G.api.normalize("mr", raw, "gitlab.com"), "abc")
				end, gl.mr(412, "Retry", { references = { full = "platform/payments/api!412" } }))
			)
		end)
	end)

	t.describe("normalize_detail", function()
		---`api.normalize_detail(kind, raw, {})` in the child.
		---@param kind "mr"|"issue"
		---@param raw table
		---@return table
		local function normalize_detail(kind, raw)
			return n.exec_lua(function(a)
				return _G.api.normalize_detail(a.kind, a.raw, {})
			end, { kind = kind, raw = raw })
		end

		t.it("reads more than a thousand files", function()
			t.eq(1000, normalize_detail("mr", { changes_count = "1000+" }).files)
		end)

		t.it("reads conflicts", function()
			t.eq("CONFLICTING", normalize_detail("mr", { has_conflicts = true }).mergeable)
		end)

		t.it("reads the conflict status", function()
			t.eq("CONFLICTING", normalize_detail("mr", { detailed_merge_status = "conflict" }).mergeable)
		end)

		t.it("leaves other merge statuses out", function()
			t.eq(nil, normalize_detail("mr", { detailed_merge_status = "ci_must_pass" }).mergeable)
		end)

		for _, case in ipairs({
			{ "failed", "failed", "✗ failed" },
			{ "running", "running", "● running" },
			{ "waiting", "waiting_for_resource", "● waiting for resource" },
			{ "canceled", "canceled", "canceled" },
		}) do
			t.it("words a " .. case[1] .. " pipeline", function()
				t.eq(case[3], normalize_detail("mr", { head_pipeline = { status = case[2] } }).pipeline)
			end)
		end

		t.it("gives an issue no branches or files", function()
			t.eq(nil, normalize_detail("issue", { description = "x" }).base)
		end)
	end)
end)
