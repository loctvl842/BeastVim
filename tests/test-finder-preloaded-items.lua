-- =========================================================================
-- Test: pipeline/match.lua skips re-fetching when Query.items is preloaded
-- =========================================================================
-- Covers the Phase 3 optimization in docs/dev-specs/finder-auto-select.md:
-- when finder/init.lua's pre-flight already fetched the full result set
-- (more than one item), opening the picker must not call source.get() again.
--
-- Run as: nvim --clean --headless -l tests/test-finder-preloaded-items.lua
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

-- render.render() and ui.input's spinner need real floating windows this test
-- doesn't set up; match.lua only needs them callable, so stub both before
-- match.lua requires them (the not-preloaded control case below still runs
-- the spinner start/stop calls, just against a no-op).
package.loaded["beast.libs.finder.render"] = { render = function() end }
package.loaded["beast.libs.finder.ui"] = {
	input = {
		start_spinner = function() end,
		stop_spinner = function() end,
	},
}

local match_pipeline = require("beast.libs.finder.pipeline.match")

---@param items table[]
---@return Beast.Finder.ASource, fun(): integer get_call_count
local function fake_source(items)
	local call_count = 0
	local source = {
		async = true,
		get = function(_, cb)
			call_count = call_count + 1
			for _, it in ipairs(items) do
				cb(it)
			end
			cb(nil)
		end,
	}
	return source, function()
		return call_count
	end
end

---@param source Beast.Finder.ASource
---@param preloaded_items? table[]
local function make_state(source, preloaded_items)
	return {
		query = {
			source = source,
			items = preloaded_items or {},
			filter = { pattern = "", cwd = "/tmp", cur_win = 0 },
			matched = {},
		},
		view = {},
	}
end

io.write("\n--- preloaded items: source.get is never called ---\n")
do
	local source, get_call_count = fake_source({ { text = "a" }, { text = "b" } })
	local state = make_state(source, { { text = "a" }, { text = "b" } })

	match_pipeline.load(state)
	vim.wait(200, function()
		return #state.query.matched > 0
	end)

	assert_eq("source.get was not called", get_call_count(), 0)
	assert_eq("matched has both preloaded items", #state.query.matched, 2)
end

io.write("\n--- no preloaded items: source.get is called exactly once ---\n")
do
	local source, get_call_count = fake_source({ { text = "a" }, { text = "b" } })
	local state = make_state(source, nil)

	match_pipeline.load(state)
	vim.wait(200, function()
		return #state.query.matched > 0
	end)

	assert_eq("source.get was called once", get_call_count(), 1)
	assert_eq("matched has both streamed items", #state.query.matched, 2)
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
