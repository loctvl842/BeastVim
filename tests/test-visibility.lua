-- =========================================================================
-- Test: beast.visibility (global hidden/gitignored state + change event)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-visibility.lua
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

local visibility = require("beast.visibility")

io.write("\n--- defaults ---\n")
assert_eq("hidden defaults false", visibility.hidden, false)
assert_eq("gitignored defaults false", visibility.gitignored, false)

io.write("\n--- toggle_hidden fires BeastVisibilityChanged with the post-toggle value ---\n")
do
	local events = {}
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "BeastVisibilityChanged",
		callback = function(ev)
			events[#events + 1] = ev.data
		end,
	})

	visibility.toggle_hidden()
	assert_eq("hidden flips to true", visibility.hidden, true)
	assert_eq("gitignored untouched by toggle_hidden", visibility.gitignored, false)
	assert_eq("one event fired", #events, 1)
	assert_eq("event key is 'hidden'", events[1] and events[1].key, "hidden")
	assert_eq("event value matches new state", events[1] and events[1].value, true)

	visibility.toggle_hidden()
	assert_eq("hidden flips back to false", visibility.hidden, false)
	assert_eq("second event value is false", events[2] and events[2].value, false)

	vim.api.nvim_del_autocmd(id)
end

io.write("\n--- toggle_gitignored fires BeastVisibilityChanged independently ---\n")
do
	local events = {}
	local id = vim.api.nvim_create_autocmd("User", {
		pattern = "BeastVisibilityChanged",
		callback = function(ev)
			events[#events + 1] = ev.data
		end,
	})

	visibility.toggle_gitignored()
	assert_eq("gitignored flips to true", visibility.gitignored, true)
	assert_eq("hidden untouched by toggle_gitignored", visibility.hidden, false)
	assert_eq("event key is 'gitignored'", events[1] and events[1].key, "gitignored")
	assert_eq("event value matches new state", events[1] and events[1].value, true)

	visibility.toggle_gitignored()
	assert_eq("gitignored flips back to false", visibility.gitignored, false)

	vim.api.nvim_del_autocmd(id)
end

io.write("\n--- setup(opts) merges initial overrides ---\n")
visibility.setup({ hidden = true })
assert_eq("setup applies hidden override", visibility.hidden, true)
assert_eq("setup leaves gitignored at its default", visibility.gitignored, false)
visibility.setup({}) -- reset back to defaults for the next check

io.write("\n--- read-only proxy rejects direct assignment ---\n")
local ok = pcall(function()
	visibility.hidden = true
end)
assert_test("direct assignment errors", not ok, "expected an error, assignment succeeded silently")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
