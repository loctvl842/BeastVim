-- =========================================================================
-- Test: key `cond`
-- =========================================================================
-- Covers docs/dev-specs/key-cond.md: a keymap spec's `cond` (boolean or
-- quick function) decides whether the keymap is registered. Toast is stubbed.
--
-- Run as: NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-key-cond.lua
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

local function assert_eq(name, got, expected)
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local toasts = {}
package.loaded["beast.libs.toast"] = setmetatable({}, {
	__call = function(_, msg, level, opts)
		toasts[#toasts + 1] = { msg = msg, level = level, opts = opts }
		return {}
	end,
})

local Key = require("beast.libs.key.core")

local function mapped(lhs, mode)
	return vim.fn.maparg(lhs, mode or "n", false, true).lhs ~= nil
end

local function registered(lhs, mode)
	local id = vim.api.nvim_replace_termcodes(lhs, true, true, true) .. " (" .. (mode or "n") .. ")"
	return Key.managed[id] ~= nil
end

local function noop() end

io.write("boolean cond\n")
Key.safe_set("n", "<leader>ca", noop, { desc = "cond true", cond = true })
assert_test("cond = true registers", mapped("<leader>ca") and registered("<leader>ca"))
Key.safe_set("n", "<leader>cb", noop, { desc = "cond false", cond = false })
assert_test("cond = false does not register", not mapped("<leader>cb") and not registered("<leader>cb"))
Key.safe_set("n", "<leader>cc", noop, { desc = "no cond" })
assert_test("no cond registers", mapped("<leader>cc") and registered("<leader>cc"))

io.write("quick function cond\n")
Key.safe_set("n", "<leader>cd", noop, {
	desc = "fn true",
	cond = function()
		return true
	end,
})
assert_test("function returning true registers", mapped("<leader>cd"))
Key.safe_set("n", "<leader>ce", noop, {
	desc = "fn false",
	cond = function()
		return false
	end,
})
assert_test("function returning false does not register", not mapped("<leader>ce") and not registered("<leader>ce"))
assert_eq("a plain false is silent", #toasts, 0)

local calls = 0
Key.safe_set("nv", "<leader>cf", noop, {
	desc = "multi-mode",
	cond = function()
		calls = calls + 1
		return true
	end,
})
assert_test("multi-mode registers every mode", mapped("<leader>cf", "n") and mapped("<leader>cf", "v"))
assert_eq("cond runs once per call, not per mode", calls, 1)

io.write("failing cond\n")
Key.safe_set("n", "<leader>cg", noop, {
	desc = "raises",
	cond = function()
		error("boom")
	end,
})
assert_test("a raising cond does not register", not mapped("<leader>cg") and not registered("<leader>cg"))
assert_eq("a raising cond toasts once", #toasts, 1)
assert_eq("the toast is a warning", toasts[1] and toasts[1].level, "WARN")
assert_test("the toast names the keymap", toasts[1] and toasts[1].msg:find("raises", 1, true) ~= nil, vim.inspect(toasts[1]))

Key.safe_set("n", "<leader>ch", noop, { desc = "returns nil", cond = function() end })
assert_test("a cond returning nothing counts as no", not mapped("<leader>ch"))

io.write("cond is not a map option\n")
local km = vim.fn.maparg("<leader>ca", "n", false, true)
assert_test("cond does not reach vim.keymap.set", km.cond == nil and km.desc == "cond true")
assert_test("opts() drops cond", Key.opts({ "<leader>x", noop, cond = true, desc = "d" }).cond == nil)

io.write("deleting ignores cond\n")
Key.safe_set("n", "<leader>ca", false, { cond = false })
assert_test("rhs = false deletes even when cond is false", not mapped("<leader>ca") and not registered("<leader>ca"))

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
