local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder pipelines", function()
	t.before_each(F.setup)

	t.after_each(F.close)

	t.describe("match pipeline: sync source", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.list_source("fake_sync", { "alpha.lua", "beta.lua", "gamma.lua", "delta/beta2.lua" })
			end)
			F.open("fake_sync")
		end)

		t.it("lists everything on an empty prompt, in source order", function()
			t.eq(true, F.has_row("alpha.lua") and F.has_row("gamma.lua") and F.has_row("beta2.lua"))
			t.eq(true, F.rows()[1]:find("alpha", 1, true) ~= nil)
		end)

		t.it("filters while typing", function()
			F.type("beta")
			t.eq(true, F.has_row("beta.lua") and F.has_row("beta2.lua"))
			t.eq(false, F.has_row("alpha.lua") or F.has_row("gamma.lua"))
		end)

		t.it("matches a subsequence fuzzily", function()
			F.type("gmm")
			t.eq(true, F.has_row("gamma.lua"))
			t.eq(false, F.has_row("beta.lua"))
		end)

		t.it("shows no rows when nothing matches", function()
			F.type("zzz")
			t.eq(false, F.has_row("alpha.lua") or F.has_row("gamma.lua") or F.has_row("beta"))
		end)

		t.it("restores the list when the prompt is cleared", function()
			F.type("zzz")
			F.type("")
			t.eq(true, F.has_row("alpha.lua") and F.has_row("gamma.lua"))
		end)

		t.it("keeps the right rows when a query narrows", function()
			F.type("alp")
			F.type("alph")
			t.eq(true, F.has_row("alpha.lua"))
			t.eq(false, F.has_row("beta.lua"))
		end)
	end)

	t.describe("match pipeline: async source", function()
		-- NOTE: a source that stays open without delivering items makes today's match loader spin and
		-- re-render on every loop tick, so these sources deliver in short bursts and finish.
		t.describe("streaming in bursts", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.got = 0
					FH.fake_source("fake_async", {
						live = false,
						async = true,
						get = function(_, cb)
							_G.got = _G.got + 1
							cb({ idx = 1, score = 0, text = "one.lua", file = "one.lua" })
							cb({ idx = 2, score = 0, text = "two.lua", file = "two.lua" })
							vim.defer_fn(function()
								cb({ idx = 3, score = 0, text = "three.lua", file = "three.lua" })
								cb(nil)
							end, 40)
						end,
					})
				end)
				F.open("fake_async")
				n.exec_lua(function()
					FH.wait(function()
						return FH.has_row("three.lua")
					end, 2000)
				end)
			end)

			t.it("asks the source once and shows the streamed items", function()
				t.eq(1, n.exec_lua("return _G.got"))
				t.eq(true, F.has_row("one.lua") and F.has_row("two.lua") and F.has_row("three.lua"))
			end)

			t.it("filters the streamed items while typing", function()
				F.type("thr")
				t.eq(true, F.has_row("three.lua"))
				t.eq(false, F.has_row("one.lua"))
			end)
		end)

		t.it("drops a late answer that arrives after the picker is gone", function()
			n.exec_lua(function()
				_G.closed_early = 0
				FH.fake_source("fake_async_late", {
					live = false,
					async = true,
					get = function(_, cb)
						vim.defer_fn(function()
							_G.closed_early = _G.closed_early + 1
							cb({ idx = 1, score = 0, text = "late.lua", file = "late.lua" })
							cb(nil)
						end, 60)
					end,
				})
			end)
			F.open("fake_async_late", { backdrop = false })
			F.close()
			F.settle(200)
			t.eq(1, n.exec_lua("return _G.closed_early"))
			t.eq(0, F.window_count())
		end)
	end)

	t.describe("match pipeline: a visibility change", function()
		t.it("re-reads an async source and shows the new items only", function()
			n.exec_lua(function()
				_G.reload_gets = 0
				FH.fake_source("fake_async_reload", {
					live = false,
					async = true,
					get = function(_, cb)
						_G.reload_gets = _G.reload_gets + 1
						local name = "gen" .. _G.reload_gets .. ".lua"
						cb({ idx = 1, score = 0, text = name, file = name })
						cb(nil)
					end,
				})
			end)
			F.open("fake_async_reload")
			t.eq(true, F.has_row("gen1.lua"))
			n.exec_lua(function()
				vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", modeline = false })
				FH.wait(function()
					return FH.has_row("gen2.lua")
				end, 2000)
			end)
			t.eq(2, n.exec_lua("return _G.reload_gets"))
			t.eq(true, F.has_row("gen2.lua"))
			t.eq(false, F.has_row("gen1.lua"))
		end)
	end)

	t.describe("stream pipeline: one search per prompt change", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.calls, _G.cancels = {}, 0
				FH.fake_source("fake_live", {
					live = true,
					async = true,
					debounce_ms = 10,
					get = function(filter, cb)
						_G.calls[#_G.calls + 1] = filter.pattern
						cb({ idx = 1, score = 1, text = filter.pattern .. "-1", file = filter.pattern .. "-1" })
						cb({ idx = 2, score = 1, text = filter.pattern .. "-2", file = filter.pattern .. "-2" })
						cb(nil)
					end,
					cancel = function()
						_G.cancels = _G.cancels + 1
					end,
				})
			end)
			F.open("fake_live")
		end)

		t.it("searches nothing and shows nothing on an empty prompt", function()
			t.eq(0, n.exec_lua("return #_G.calls"))
			t.eq(false, F.has_row("-1"))
		end)

		t.it("runs the source with the prompt text and shows results as they are", function()
			F.type("ab")
			t.eq("ab", n.exec_lua("return _G.calls[#_G.calls]"))
			t.eq(true, F.has_row("ab-1") and F.has_row("ab-2"))
		end)

		t.it("searches again on each change and replaces the previous results", function()
			F.type("ab")
			F.type("abc")
			t.eq("abc", n.exec_lua("return _G.calls[#_G.calls]"))
			t.eq(true, F.has_row("abc-1"))
			t.eq(false, F.has_row("ab-1"))
		end)

		t.it("cancels the running search before each new one", function()
			F.type("ab")
			F.type("abc")
			t.eq(true, n.exec_lua("return _G.cancels >= 2"))
		end)

		t.it("clears the list on an empty prompt", function()
			F.type("ab")
			F.type("abc")
			F.type("")
			t.eq(false, F.has_row("abc-1"))
		end)
	end)

	t.describe("stream pipeline: manual sources", function()
		t.it("drops the answers of a replaced search", function()
			n.exec_lua(function()
				_G.pending = {}
				FH.fake_source("fake_manual", {
					live = true,
					async = true,
					debounce_ms = 10,
					get = function(_, cb)
						_G.pending[#_G.pending + 1] = cb
					end,
					cancel = function() end,
				})
			end)
			F.open("fake_manual")
			F.type("a")
			F.type("ab")
			t.eq(2, n.exec_lua("return #_G.pending"))
			n.exec_lua(function()
				_G.pending[1]({ idx = 1, score = 1, text = "old.lua", file = "old.lua" })
				_G.pending[1](nil)
				_G.pending[2]({ idx = 1, score = 1, text = "new.lua", file = "new.lua" })
				_G.pending[2](nil)
			end)
			F.settle(300)
			t.eq(true, F.has_row("new.lua"))
			t.eq(false, F.has_row("old.lua"))
		end)

		t.it("keeps the old list until new items arrive with retain_results", function()
			n.exec_lua(function()
				_G.pending = {}
				FH.fake_source("fake_retain", {
					live = true,
					async = true,
					retain_results = true,
					debounce_ms = 10,
					get = function(_, cb)
						_G.pending[#_G.pending + 1] = cb
					end,
					cancel = function() end,
				})
			end)
			F.open("fake_retain")
			F.type("a")
			n.exec_lua(function()
				_G.pending[1]({ idx = 1, score = 1, text = "first.lua", file = "first.lua" })
				_G.pending[1](nil)
			end)
			F.settle(200)
			t.eq(true, F.has_row("first.lua"))
			F.type("ab")
			t.eq(true, F.has_row("first.lua"))
			n.exec_lua(function()
				_G.pending[2]({ idx = 1, score = 1, text = "second.lua", file = "second.lua" })
				_G.pending[2](nil)
			end)
			F.settle(300)
			t.eq(true, F.has_row("second.lua"))
			t.eq(false, F.has_row("first.lua"))
		end)

		t.it("searches at once with initial_query and fills the prompt", function()
			n.exec_lua(function()
				_G.seen = {}
				FH.fake_source("fake_initial", {
					live = true,
					async = true,
					initial_query = "q ",
					run_when_empty = true,
					debounce_ms = 10,
					get = function(filter, cb)
						_G.seen[#_G.seen + 1] = filter.pattern
						cb({ idx = 1, score = 1, text = "hit.lua", file = "hit.lua" })
						cb(nil)
					end,
					cancel = function() end,
				})
			end)
			F.open("fake_initial")
			t.eq({ "q " }, n.exec_lua("return _G.seen"))
			t.eq("q ", F.prompt())
			t.eq(true, F.has_row("hit.lua"))
		end)
	end)
end)
