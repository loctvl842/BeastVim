local F = require("test.libs.finder.helpers.finder")
local gl = require("test.libs.finder.helpers.gl")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- GitLab drill-down (files, commits, commit files, issue grep, chain edges): the glab requests behind
-- the shared sources, their normalization (status from flags, line counts from hunks, newest-first
-- commits reversed), truncation, the sources run on a merge request item, and the new edges.
-- vim.system is scripted in the child.

local HOST = "gitlab.acme.dev"
local BASE = "projects/platform%2Fpayments%2Fapi"
local DIFFS = gl.req(HOST, BASE .. "/merge_requests/6/diffs")
local COMMITS = gl.req(HOST, BASE .. "/merge_requests/6/commits")
local MR_RAW = gl.mr(6, "Retry failed webhooks with backoff", { references = { full = "platform/payments/api!6" } })

---`api.normalize_file(raw)` in the child.
---@param raw table
---@return table
local function normalize_file(raw)
	return n.exec_lua(function(r)
		return require("beast.libs.finder.source.gl.api").normalize_file(r)
	end, raw)
end

---Run `api.<fn>(mr, cb)` in the child and wait for its answer; `files`/`commits` of the result are
---reduced to what the assertions read.
---@param fn "files"|"commits"
---@return table
local function api_call(fn)
	return n.exec_lua(function(name)
		return _G.wait_for(function(cb)
			require("beast.libs.finder.source.gl.api")[name](_G.mr, cb)
		end)
	end, fn)
end

---Run the shared source `name` with `filter` in the child, return the items it emitted.
---@param name string
---@param filter table the string "MR" in `ctx.pr` is replaced by the normalized merge request
---@return table[]
local function run(name, filter)
	return n.exec_lua(function(a)
		if a.filter.ctx and a.filter.ctx.pr == "MR" then
			a.filter.ctx.pr = _G.mr
		end
		return _G.run(require("beast.libs.finder.source." .. a.name), a.filter)
	end, { name = name, filter = filter })
end

t.describe("finder gl chains", function()
	t.before_each(function()
		F.setup()
		gl.install()
		n.exec_lua(function(raw)
			_G.mr = require("beast.libs.finder.source.gl.api").normalize("mr", raw, "gitlab.acme.dev")

			_G.wait_for = function(start)
				local out
				start(function(r)
					out = r
				end)
				vim.wait(1000, function()
					return out ~= nil
				end)
				return out
			end

			---Run source.get and collect what it emits.
			_G.run = function(source, filter)
				local items, finished = {}, false
				source.get(filter, function(item)
					if item == nil then
						finished = true
					else
						items[#items + 1] = item
					end
				end)
				vim.wait(1000, function()
					return finished
				end)
				return items
			end
		end, MR_RAW)
	end)

	t.describe("normalize_file", function()
		t.it("reads the path and the status", function()
			local f = normalize_file(gl.diffs(1)[1])
			t.eq("src/f1.lua", f.path)
			t.eq("modified", f.status)
		end)

		t.it("counts additions and deletions from the hunk", function()
			local f = normalize_file(gl.diffs(1)[1])
			t.eq(2, f.additions)
			t.eq(1, f.deletions)
		end)

		t.it("keeps the patch", function()
			t.eq(true, normalize_file(gl.diffs(1)[1]).patch:find("^@@") ~= nil)
		end)

		t.it("has no previous path when not renamed", function()
			t.eq(nil, normalize_file(gl.diffs(1)[1]).previous)
		end)

		t.it("reads a new file as added", function()
			t.eq("added", normalize_file({ new_path = "a", old_path = "a", new_file = true, diff = "@@ -0,0 +1 @@\n+x\n" }).status)
		end)

		t.it("reads a deleted file as removed", function()
			t.eq("removed", normalize_file({ new_path = "a", old_path = "a", deleted_file = true, diff = "@@ -1 +0,0 @@\n-x\n" }).status)
		end)

		t.describe("a rename", function()
			local renamed

			t.before_each(function()
				renamed = normalize_file({ new_path = "b.lua", old_path = "a.lua", renamed_file = true, diff = "" })
			end)

			t.it("reads as renamed with the previous path", function()
				t.eq("renamed", renamed.status)
				t.eq("a.lua", renamed.previous)
			end)

			t.it("has no patch for an empty diff", function()
				t.eq(nil, renamed.patch)
			end)
		end)

		t.it("has no patch when too large", function()
			t.eq(nil, normalize_file({ new_path = "a", old_path = "a", too_large = true, diff = "@@ -1 +1 @@\n-a\n+b\n" }).patch)
		end)

		t.it("has no patch when collapsed", function()
			t.eq(nil, normalize_file({ new_path = "a", old_path = "a", collapsed = true, diff = "@@ -1 +1 @@\n-a\n+b\n" }).patch)
		end)
	end)

	t.describe("files", function()
		t.it("lists three files, not truncated", function()
			gl.set({ [DIFFS] = gl.http(gl.diffs(3)) })
			local res = api_call("files")
			t.eq(3, #res.files)
			t.eq(nil, res.truncated)
		end)

		t.it("requests host, nested project and paging", function()
			gl.set({ [DIFFS] = gl.http(gl.diffs(3)) })
			api_call("files")
			local calls = gl.calls()
			t.eq(DIFFS .. " -f page=1 -f per_page=100", calls[#calls])
		end)

		t.describe("with three full pages", function()
			t.before_each(function()
				gl.set({
					[DIFFS .. " -f page=1"] = gl.http(gl.diffs(100, "a", 1)),
					[DIFFS .. " -f page=2"] = gl.http(gl.diffs(100, "b", 1)),
					[DIFFS .. " -f page=3"] = gl.http(gl.diffs(100, "c", 1)),
				})
			end)

			t.it("keeps three pages and says a fourth page with files cut it short", function()
				gl.set({ [DIFFS .. " -f page=4"] = gl.http(gl.diffs(1, "d", 1)) })
				local res = api_call("files")
				t.eq(300, #res.files)
				t.eq(true, res.truncated)
			end)

			t.it("is not truncated with an empty fourth page", function()
				gl.set({ [DIFFS .. " -f page=4"] = gl.http({}) })
				t.eq(false, api_call("files").truncated)
			end)
		end)

		t.it("returns an error", function()
			gl.set({ [DIFFS .. " -f page=1"] = gl.http_error(404, "404 Not Found") })
			t.eq("not_found", api_call("files").error.kind)
		end)
	end)

	t.describe("commits", function()
		t.before_each(function()
			gl.set({ [COMMITS] = gl.http(gl.commits(3)) })
		end)

		t.it("hands over oldest first what GitLab answers newest first", function()
			local res = api_call("commits")
			t.eq({ "Commit 1 subject", "Commit 3 subject" }, { res.commits[1].subject, res.commits[3].subject })
		end)

		t.it("has the short id and the author", function()
			local c = api_call("commits").commits[1]
			t.eq("00000001", c.short)
			t.eq("Author 1", c.author)
		end)

		t.it("keeps the body in the message", function()
			t.eq("Commit 1 subject\n\nBody of commit 1", api_call("commits").commits[1].message)
		end)

		t.it("has a full sha", function()
			t.eq(40, #api_call("commits").commits[1].sha)
		end)

		t.it("keeps the offset of the date", function()
			t.eq("2026-11-11T17:00:00.000+07:00", api_call("commits").commits[1].date)
		end)

		t.describe("the shared source", function()
			local items

			t.before_each(function()
				items = run("gh_commits", { ctx = { pr = "MR" }, cwd = "/proj" })
			end)

			t.it("lists three rows, newest first again", function()
				t.eq(3, #items)
				t.eq("Commit 3 subject", items[1].subject)
			end)

			t.it("numbers the rows in order", function()
				t.eq(1, items[1].idx)
			end)

			t.it("uses GitLab's commit url", function()
				t.eq("https://gitlab.acme.dev/platform/payments/api/-/commit/" .. items[1].sha, items[1].url)
			end)

			t.it("says MR in the title", function()
				t.eq(
					"MR Retry failed webhooks with backoff › Commits (3)",
					n.exec_lua(function(its)
						return require("beast.libs.finder.source.gh_commits").title({ ctx = { pr = _G.mr } }, its)
					end, items)
				)
			end)
		end)

		t.it("names GitLab in the failure heading", function()
			gl.set({ [COMMITS] = gl.http_error(404, "404 Not Found") })
			t.eq("GitLab could not list the commits:", run("gh_commits", { ctx = { pr = "MR" }, cwd = "/proj" })[1].text)
		end)
	end)

	t.describe("files source on a merge request", function()
		local filter = { ctx = { pr = "MR" }, cwd = "/proj" }

		t.before_each(function()
			gl.set({
				[DIFFS] = gl.http({
					{ old_path = "a.lua", new_path = "a.lua", diff = "@@ -1 +1 @@\n-a\n+b\n" },
					{ old_path = "old.lua", new_path = "new.lua", renamed_file = true, diff = "" },
				}),
			})
		end)

		t.it("lists the rows with the file and the owner", function()
			local items = run("gh_pr_files", filter)
			t.eq(2, #items)
			t.eq("a.lua", items[1].file)
			t.eq("!6", items[1].pr.ref)
		end)

		t.it("keeps the previous path of a rename", function()
			t.eq("old.lua", run("gh_pr_files", filter)[2].previous)
		end)

		t.it("has a title", function()
			t.eq(
				"MR Retry failed webhooks with backoff › Files Changed (2)",
				n.exec_lua(function(its)
					return require("beast.libs.finder.source.gh_pr_files").title({ ctx = { pr = _G.mr } }, its)
				end, run("gh_pr_files", filter))
			)
		end)

		t.it("says so when no files changed", function()
			gl.set({ [DIFFS] = gl.http({}) })
			t.eq("No files changed", run("gh_pr_files", filter)[1].text)
		end)

		t.it("names GitLab and the host's login on failure", function()
			gl.set({ [DIFFS] = gl.http_error(401, "401 Unauthorized") })
			local items = run("gh_pr_files", filter)
			t.eq("GitLab could not list the files:", items[1].text)
			t.eq("GitLab login expired, run `glab auth login --hostname gitlab.acme.dev`", items[2].text)
		end)
	end)

	t.describe("commit files", function()
		local sha = ("%08dabcdef0123456789abcdef0123456789"):format(2):sub(1, 40)
		local CDIFF = gl.req(HOST, BASE .. "/repository/commits/" .. sha .. "/diff")
		local commit_item = {
			sha = sha,
			short = "00000002",
			subject = "Commit 2 subject",
			body = "Commit 2 subject",
			author = "Author 2",
			date = "",
			cwd = "/proj",
		}

		---Publish the commit item (with the merge request as its `pr`) in the child.
		local function with_commit()
			return n.exec_lua(function(item)
				item.pr = _G.mr
				require("beast.libs.finder.source.gh.commit_preview").reset()
				_G.commit_item = item
			end, commit_item)
		end

		t.before_each(function()
			gl.set({ [CDIFF] = gl.http(gl.diffs(2, "c")) })
			with_commit()
		end)

		t.it("has the commit's files, not truncated", function()
			local res = n.exec_lua(function()
				return _G.wait_for(function(cb)
					require("beast.libs.finder.source.gh.commit_preview").detail(_G.commit_item, cb)
				end)
			end)
			t.eq(2, #res.detail.files)
			t.eq(false, res.detail.truncated)
		end)

		t.it("answers a second look from the cache", function()
			local count = n.exec_lua(function()
				local preview = require("beast.libs.finder.source.gh.commit_preview")
				_G.wait_for(function(cb)
					preview.detail(_G.commit_item, cb)
				end)
				local cached = _G.wait_for(function(cb)
					preview.detail(_G.commit_item, cb)
				end)
				return #cached.detail.files
			end)
			t.eq(2, count)
			t.eq(1, gl.count(CDIFF))
		end)

		t.it("lists a row per file of the commit", function()
			local items = n.exec_lua(function()
				return _G.run(require("beast.libs.finder.source.gh_commit_files"), { ctx = { commit = _G.commit_item }, cwd = "/proj" })
			end)
			t.eq(2, #items)
			t.eq("c1.lua", items[1].file)
		end)

		t.it("names GitLab in the failure heading", function()
			gl.set({ [CDIFF] = gl.http_error(404, "404 Not Found") })
			local items = n.exec_lua(function()
				return _G.run(require("beast.libs.finder.source.gh_commit_files"), { ctx = { commit = _G.commit_item }, cwd = "/proj" })
			end)
			t.eq("GitLab could not list the files:", items[1].text)
		end)
	end)

	t.describe("issue grep on GitLab issues", function()
		local items

		t.before_each(function()
			items = n.exec_lua(function(raw)
				local issue = require("beast.libs.finder.source.gl.api").normalize("issue", raw, "gitlab.com")
				return _G.run(require("beast.libs.finder.source.gh_issue_grep"), { pattern = "retry", ctx = { issues = { issue } } })
			end, gl.issue(207, "Webhook signature", { description = "Steps\nretry fails" }))
		end)

		t.it("finds one hit", function()
			t.eq(1, #items)
		end)

		-- line 1 is the title, so the description's second line is line 3
		t.it("uses the issue's own reference in the row text", function()
			t.eq("#207:3: retry fails", items[1].text)
		end)

		t.it("shows the reference in the header", function()
			t.eq(
				"#207",
				n.exec_lua(function(item)
					local header = require("beast.libs.finder.format").gh_issue_grep_header(item)
					return vim.trim(header[2].text)
				end, items[1])
			)
		end)
	end)

	t.describe("edges", function()
		---The edge `id` of the chain list as plain data, with what its callbacks answer for the merge request.
		---@param id string
		---@return table
		local function edge(id)
			return n.exec_lua(function(edge_id)
				local found
				for _, e in ipairs(require("beast.libs.finder.chains")) do
					if e.id == edge_id then
						found = e
					end
				end
				if not found then
					return { found = false }
				end
				local state = { selected = _G.mr, total = 1 }
				local hint_ok, hint = pcall(found.hint, state)
				local open_ok, opened = pcall(found.open, state)
				opened = open_ok and type(opened) == "table" and opened or {}
				return {
					found = true,
					key = found.key,
					crumb = found.crumb,
					hint = hint_ok and hint or nil,
					opened_ref = opened.ctx and opened.ctx.pr and opened.ctx.pr.ref,
					opened_title = opened.title,
				}
			end, id)
		end

		t.it("has mr -> files on the default key", function()
			t.eq("<C-g>", edge("gl_mr|gh_pr_files").key)
		end)

		t.it("has mr -> commits", function()
			t.eq("<C-t>", edge("gl_mr|gh_commits").key)
		end)

		t.it("has issue -> grep", function()
			t.eq("<C-g>", edge("gl_issue|gh_issue_grep").key)
		end)

		t.it("has the crumb", function()
			t.eq("Merge Requests", edge("gl_mr|gh_pr_files").crumb)
		end)

		t.it("names the merge request's reference in the hints", function()
			t.eq("files changed in !6", edge("gl_mr|gh_pr_files").hint)
			t.eq("commits in !6", edge("gl_mr|gh_commits").hint)
		end)

		t.it("still has the GitHub edges", function()
			t.eq(true, edge("gh_pr|gh_pr_files").found and edge("gh_issue|gh_issue_grep").found)
		end)

		t.it("carries the merge request and its title when opening", function()
			local e = edge("gl_mr|gh_commits")
			t.eq("!6", e.opened_ref)
			t.eq("MR Retry failed webhooks with backoff › Commits", e.opened_title)
		end)
	end)
end)
