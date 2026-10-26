-- =========================================================================
-- Test: beast.libs.toast repeat merging ("xN" count)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-toast-repeat.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

local Record = require("beast.libs.toast.record")
local State = require("beast.libs.toast.state")
local config = require("beast.libs.toast.config")
local stack = require("beast.libs.toast.stack")
local toast = require("beast.libs.toast")
config.setup({ stagger = 5, anim_ms = 10, timeout = 300 })

-- The toast module owns its state privately; build a fresh one to inspect.
local function fresh()
	local state = State()
	local function push(msg, level, opts)
		stack.push(state, Record(state.next_id, msg, level, opts))
		state.next_id = state.next_id + 1
	end
	return state, push
end

local function settle(ms)
	vim.wait(ms or 80)
end

local function body(view)
	return vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)[1]
end

io.write("\n--- count_label ---\n")
assert_eq("x2", Record.count_label(2), "x2")
assert_eq("x99", Record.count_label(99), "x99")
assert_eq("x99+ from 100", Record.count_label(100), "x99+")
assert_eq("x99+ far above", Record.count_label(5000), "x99+")

io.write("\n--- merging ---\n")
do
	local state, push = fresh()
	push("Pattern not found: foo", "WARN", { title = "Search" })
	settle()
	push("Pattern not found: foo", "WARN", { title = "Search" })
	settle()
	assert_eq("one view for identical toasts", #state.views, 1)
	assert_eq("count is 2", state.views[1].record.count, 2)
	assert_eq("line shows the badge", body(state.views[1]):match("Pattern not found: foo x2") ~= nil, true)

	push("Pattern not found: foo", "WARN", { title = "Search" })
	settle()
	assert_eq("count climbs to 3", state.views[1].record.count, 3)

	push("Other", "WARN", { title = "Search" })
	settle()
	push("Pattern not found: foo", "WARN", { title = "Search" })
	settle()
	assert_eq("two views with a different toast in between", #state.views, 2)
	assert_eq("repeat merges into the older matching toast", state.views[1].record.count, 4)
	assert_eq("the other toast is untouched", state.views[2].record.count, 1)
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- identity ---\n")
do
	local state, push = fresh()
	push("Done", "INFO", { title = "Build" })
	push("Done", "INFO", { title = "Test" })
	push("Done", "WARN", { title = "Build" })
	settle(120)
	assert_eq("different title or level stay separate", #state.views, 3)
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- burst inside the stagger window ---\n")
do
	local state, push = fresh()
	for _ = 1, 5 do
		push("burst", "INFO")
	end
	settle(120)
	assert_eq("one view", #state.views, 1)
	assert_eq("count is 5", state.views[1].record.count, 5)
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- opt-outs ---\n")
do
	local state, push = fresh()
	push("sticky", "INFO", { timeout = false })
	push("sticky", "INFO", { timeout = false })
	push("segments", "INFO", { segments = { { text = "segments" } } })
	push("segments", "INFO", { segments = { { text = "segments" } } })
	push("no merge", "INFO", { merge = false })
	push("no merge", "INFO", { merge = false })
	settle(200)
	assert_eq("sticky, segment and merge=false toasts never merge", #state.views, 6)
	for _, v in ipairs(state.views) do
		if v.timer then
			v.timer:stop()
		end
	end
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- timer restart ---\n")
do
	local state, push = fresh()
	push("keepalive", "INFO") -- 300 ms timeout
	settle(30)
	vim.wait(200)
	push("keepalive", "INFO") -- repeat at ~230 ms: the original would die at 300 ms
	vim.wait(200) -- ~430 ms since first show, ~200 ms since repeat
	assert_eq("still visible after the original timeout", #state.views, 1)
	vim.wait(300)
	assert_eq("gone after the restarted window", #state.views, 0)
end

io.write("\n--- new toast after dismissal ---\n")
do
	local state, push = fresh()
	push("again", "INFO")
	push("again", "INFO")
	vim.wait(600)
	assert_eq("dismissed", #state.views, 0)
	push("again", "INFO")
	settle()
	assert_eq("starts at count 1", state.views[1] and state.views[1].record.count, 1)
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- repeat during fade-out ---\n")
do
	local state, push = fresh()
	push("fading", "INFO")
	settle()
	local first = state.views[1]
	stack.remove(state, first.record.id)
	assert_eq("view is closing", first.closing, true)
	push("fading", "INFO")
	settle(120)
	local open = 0
	for _, v in ipairs(state.views) do
		if not v.closing then
			open = open + 1
		end
	end
	assert_eq("repeat opens a new toast", open, 1)
	stack.dismiss(state)
	settle(150)
end

io.write("\n--- width grows with the badge ---\n")
do
	local one = Record(1, "a longer message here", "INFO")
	local many = Record(2, "a longer message here", "INFO")
	many.count = 14
	assert_eq("x14 adds 4 columns (space + 3 chars)", (many:dimensions()) - (one:dimensions()), 4)
end

pcall(toast.dismiss)
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
