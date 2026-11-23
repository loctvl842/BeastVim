local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Commits of a pull request and one commit with its files (gh api, paging, errors).

local PR = { number = 7, repo = "o/n", host = "github.com" }

---@param p integer
---@return string
local function page(p)
	return ("gh api -X GET repos/o/n/pulls/7/commits --hostname github.com -f per_page=100 -f page=%d"):format(p)
end

local SHA = "abc1234def"
local COMMIT = "gh api -X GET repos/o/n/commits/" .. SHA

t.describe("finder gh commits api", function()
	t.before_each(function()
		h.clear()
		gh.install()
	end)

	---`api.commits(pr)` in the child, waiting for the answer.
	---@return table
	local function commits()
		return n.exec_lua(function(pr)
			local got
			require("beast.libs.finder.source.gh.api").commits(pr, function(r)
				got = r
			end)
			vim.wait(1000, function()
				return got ~= nil
			end, 5)
			return {
				count = got.commits and #got.commits,
				first = got.commits and got.commits[1],
				second = got.commits and got.commits[2],
				truncated = got.truncated == true,
				truncated_nil = got.truncated == nil,
				error = got.error and got.error.message,
				no_commits = got.commits == nil,
			}
		end, PR)
	end

	---`api.commit(pr, sha)` in the child, waiting for the answer.
	---@return table
	local function commit()
		return n.exec_lua(function(pr, sha)
			local got
			require("beast.libs.finder.source.gh.api").commit(pr, sha, function(r)
				got = r
			end)
			vim.wait(1000, function()
				return got ~= nil
			end, 5)
			local d = got.detail
			return {
				message = d and d.message,
				count = d and #d.files,
				truncated = d and d.truncated,
				patch = d and d.files[1] and d.files[1].patch ~= nil,
				no_detail = d == nil,
				error = got.error ~= nil,
			}
		end, PR, SHA)
	end

	t.describe("commits of a pull request", function()
		t.it("lists three commits with one call", function()
			gh.set({ [page(1)] = gh.json(gh.commits(3)) })
			t.eq(3, commits().count)
			t.eq(1, gh.count("gh api"))
		end)

		t.it("gives a short id and the subject", function()
			gh.set({ [page(1)] = gh.json(gh.commits(3)) })
			local r = commits()
			t.eq(7, #r.first.short)
			t.eq("Commit 1 subject", r.first.subject)
		end)

		t.it("takes the login as the author and keeps the full message", function()
			gh.set({ [page(1)] = gh.json(gh.commits(3)) })
			local r = commits()
			t.eq("dev2", r.second.author)
			t.eq(true, r.second.message:find("Body of commit 2", 1, true) ~= nil)
		end)

		t.it("is not truncated", function()
			gh.set({ [page(1)] = gh.json(gh.commits(3)) })
			t.eq(true, commits().truncated_nil)
		end)

		t.it("ends the listing on a short third page", function()
			gh.set({
				[page(1)] = gh.json(gh.commits(100, 1)),
				[page(2)] = gh.json(gh.commits(100, 101)),
				[page(3)] = gh.json(gh.commits(50, 201)),
			})
			local r = commits()
			t.eq(250, r.count)
			t.eq(true, r.truncated_nil)
			t.eq(3, gh.count("gh api"))
		end)

		t.it("truncates after more than three full pages", function()
			gh.set({
				[page(1)] = gh.json(gh.commits(100, 1)),
				[page(2)] = gh.json(gh.commits(100, 101)),
				[page(3)] = gh.json(gh.commits(100, 201)),
				[page(4)] = gh.json(gh.commits(1, 301)),
			})
			local r = commits()
			t.eq(300, r.count)
			t.eq(true, r.truncated)
		end)

		t.it("comes back as an error", function()
			gh.set({ [page(1)] = gh.fail("gh: Not Found (HTTP 404)") })
			local r = commits()
			t.eq(true, r.no_commits)
			t.eq(true, r.error ~= nil and r.error:find("Not Found", 1, true) ~= nil)
		end)
	end)

	t.describe("one commit", function()
		t.it("has the message and the files", function()
			gh.set({ [COMMIT] = gh.json({ commit = { message = "Subject\n\nBody" }, files = gh.files(2) }) })
			local r = commit()
			t.eq("Subject\n\nBody", r.message)
			t.eq(2, r.count)
			t.eq(false, r.truncated)
		end)

		t.it("keeps the patch of a file", function()
			gh.set({ [COMMIT] = gh.json({ commit = { message = "Subject\n\nBody" }, files = gh.files(2) }) })
			t.eq(true, commit().patch)
		end)

		t.it("has an empty file list for a commit without files", function()
			gh.set({ [COMMIT] = gh.json({ commit = { message = "Merge" } }) })
			t.eq(0, commit().count)
		end)

		t.it("reports an error", function()
			gh.set({ [COMMIT] = gh.fail("gh: Not Found (HTTP 404)") })
			local r = commit()
			t.eq(true, r.no_detail)
			t.eq(true, r.error)
		end)
	end)
end)
