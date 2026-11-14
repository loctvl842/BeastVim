-- =========================================================================
-- Test: beast.libs.review.server.identity + Review.start() port restore
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-review-identity.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
-- Keep every file this test writes out of the real state and ~/.claude dirs.
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.CLAUDE_CONFIG_DIR = root .. "/claude"

local identity = require("beast.libs.review.server.identity")
local lockfile = require("beast.libs.review.server.lockfile")
local review = require("beast.libs.review")

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

local function assert_eq(name, got, expected)
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local TOKEN = "a3f1c2d4e5f60718293a4b5c6d7e8f90"

local function lock_token(port)
	local f = assert(io.open(lockfile.path(port), "rb"))
	local data = vim.json.decode(f:read("*a"))
	f:close()
	return data.authToken
end

print("== identity: store ==")
do
	assert_eq("nothing saved yet", identity.load("/work/a"), nil)
	assert_test("save succeeds", identity.save("/work/a", 51234, TOKEN))
	assert_eq("round trip", identity.load("/work/a"), { port = 51234, token = TOKEN })
	assert_eq("other directory is separate", identity.load("/work/b"), nil)

	local mode = vim.uv.fs_stat(identity.path("/work/a")).mode % 512
	assert_eq("file is 0600", mode, tonumber("600", 8))

	for name, body in pairs({
		garbage = "not json",
		bad_port = vim.json.encode({ port = 70000, token = TOKEN }),
		fractional_port = vim.json.encode({ port = 80.5, token = TOKEN }),
		short_token = vim.json.encode({ port = 8000, token = "abc" }),
		non_hex_token = vim.json.encode({ port = 8000, token = ("z"):rep(32) }),
	}) do
		local f = assert(io.open(identity.path("/work/c"), "wb"))
		f:write(body)
		f:close()
		assert_eq("rejects " .. name, identity.load("/work/c"), nil)
	end
end

print("== Review.start: restart comes back on the same address ==")
do
	assert_test("first start", review.start())
	local first = review.status()
	local token = lock_token(first.port)
	assert_eq("identity saved", identity.load(vim.fn.getcwd()), { port = first.port, token = token })

	review.stop()
	assert_test("lock file removed on stop", vim.uv.fs_stat(lockfile.path(first.port)) == nil)

	assert_test("second start", review.start())
	local second = review.status()
	assert_eq("same port", second.port, first.port)
	assert_eq("same token", lock_token(second.port), token)
	review.stop()
end

print("== Review.start: saved port taken -> fresh address, saved identity kept ==")
do
	local saved = assert(identity.load(vim.fn.getcwd()))
	local squatter = vim.uv.new_tcp()
	assert(squatter:bind("127.0.0.1", saved.port))
	squatter:listen(1, function() end)

	assert_test("start still succeeds", review.start())
	local s = review.status()
	assert_test("serves on a different port", s.port ~= saved.port)
	assert_test("uses a fresh token", lock_token(s.port) ~= saved.token)
	assert_eq("saved identity untouched", identity.load(vim.fn.getcwd()), saved)
	review.stop()
	squatter:close()
end

vim.fn.delete(root, "rf")
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
