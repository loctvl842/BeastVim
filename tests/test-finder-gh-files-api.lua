-- =========================================================================
-- Test: files a pull request changes (gh api, paging, truncation, errors)
-- (docs/dev-specs/finder-continuous.md, Phase 4)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-files-api.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()
local api = require("beast.libs.finder.source.gh.api")

local pr = { number = 7, repo = "o/n", host = "github.com" }
local function page(n)
	return ("gh api -X GET repos/o/n/pulls/7/files --hostname github.com -f per_page=100 -f page=%d"):format(n)
end

--- Run `api.files` and wait for its answer.
local function files()
	local result
	api.files(pr, function(r)
		result = r
	end)
	H.wait(function()
		return result ~= nil
	end, 1000)
	return result
end

gh.install()

gh.script[page(1)] = gh.ok(vim.json.encode(gh.files(2)))
local r = files()
t.eq("a short first page ends the listing", #r.files, 2)
t.eq("no truncation", r.truncated, nil)
t.eq("one call", gh.count("gh api"), 1)
t.eq("paths", { r.files[1].path, r.files[2].path }, { "src/f1.lua", "src/f2.lua" })
t.eq("counts and patch are kept", { r.files[2].additions, r.files[2].deletions, r.files[2].patch ~= nil }, { 2, 1, true })

gh.calls = {}
gh.script[page(1)] = gh.ok(vim.json.encode(gh.files(100, "a", 1)))
gh.script[page(2)] = gh.ok(vim.json.encode(gh.files(100, "a", 101)))
gh.script[page(3)] = gh.ok(vim.json.encode(gh.files(100, "a", 201)))
gh.script[page(4)] = gh.ok(vim.json.encode(gh.files(5, "a", 301)))
r = files()
t.eq("three pages are kept", #r.files, 300)
t.eq("a fourth page says the list was cut", r.truncated, true)
t.eq("four calls", gh.count("gh api"), 4)

gh.calls = {}
gh.script[page(4)] = gh.ok("[]")
r = files()
t.eq("exactly 300 files is not truncated", { #r.files, r.truncated }, { 300, false })

gh.script[page(1)] = gh.ok(vim.json.encode({ { filename = "x.png", status = "added", additions = 0, deletions = 0 } }))
r = files()
t.eq("a binary file has no patch", r.files[1].patch, nil)

gh.script[page(1)] = gh.fail("gh: Not Found (HTTP 404)")
r = files()
t.eq("an error comes back as an error", r.files, nil)
t.ok("error has a message", r.error and r.error.message:find("Not Found", 1, true) ~= nil, vim.inspect(r.error))

gh.script[page(1)] = gh.ok("not json")
r = files()
t.ok("garbage is an error", r.error ~= nil)

gh.restore()
t.done()
