-- =========================================================================
-- Test: Finder bigram engine (extraction + bitset AND + false-neg guard)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-bigram.lua
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
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local function set_of(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[v] = true
	end
	return s
end

local bigram = require("beast.libs.finder.engine.bigram")
local extract = require("beast.libs.finder.engine.extract")

-- =========================================================================
-- extract.literal_runs — metachars split, backslash escapes next byte
-- =========================================================================
io.write("\n--- extract.literal_runs ---\n")
assert_eq("plain literal", table.concat(extract.literal_runs("error"), "|"), "error")
assert_eq("escaped paren drops paren", table.concat(extract.literal_runs("require\\("), "|"), "require")
assert_eq("dot splits run", table.concat(extract.literal_runs("a.b"), "|"), "a|b")
assert_eq("parens split", table.concat(extract.literal_runs("foo(bar)"), "|"), "foo|bar")
assert_eq("pure regex → no runs", table.concat(extract.literal_runs("\\d+"), "|"), "")

-- =========================================================================
-- extract.keys — only runs >= 2 contribute; pure-meta query is empty
-- =========================================================================
io.write("\n--- extract.keys ---\n")
assert_test("error has bigrams", #extract.keys("error") > 0)
assert_test("single chars → empty", #extract.keys("a.b") == 0, "each run is 1 byte → no bigrams")
assert_test("metachars only → empty", #extract.keys("(.)") == 0)
assert_eq("escaped query uses literal", #extract.keys("require\\("), #bigram.keys_of("require"))

-- =========================================================================
-- bitset add/query — AND of columns; false-negative guarantee
-- =========================================================================
io.write("\n--- bigram add/query ---\n")
local idx = bigram.new(8)
local files = {
	[0] = "local error = handler",
	[1] = "no match here at all",
	[2] = "another error path",
	[3] = "errno different word",
}
for id, content in pairs(files) do
	idx:add(id, content)
end

local cand = set_of(idx:query(extract.keys("error")))
-- Every file containing the literal MUST survive (no false negatives).
assert_test("file 0 (has error) survives", cand[0])
assert_test("file 2 (has error) survives", cand[2])
-- file 1 has none of error's bigrams → pruned.
assert_test("file 1 (no error) pruned", not cand[1])

-- All true matches present even if some non-matches leak through.
local truth = bigram.keys_of("error")
assert_test("AND keeps superset of matches", cand[0] and cand[2] and #truth > 0)

-- =========================================================================
-- fallback — keys absent from index → nil; empty query → empty keys
-- =========================================================================
io.write("\n--- fallback ---\n")
assert_eq("missing bigrams → nil (full scan)", idx:query(bigram.keys_of("zzqq")), nil)
assert_eq("pure metachar query → no keys", #extract.keys("\\("), 0)
assert_test("stats reports files/columns", idx:stats().files == 4 and idx:stats().columns > 0)

-- =========================================================================
-- index builder — chunked build over a temp dir; query → candidate paths
-- =========================================================================
io.write("\n--- index builder ---\n")
local index = require("beast.libs.finder.engine.index")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "local error_handler = 1" }, tmp .. "/a.lua")
vim.fn.writefile({ "no relevant content" }, tmp .. "/b.lua")
vim.fn.writefile({ "another error case" }, tmp .. "/c.lua")

local built
index.build(tmp, { max_files = 100, max_file_size = 1024 * 1024 }, function(i)
	built = i
end)
vim.wait(3000, function()
	return built ~= nil
end, 10)

assert_test("build completed + ready", built and built.ready)
if built then
	local hits = set_of(built:query("error"))
	assert_test("a.lua candidate", hits[tmp .. "/a.lua"])
	assert_test("c.lua candidate", hits[tmp .. "/c.lua"])
	assert_test("b.lua pruned", not hits[tmp .. "/b.lua"])
	assert_eq("pure-meta query → full scan", built:query("(.)"), nil)
	assert_test("get(root) returns ready index", index.get(tmp) == built)
	assert_test("report has files", index.report().files == 3)

	-- freshness: new file becomes searchable; deleted file tombstoned
	vim.fn.writefile({ "fresh error line" }, tmp .. "/d.lua")
	built:refresh(tmp .. "/d.lua")
	local h2 = set_of(built:query("error"))
	assert_test("new file d.lua searchable", h2[tmp .. "/d.lua"])
	vim.fn.delete(tmp .. "/a.lua")
	built:refresh(tmp .. "/a.lua")
	local h3 = set_of(built:query("error"))
	assert_test("deleted a.lua tombstoned", not h3[tmp .. "/a.lua"])
	-- many new files past the 32-slot pad: capacity from max_files holds, no loss
	for i = 1, 60 do
		local p = string.format("%s/z%02d.lua", tmp, i)
		vim.fn.writefile({ "unique zebra token" }, p)
		built:refresh(p)
	end
	assert_eq("60 new files all searchable", #built:query("zebra"), 60)
	built:stop()
end
vim.fn.delete(tmp, "rf")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
