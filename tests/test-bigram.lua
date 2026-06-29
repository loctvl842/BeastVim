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

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
