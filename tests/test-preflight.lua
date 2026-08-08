-- =========================================================================
-- Test: beast.libs.finder.preflight (run a source to completion, no UI)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-preflight.lua
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

local preflight = require("beast.libs.finder.preflight")

---A fake source whose `get` only resolves once `resolve()` is called, so
---tests can control exactly when a check finishes relative to the next
---`check()` call (needed to exercise generation supersession).
---@param items table[]
local function deferred_source(items)
	local resolve
	local source = {
		get = function(_, cb)
			resolve = function()
				for _, it in ipairs(items) do
					cb(it)
				end
				cb(nil)
			end
		end,
	}
	return source, function()
		resolve()
	end
end

io.write("\n--- single item resolves ---\n")
do
	local source, resolve = deferred_source({ { text = "one" } })
	local got
	preflight.check(source, {}, function(items)
		got = items
	end)
	resolve()
	assert_eq("on_done receives 1 item", got and #got, 1)
	assert_eq("item content preserved", got and got[1].text, "one")
end

io.write("\n--- zero items resolves with an empty list ---\n")
do
	local source, resolve = deferred_source({})
	local got
	preflight.check(source, {}, function(items)
		got = items
	end)
	resolve()
	assert_eq("on_done receives 0 items", got and #got, 0)
end

io.write("\n--- a second check() supersedes a pending first one ---\n")
do
	local first_source, resolve_first = deferred_source({ { text = "stale" } })
	local first_called = false
	preflight.check(first_source, {}, function()
		first_called = true
	end)

	local second_source, resolve_second = deferred_source({ { text = "fresh" } })
	local second_result
	preflight.check(second_source, {}, function(items)
		second_result = items
	end)

	-- The first check resolves *after* the second one started, simulating a
	-- slow request that's still in flight when the user re-triggers.
	resolve_first()
	assert_test("superseded check's on_done never fires", not first_called)

	resolve_second()
	assert_eq("current check resolves normally", second_result and #second_result, 1)
	assert_eq("current check's item is the fresh one", second_result and second_result[1].text, "fresh")
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
