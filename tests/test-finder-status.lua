-- =========================================================================
-- Test: beast.libs.finder.status (pre-flight "checking" state + change event)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-finder-status.lua
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

local status = require("beast.libs.finder.status")

io.write("\n--- defaults ---\n")
assert_eq("action defaults nil", status.action, nil)

io.write("\n--- start(label) sets action and fires BeastFinderStatusChanged ---\n")
do
	local events = 0
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "BeastFinderStatusChanged",
		callback = function()
			events = events + 1
		end,
	})

	status.start("Definition")
	assert_eq("action set", status.action, "Definition")
	assert_eq("one event fired", events, 1)

	status.stop()
	vim.api.nvim_del_autocmd(id)
end

io.write("\n--- start() again while active relabels without a second timer ---\n")
do
	local events = 0
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "BeastFinderStatusChanged",
		callback = function()
			events = events + 1
		end,
	})

	status.start("References")
	assert_eq("first label applied", status.action, "References")
	status.start("Declaration")
	assert_eq("second label overwrites the first", status.action, "Declaration")
	assert_eq("two events fired (one per start())", events, 2)

	status.stop()
	vim.api.nvim_del_autocmd(id)
end

io.write("\n--- stop() clears action and fires the event once more ---\n")
do
	-- events[] tracks the observed `action` at each firing; a plain counter
	-- (not #events) counts firings, since stop()'s event observes action
	-- already nil and assigning nil into an array slot doesn't grow it.
	local fire_count = 0
	local events = {}
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "BeastFinderStatusChanged",
		callback = function()
			fire_count = fire_count + 1
			events[fire_count] = status.action
		end,
	})

	status.start("Implementation")
	status.stop()
	assert_eq("action cleared", status.action, nil)
	assert_eq("two events fired (start + stop)", fire_count, 2)
	assert_eq("start's event observed action set", events[1], "Implementation")
	assert_eq("stop's event observes action already nil", events[2], nil)

	vim.api.nvim_del_autocmd(id)
end

io.write("\n--- read-only proxy rejects direct assignment ---\n")
local ok = pcall(function()
	status.action = "Definition"
end)
assert_test("direct assignment errors", not ok, "expected an error, assignment succeeded silently")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
