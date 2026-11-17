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

io.write("cond is not a map option\n")
local km = vim.fn.maparg("<leader>ca", "n", false, true)
assert_test("cond does not reach vim.keymap.set", km.cond == nil and km.desc == "cond true")
assert_test("opts() drops cond", Key.opts({ "<leader>x", noop, cond = true, desc = "d" }).cond == nil)

io.write("deleting ignores cond\n")
Key.safe_set("n", "<leader>ca", false, { cond = false })
assert_test("rhs = false deletes even when cond is false", not mapped("<leader>ca") and not registered("<leader>ca"))

-- ---------------------------------------------------------------------------
-- slow conditions
-- ---------------------------------------------------------------------------
local Cond = require("beast.libs.key.cond")

local function reset_toasts()
	for i = #toasts, 1, -1 do
		toasts[i] = nil
	end
end

---A slow cond whose `done` the test calls by hand.
local function slow()
	local h = {}
	h.cond = function(done)
		h.done = done
	end
	return h
end

local function press(lhs, mode)
	local km = vim.fn.maparg(lhs, mode or "n", false, true)
	km.callback()
end

local function settle(until_fn)
	return vim.wait(500, until_fn, 5)
end

io.write("slow cond: placeholder\n")
do
	reset_toasts()
	local ran, h = 0, slow()
	Key.safe_set("n", "<leader>sa", function()
		ran = ran + 1
	end, { desc = "Pull requests", cond = h.cond })
	assert_test("the key exists while the check runs", mapped("<leader>sa") and registered("<leader>sa"))
	press("<leader>sa")
	assert_eq("pressing the placeholder does not run the action", ran, 0)
	assert_eq("pressing the placeholder toasts once", #toasts, 1)
	assert_test("the toast says it is still checking", toasts[1].msg == "Pull requests: still checking", vim.inspect(toasts[1]))
	assert_eq("the placeholder is in the conflict history once", #Key.conflicts[Key.id("<leader>sa", "n")].calls, 1)

	h.done(true)
	assert_test(
		"a yes swaps in the real action",
		settle(function()
			press("<leader>sa")
			return ran > 0
		end)
	)
	assert_eq("the swap adds no conflict record", #Key.conflicts[Key.id("<leader>sa", "n")].calls, 1)
	local warned = vim.tbl_filter(function(t)
		return t.level == "WARN"
	end, toasts)
	assert_eq("a yes raises no warning", #warned, 0)
end

io.write("slow cond: no\n")
do
	reset_toasts()
	local h = slow()
	Key.safe_set("n", "<leader>sb", noop, { desc = "slow no", cond = h.cond })
	h.done(false)
	assert_test(
		"a no removes the placeholder",
		settle(function()
			return not mapped("<leader>sb") and not registered("<leader>sb")
		end)
	)
	assert_eq("a plain no is silent", #toasts, 0)
end

io.write("slow cond: done answers from a process callback\n")
do
	local ran = 0
	Key.safe_set("n", "<leader>sc", function()
		ran = ran + 1
	end, {
		desc = "from a timer",
		cond = function(done)
			local timer = vim.uv.new_timer()
			timer:start(10, 0, function()
				timer:close()
				done(true)
			end)
		end,
	})
	assert_test(
		"the answer arrives from a fast callback",
		settle(function()
			press("<leader>sc")
			return ran > 0
		end)
	)
end

io.write("slow cond: only the first answer counts\n")
do
	local ran, h = 0, slow()
	Key.safe_set("n", "<leader>sd", function()
		ran = ran + 1
	end, { desc = "twice", cond = h.cond })
	h.done(true)
	h.done(false)
	settle(function()
		return false
	end)
	assert_test("a second done is ignored", mapped("<leader>sd"))
end

io.write("slow cond: done called before the function returns\n")
do
	local ran = 0
	Key.safe_set("n", "<leader>se", function()
		ran = ran + 1
	end, {
		desc = "sync done",
		cond = function(done)
			done(true)
		end,
	})
	press("<leader>se")
	assert_eq("an answer given at once registers the real keymap, no placeholder", ran, 1)
end

io.write("slow cond: timeout and errors\n")
do
	reset_toasts()
	Cond.timeout_ms = 50
	local h = slow()
	Key.safe_set("n", "<leader>sf", noop, { desc = "hangs", cond = h.cond })
	assert_test(
		"a check that never answers is removed",
		settle(function()
			return not mapped("<leader>sf")
		end)
	)
	assert_eq("a timeout toasts once", #toasts, 1)
	assert_eq("the timeout toast is a warning", toasts[1].level, "WARN")
	assert_test("the timeout toast says why", toasts[1].msg:find("hangs disabled: check timed out", 1, true) ~= nil, vim.inspect(toasts[1]))
	h.done(true)
	settle(function()
		return false
	end)
	assert_test("an answer after the timeout is thrown away", not mapped("<leader>sf"))
	Cond.timeout_ms = 10000
end

io.write("slow cond: superseded or deleted while pending\n")
do
	local first, second = 0, 0
	local h = slow()
	Key.safe_set("n", "<leader>sg", function()
		first = first + 1
	end, { desc = "old", cond = h.cond })
	Key.safe_set("n", "<leader>sg", function()
		second = second + 1
	end, { desc = "new" })
	h.done(true)
	settle(function()
		return false
	end)
	press("<leader>sg")
	assert_test("the newer registration is not overwritten by the late yes", first == 0 and second == 1)

	local h2 = slow()
	Key.safe_set("n", "<leader>sh", noop, { desc = "to delete", cond = h2.cond })
	Key.safe_set("n", "<leader>sh", false)
	h2.done(true)
	settle(function()
		return false
	end)
	assert_test("a deleted key is not brought back by a late yes", not mapped("<leader>sh") and not registered("<leader>sh"))

	local h3 = slow()
	Key.safe_set("n", "<leader>si", noop, { desc = "replaced then no", cond = h3.cond })
	Key.safe_set("n", "<leader>si", noop, { desc = "newer" })
	h3.done(false)
	settle(function()
		return false
	end)
	assert_test("a late no does not remove a newer registration", mapped("<leader>si"))
end

io.write("slow cond: buffer-local\n")
do
	local buf = vim.api.nvim_create_buf(true, false)
	local other = vim.api.nvim_create_buf(true, false)
	local h, h_other = slow(), slow()
	Key.safe_set("n", "<leader>sj", noop, { desc = "local", buffer = buf, cond = h.cond })
	Key.safe_set("n", "<leader>sj", noop, { desc = "local", buffer = other, cond = h_other.cond })
	assert_eq("each buffer is checked on its own", type(h.done) == "function" and type(h_other.done) == "function", true)
	vim.api.nvim_buf_delete(buf, { force = true })
	h.done(true)
	h_other.done(false)
	settle(function()
		return false
	end)
	assert_test("the late answer of a closed buffer is thrown away without an error", not vim.api.nvim_buf_is_valid(buf))
	local has_map = vim.api.nvim_buf_call(other, function()
		return mapped("<leader>sj")
	end)
	assert_test("a no for one buffer removes only that buffer's placeholder", not has_map)
end

io.write("slow cond: label-only entry and several modes\n")
do
	local h = slow()
	Key.safe_set("n", "<leader>sk", nil, { group = "Slow group", cond = h.cond })
	assert_test("a label gets no placeholder while the check runs", not registered("<leader>sk"))
	h.done(true)
	assert_test(
		"a label is listed once the check says yes",
		settle(function()
			return registered("<leader>sk")
		end)
	)

	local ran, hm = 0, slow()
	Key.safe_set("nv", "<leader>sl", function()
		ran = ran + 1
	end, { desc = "multi", cond = hm.cond })
	assert_test("every mode gets a placeholder", mapped("<leader>sl", "n") and mapped("<leader>sl", "v"))
	hm.done(true)
	settle(function()
		press("<leader>sl", "v")
		return ran > 0
	end)
	assert_test("every mode is swapped on yes", ran > 0)
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
