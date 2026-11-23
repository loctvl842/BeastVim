local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder preflight", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			---A fake source whose `get` only resolves once `resolve()` is called, so
			---tests control exactly when a check finishes relative to the next `check()`
			---(needed to exercise generation supersession).
			_G.deferred_source = function(items)
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
		end)
	end)

	t.it("resolves a single item", function()
		t.eq(
			{ count = 1, text = "one" },
			n.exec_lua(function()
				local preflight = require("beast.libs.finder.preflight")
				local source, resolve = _G.deferred_source({ { text = "one" } })
				local got
				preflight.check(source, {}, function(items)
					got = items
				end)
				resolve()
				return { count = got and #got, text = got and got[1].text }
			end)
		)
	end)

	t.it("resolves zero items with an empty list", function()
		t.eq(
			0,
			n.exec_lua(function()
				local preflight = require("beast.libs.finder.preflight")
				local source, resolve = _G.deferred_source({})
				local got
				preflight.check(source, {}, function(items)
					got = items
				end)
				resolve()
				return got and #got
			end)
		)
	end)

	t.describe("a second check() superseding a pending first one", function()
		---@return table
		local function run()
			return n.exec_lua(function()
				local preflight = require("beast.libs.finder.preflight")
				local first_source, resolve_first = _G.deferred_source({ { text = "stale" } })
				local first_called = false
				preflight.check(first_source, {}, function()
					first_called = true
				end)

				local second_source, resolve_second = _G.deferred_source({ { text = "fresh" } })
				local second_result
				preflight.check(second_source, {}, function(items)
					second_result = items
				end)

				-- The first check resolves after the second started, like a slow
				-- request still in flight when the user re-triggers.
				resolve_first()
				local first_after_stale = first_called
				resolve_second()
				return {
					first_called = first_after_stale,
					count = second_result and #second_result,
					text = second_result and second_result[1].text,
				}
			end)
		end

		t.it("never fires the superseded on_done", function()
			t.eq(false, run().first_called)
		end)

		t.it("resolves the current check with the fresh item", function()
			local r = run()
			t.eq(1, r.count)
			t.eq("fresh", r.text)
		end)
	end)
end)
