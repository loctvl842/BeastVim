-- =========================================================================
-- Test: beast.libs.finder.search (headless file-search session)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-finder-search.lua
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

local function write(path)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ "x" }, path)
end

local root = vim.fn.resolve(vim.fn.tempname())
write(root .. "/lua/beast/init.lua")
write(root .. "/lua/beast/libs/explorer/init.lua")
write(root .. "/lua/beast/libs/finder/init.lua")
write(root .. "/lua/beast/util.lua")
write(root .. "/README.md")
write(root .. "/.hidden/secret.lua")

local search = require("beast.libs.finder.search")

--- Run one query to completion and return the sorted relative paths.
---@param session Beast.Finder.Search.Session
---@param pattern string
---@return string[] texts, Beast.Finder.Search.Result result
local function query(session, pattern)
	local out, res
	session:query(pattern, function(matched, result)
		out, res = matched, result
	end)
	vim.wait(3000, function()
		return out ~= nil and not res.loading
	end, 10)
	local texts = {}
	for _, item in ipairs(out or {}) do
		texts[#texts + 1] = item.text
	end
	table.sort(texts)
	return texts, res or {}
end

io.write("\n--- available() ---\n")
assert_test("available when fd/rg/find is installed", search.available() == true)

io.write("\n--- matches files inside closed folders ---\n")
local s = search.files({ cwd = root })
local got = query(s, "in.lua")
assert_test(
	"finds nested init.lua files",
	vim.deep_equal(got, {
		"lua/beast/init.lua",
		"lua/beast/libs/explorer/init.lua",
		"lua/beast/libs/finder/init.lua",
	}),
	vim.inspect(got)
)

io.write("\n--- finder fuzzy syntax is inherited ---\n")
got = query(s, "init !finder")
assert_test("inverse term excludes", vim.deep_equal(got, { "lua/beast/init.lua", "lua/beast/libs/explorer/init.lua" }), vim.inspect(got))
got = query(s, "explorer init")
assert_test("AND terms", vim.deep_equal(got, { "lua/beast/libs/explorer/init.lua" }), vim.inspect(got))

io.write("\n--- hidden files are excluded by default ---\n")
got = query(s, "secret")
assert_test("hidden dir not listed", #got == 0, vim.inspect(got))

io.write("\n--- limit caps results and flags capped ---\n")
local capped = search.files({ cwd = root, limit = 2 })
local texts, res = query(capped, "lua")
assert_test("two results", #texts == 2, vim.inspect(texts))
assert_test("capped flag set", res.capped == true)
capped:close()

io.write("\n--- exactly `limit` matches is not capped ---\n")
local exact = search.files({ cwd = root, limit = 3 })
texts, res = query(exact, "in.lua")
assert_test("three results", #texts == 3, vim.inspect(texts))
assert_test("not capped at exactly limit", res.capped == false)
exact:close()

io.write("\n--- rapid successive queries: the last one wins ---\n")
local rapid = search.files({ cwd = root })
vim.wait(3000, function()
	return not rapid.loading
end, 10)
local delivered = {}
local function record(matched)
	delivered[#delivered + 1] = #matched
end
rapid:query("in", record)
rapid:query("init", record)
rapid:query("explorer init", record)
vim.wait(500, function()
	return false
end, 10)
assert_test("last delivery is for the last pattern", delivered[#delivered] == 1, vim.inspect(delivered))
rapid:close()

io.write("\n--- close() with a matcher in flight ---\n")
local inflight = search.files({ cwd = root })
vim.wait(3000, function()
	return not inflight.loading
end, 10)
local late = 0
inflight:query("lua", function()
	late = late + 1
end)
inflight:close()
vim.wait(300, function()
	return false
end, 10)
assert_test("no callback after close mid-match", late == 0, "late=" .. late)

io.write("\n--- query issued mid-stream is re-run on completion ---\n")
local early = search.files({ cwd = root })
local last
early:query("README", function(matched, result)
	if not result.loading then
		last = matched
	end
end)
vim.wait(3000, function()
	return last ~= nil
end, 10)
assert_test("final result after streaming ends", last ~= nil and #last == 1 and last[1].text == "README.md")
early:close()

io.write("\n--- close() stops callbacks ---\n")
local closed = search.files({ cwd = root })
local calls = 0
closed:query("lua", function()
	calls = calls + 1
end)
closed:close()
vim.wait(300, function()
	return false
end, 10)
assert_test("no callback after close", calls == 0, "calls=" .. calls)

io.write("\n--- refresh() picks up new files ---\n")
write(root .. "/lua/beast/fresh_file.lua")
s:refresh()
vim.wait(3000, function()
	return not s.loading
end, 10)
got = query(s, "fresh_file")
assert_test("new file found after refresh", vim.deep_equal(got, { "lua/beast/fresh_file.lua" }), vim.inspect(got))
s:close()

vim.fn.delete(root, "rf")
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
