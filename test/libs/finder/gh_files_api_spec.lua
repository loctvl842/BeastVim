local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Files a pull request changes (gh api, paging, truncation, errors).

local PR = { number = 7, repo = "o/n", host = "github.com" }

---@param p integer
---@return string
local function page(p)
	return ("gh api -X GET repos/o/n/pulls/7/files --hostname github.com -f per_page=100 -f page=%d"):format(p)
end

t.describe("finder gh files api", function()
	t.before_each(function()
		h.clear()
		gh.install()
	end)

	---`api.files(pr)` in the child, waiting for the answer.
	---@return table
	local function files()
		return n.exec_lua(function(pr)
			local got
			require("beast.libs.finder.source.gh.api").files(pr, function(r)
				got = r
			end)
			vim.wait(1000, function()
				return got ~= nil
			end, 5)
			local f = got.files
			return {
				count = f and #f,
				first = f and f[1],
				second = f and f[2],
				patch1 = f and f[1] and f[1].patch ~= nil,
				patch2 = f and f[2] and f[2].patch ~= nil,
				truncated = got.truncated,
				truncated_set = got.truncated ~= nil,
				no_files = f == nil,
				error = got.error and got.error.message,
			}
		end, PR)
	end

	t.describe("a short first page", function()
		t.before_each(function()
			gh.set({ [page(1)] = gh.json(gh.files(2)) })
		end)

		t.it("ends the listing", function()
			t.eq(2, files().count)
		end)

		t.it("is not truncated", function()
			t.eq(false, files().truncated_set)
		end)

		t.it("takes one call", function()
			files()
			t.eq(1, gh.count("gh api"))
		end)

		t.it("lists the paths", function()
			local r = files()
			t.eq({ "src/f1.lua", "src/f2.lua" }, { r.first.path, r.second.path })
		end)

		t.it("keeps the counts and the patch", function()
			local r = files()
			t.eq({ 2, 1, true }, { r.second.additions, r.second.deletions, r.patch2 })
		end)
	end)

	t.describe("paging", function()
		t.it("keeps three pages and says a fourth cut the list", function()
			gh.set({
				[page(1)] = gh.json(gh.files(100, "a", 1)),
				[page(2)] = gh.json(gh.files(100, "a", 101)),
				[page(3)] = gh.json(gh.files(100, "a", 201)),
				[page(4)] = gh.json(gh.files(5, "a", 301)),
			})
			local r = files()
			t.eq(300, r.count)
			t.eq(true, r.truncated)
			t.eq(4, gh.count("gh api"))
		end)

		t.it("does not truncate exactly 300 files", function()
			gh.set({
				[page(1)] = gh.json(gh.files(100, "a", 1)),
				[page(2)] = gh.json(gh.files(100, "a", 101)),
				[page(3)] = gh.json(gh.files(100, "a", 201)),
				[page(4)] = gh.ok("[]"),
			})
			local r = files()
			t.eq({ 300, false }, { r.count, r.truncated })
		end)
	end)

	t.it("gives a binary file no patch", function()
		gh.set({
			[page(1)] = gh.json({ { filename = "x.png", status = "added", additions = 0, deletions = 0 } }),
		})
		t.eq(false, files().patch1)
	end)

	t.it("comes back as an error with a message", function()
		gh.set({ [page(1)] = gh.fail("gh: Not Found (HTTP 404)") })
		local r = files()
		t.eq(true, r.no_files)
		t.eq(true, r.error ~= nil and r.error:find("Not Found", 1, true) ~= nil)
	end)

	t.it("treats garbage as an error", function()
		gh.set({ [page(1)] = gh.ok("not json") })
		t.eq(true, files().error ~= nil)
	end)
end)
