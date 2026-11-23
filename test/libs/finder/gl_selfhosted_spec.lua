local F = require("test.libs.finder.helpers.finder")
local gl = require("test.libs.finder.helpers.gl")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- GitLab sources against a self-hosted server (replayed responses): responses recorded from gitlab.com
-- (fixtures/gitlab) are replayed as if a server at git.acme.dev answered, with a nested project path:
-- every request must carry that host and the encoded path, the unknown-host toast must go away once
-- the host is mapped, and a server that lacks fields or answers with a gateway page must not break the
-- pickers. vim.system is scripted in the child; nothing runs `glab`.

local HOST = "git.acme.dev"
local PROJECT = "platform/payments/api"
local ENC = "platform%2Fpayments%2Fapi"
local REMOTE = "git@git.acme.dev:platform/payments/api.git"

---A recorded response, moved to the fake server and the nested project.
---@param name string fixture file
---@return table
local function fixture(name)
	local f = assert(io.open("test/libs/finder/fixtures/gitlab/" .. name .. ".json"))
	local text = f:read("*a")
	f:close()
	text = text:gsub("loctvl842/glab%-finder%-test", PROJECT):gsub("https://gitlab%.com", "https://" .. HOST)
	return vim.json.decode(text)
end

---@param path string
---@return string
local function req(path)
	return gl.req(HOST, "projects/" .. ENC .. "/" .. path)
end

---Map the fake host to GitLab in the child's git config and drop the cached remote.
local function map_host()
	n.exec_lua(function(host)
		require("beast.libs.git.config").setup({ remote = { hosts = { [host] = "gitlab" } } })
		require("beast.libs.git.remote").invalidate()
	end, HOST)
end

t.describe("finder gl selfhosted", function()
	t.before_each(function()
		F.setup()
		gl.install(REMOTE)
		n.exec_lua(function()
			_G.mr_source = require("beast.libs.finder.source.gl").create("mr")

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
		end)
	end)

	t.describe("an unknown host", function()
		t.it("offers no keys", function()
			t.eq(
				false,
				n.exec_lua(function()
					return Git.has_provider("gitlab", "/proj")
				end)
			)
		end)

		t.it("fails to open", function()
			t.eq(
				false,
				n.exec_lua(function()
					return _G.mr_source.check()
				end)
			)
		end)

		t.it("explains the host and the setting in a toast", function()
			n.exec_lua(function()
				_G.mr_source.check()
			end)
			t.eq("git.acme.dev is not known as a GitLab server. Add it to the git remote hosts setting.", F.toasts()[1])
		end)
	end)

	t.describe("once mapped", function()
		t.before_each(map_host)

		t.it("offers the keys", function()
			t.eq(
				true,
				n.exec_lua(function()
					return Git.has_provider("gitlab", "/proj")
				end)
			)
		end)

		t.it("opens", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.mr_source.check()
				end)
			)
		end)

		t.it("sends the login check to the mapped host", function()
			n.exec_lua(function()
				_G.mr_source.check()
			end)
			local calls = gl.calls()
			t.eq("glab auth status --hostname " .. HOST, calls[#calls])
		end)

		t.it("titles with the host and the nested path", function()
			t.eq(
				"Merge Requests - git.acme.dev/platform/payments/api",
				n.exec_lua(function()
					_G.mr_source.check()
					return _G.mr_source.title()
				end)
			)
		end)
	end)

	t.describe("list, detail, files, commits on the fake server", function()
		local mr6

		---Run the merge request list source once; returns the items.
		---@param pattern string
		---@return table[]
		local function list(pattern)
			return n.exec_lua(function(p)
				_G.mr_source.check()
				return _G.run(_G.mr_source, { pattern = p })
			end, pattern)
		end

		---Publish the first merge request of the list as `_G.mr6` in the child.
		local function publish_mr6()
			n.exec_lua(function(item)
				_G.mr6 = item
			end, mr6)
		end

		t.before_each(function()
			map_host()
			gl.set({ [req("merge_requests")] = gl.http(fixture("mr_list"), { ["X-Total"] = "6" }) })
			local items = list("state:all")
			mr6 = items[1]
		end)

		t.it("lists every merge request of the fixture", function()
			t.eq(6, #list("state:all"))
		end)

		t.it("keeps the states through the replay", function()
			t.eq(
				{ "open", "open", "closed", "merged", "open", "draft" },
				vim.tbl_map(function(i)
					return i.state
				end, list("state:all"))
			)
		end)

		t.it("takes the nested project path", function()
			t.eq(PROJECT, mr6.repo)
		end)

		t.it("points the url at the fake server", function()
			t.eq("https://git.acme.dev/" .. PROJECT .. "/-/merge_requests/6", mr6.url)
		end)

		t.it("takes the host", function()
			t.eq(HOST, mr6.host)
		end)

		t.it("sends every request to the fake host with the encoded path", function()
			local bad = {}
			for _, line in ipairs(gl.calls()) do
				if line:sub(1, 8) == "glab api" and not line:find("--hostname " .. HOST .. " --include projects/" .. ENC, 1, true) then
					bad[#bad + 1] = line
				end
			end
			t.eq({}, bad)
		end)

		t.describe("detail", function()
			---`api.detail(mr6)` in the child.
			---@return table
			local function detail()
				publish_mr6()
				return n.exec_lua(function()
					local out
					require("beast.libs.finder.source.gl.api").detail(_G.mr6, function(r)
						out = r
					end)
					vim.wait(1000, function()
						return out ~= nil
					end)
					return out
				end)
			end

			t.before_each(function()
				gl.set({
					[req("merge_requests/6")] = gl.http(fixture("mr_6")),
					[req("merge_requests/6/notes")] = gl.http(fixture("mr_6_notes")),
				})
			end)

			t.it("has the file count", function()
				t.eq(5, detail().detail.files)
			end)

			t.it("has the branches", function()
				local d = detail().detail
				t.eq({ "main", "retry-backoff" }, { d.base, d.head })
			end)

			t.it("keeps the human note only in the conversation", function()
				t.eq(1, #detail().detail.conversation)
			end)
		end)

		t.it("lists the files of the merge request", function()
			gl.set({ [req("merge_requests/6/diffs")] = gl.http(fixture("mr_6_diffs")) })
			publish_mr6()
			t.eq(
				5,
				n.exec_lua(function()
					return #_G.run(require("beast.libs.finder.source.gh_pr_files"), { ctx = { pr = _G.mr6 }, cwd = "/proj" })
				end)
			)
		end)

		t.describe("commits", function()
			local commits

			t.before_each(function()
				gl.set({ [req("merge_requests/6/commits")] = gl.http(fixture("mr_6_commits")) })
				publish_mr6()
				commits = n.exec_lua(function()
					return _G.run(require("beast.libs.finder.source.gh_commits"), { ctx = { pr = _G.mr6 }, cwd = "/proj" })
				end)
			end)

			t.it("lists them newest first", function()
				t.eq(3, #commits)
			end)

			t.it("puts the commit url on the fake server", function()
				t.eq("https://git.acme.dev/" .. PROJECT .. "/-/commit/" .. commits[1].sha, commits[1].url)
			end)

			-- the newest commit changes settings, adds NOTES.md and removes README.md
			t.it("lists the files of a commit", function()
				gl.set({ [req("repository/commits/" .. commits[1].sha .. "/diff")] = gl.http(fixture("commit_diff")) })
				t.eq(
					3,
					n.exec_lua(function(commit)
						require("beast.libs.finder.source.gh.commit_preview").reset()
						return #_G.run(require("beast.libs.finder.source.gh_commit_files"), { ctx = { commit = commit }, cwd = "/proj" })
					end, commits[1])
				)
			end)
		end)

		t.describe("issues", function()
			local issues

			t.before_each(function()
				gl.set({ [req("issues")] = gl.http(fixture("issue_list")) })
				issues = n.exec_lua(function()
					local source = require("beast.libs.finder.source.gl").create("issue")
					source.check()
					return _G.run(source, { pattern = "state:all" })
				end)
			end)

			t.it("lists the issues of the fixture", function()
				t.eq(4, #issues)
			end)

			t.it("gives the issue reference", function()
				t.eq("#4", issues[1].ref)
			end)
		end)
	end)

	t.describe("an older server that leaves fields out", function()
		local res

		t.before_each(function()
			map_host()
			local old = fixture("mr_6")
			for _, key in ipairs({
				"head_pipeline",
				"detailed_merge_status",
				"reviewers",
				"changes_count",
				"milestone",
				"assignees",
				"has_conflicts",
			}) do
				old[key] = nil
			end
			gl.set({ [req("merge_requests/6")] = gl.http(old), [req("merge_requests/6/notes")] = gl.http({}) })
			res = n.exec_lua(function(raw)
				local api = require("beast.libs.finder.source.gl.api")
				local item = api.normalize("mr", raw, "git.acme.dev")
				local out
				api.detail(item, function(r)
					out = r
				end)
				vim.wait(1000, function()
					return out ~= nil
				end)
				local lines = out.detail and require("beast.libs.finder.source.gh.preview").build(item, out.detail)
				return {
					has_detail = out.detail ~= nil,
					files = out.detail and out.detail.files,
					no_pipeline = out.detail and out.detail.pipeline == nil,
					no_mergeable = out.detail and out.detail.mergeable == nil,
					preview = lines and table.concat(lines, "\n"),
				}
			end, fixture("mr_6"))
		end)

		t.it("still answers the detail", function()
			t.eq(true, res.has_detail)
		end)

		t.it("takes a missing files count as zero", function()
			t.eq(0, res.files)
		end)

		t.it("has no pipeline and no merge verdict", function()
			t.eq(true, res.no_pipeline)
			t.eq(true, res.no_mergeable)
		end)

		t.it("draws the preview without the missing lines", function()
			t.eq(true, res.preview:find("Pipeline:", 1, true) == nil)
		end)
	end)

	t.describe("a gateway page instead of the API", function()
		---Run the merge request source with the list answered by `res`.
		---@param res vim.SystemCompleted
		---@return table[]
		local function failing(res)
			map_host()
			gl.set({ [req("merge_requests")] = res })
			return n.exec_lua(function()
				_G.mr_source.check()
				return _G.run(_G.mr_source, { pattern = "state:opened" })
			end)
		end

		t.it("names GitLab in the heading and gives the reason", function()
			local items = failing(gl.ok("<html><body>502 Bad Gateway</body></html>"))
			t.eq("GitLab could not run this search:", items[1].text)
			t.eq("unexpected response from GitLab", items[2].text)
		end)

		t.it("shows glab's own line for a certificate problem", function()
			local items = failing({
				code = 1,
				stdout = "",
				stderr = 'ERROR Get "https://git.acme.dev/api/v4/projects": x509: certificate signed by unknown authority',
			})
			t.eq(true, items[2].text:find("x509", 1, true) ~= nil)
		end)
	end)
end)
