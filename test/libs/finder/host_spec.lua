---@diagnostic disable: undefined-field, param-type-mismatch

local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-levels-refactor.md phase 1: the match and stream engines talk to a
-- `Beast.Finder.Host`, expose the full match set and a total, and drop every late callback once they
-- are aborted or the host is gone. Everything runs in the child with a headless host (no UI).

t.describe("finder pipelines without a UI", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			_G.Query = require("beast.libs.finder.query")
			_G.match = require("beast.libs.finder.pipeline.match")
			_G.stream = require("beast.libs.finder.pipeline.stream")
			local host_mod = require("beast.libs.finder.host")

			---A headless host that counts what the engine asked of it.
			_G.counting_host = function(extra)
				local c = { renders = 0, busy_log = {}, counts = {}, titles = {} }
				c.host = host_mod.headless(vim.tbl_extend("force", {
					render = function()
						c.renders = c.renders + 1
					end,
					busy = function(on)
						c.busy_log[#c.busy_log + 1] = on
					end,
					count = function(text)
						c.counts[#c.counts + 1] = text or "nil"
					end,
					title = function(text)
						c.titles[#c.titles + 1] = text
					end,
				}, extra or {}))
				return c
			end

			_G.make_items = function(count, name)
				local items = {}
				for i = 1, count do
					items[i] = {
						idx = i,
						score = 0,
						text = (name or "file") .. i .. ".lua",
						file = (name or "file") .. i .. ".lua",
					}
				end
				return items
			end

			_G.sync_source = function(items)
				return {
					live = false,
					async = false,
					get = function()
						return vim.deepcopy(items)
					end,
				}
			end

			_G.item = function(text)
				return { idx = 1, score = 0, text = text, file = text }
			end

			_G.texts_of = function(items)
				return vim.tbl_map(function(i)
					return i.text
				end, items)
			end
		end)
	end)

	t.describe("match engine: results beyond the display limit", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.c = _G.counting_host()
				_G.query = _G.Query(_G.sync_source(_G.make_items(1500)), { cwd = "/tmp" })
				_G.match.start(_G.query, _G.c.host)
				FH.wait(function()
					return not _G.query.matching and _G.query.total == 1500
				end)
			end)
		end)

		t.it("caps matched at the limit", function()
			t.eq(
				1000,
				n.exec_lua(function()
					return #_G.query.matched
				end)
			)
		end)

		t.it("counts every item in total", function()
			t.eq(
				1500,
				n.exec_lua(function()
					return _G.query.total
				end)
			)
		end)

		t.it("returns the whole set from matches() for an empty pattern", function()
			t.eq(
				1500,
				n.exec_lua(function()
					local all = _G.match.matches(_G.query)
					return all and #all
				end)
			)
		end)

		t.it("is neither loading nor matching", function()
			t.eq(
				{ false, false },
				n.exec_lua(function()
					return { _G.query.loading, _G.query.matching }
				end)
			)
		end)

		t.describe("with a pattern", function()
			local r

			t.before_each(function()
				r = n.exec_lua(function()
					_G.query.filter:update("file1")
					_G.match.run(_G.query, _G.c.host)
					FH.wait(function()
						return not _G.query.matching
					end)
					local matched_all = _G.match.matches(_G.query)
					local function subsequence(text, pattern)
						local i = 1
						for ch in text:gmatch(".") do
							if ch == pattern:sub(i, i) then
								i = i + 1
							end
						end
						return i > #pattern
					end
					local ok_only = true
					for _, item in ipairs(matched_all or {}) do
						ok_only = ok_only and subsequence(item.text, "file1")
					end
					local out = {
						total = _G.query.total,
						matches = matched_all and #matched_all,
						ok_only = ok_only,
					}
					_G.match.abort(_G.query)
					return out
				end)
			end)

			t.it("narrows the total", function()
				t.eq(true, r.total > 0 and r.total < 1500)
			end)

			t.it("agrees between matches() and total", function()
				t.eq(r.total, r.matches)
			end)

			t.it("returns matches() beyond the limit", function()
				t.eq(true, r.total > 1000 and r.matches > 1000 or r.total <= 1000)
			end)

			t.it("returns only real (fuzzy) matches", function()
				t.eq(true, r.ok_only)
			end)
		end)
	end)

	t.describe("match engine: limit option", function()
		local r

		t.before_each(function()
			r = n.exec_lua(function()
				local c = _G.counting_host()
				local q = _G.Query(_G.sync_source(_G.make_items(50)), { cwd = "/tmp", limit = 5 })
				_G.match.start(q, c.host)
				FH.wait(function()
					return not q.matching and q.total == 50
				end)
				local out = { matched = #q.matched, total = q.total, all = #(_G.match.matches(q) or {}) }
				_G.match.abort(q)
				return out
			end)
		end)

		t.it("honours the limit in matched", function()
			t.eq(5, r.matched)
		end)

		t.it("ignores it in total", function()
			t.eq(50, r.total)
		end)

		t.it("ignores it in matches()", function()
			t.eq(50, r.all)
		end)
	end)

	t.describe("match engine: matches() is nil while working", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.q3 = _G.Query({
					live = false,
					async = true,
					get = function(_, cb)
						_G.pending = cb
					end,
				}, { cwd = "/tmp" })
				_G.h3 = _G.counting_host()
				_G.match.start(_G.q3, _G.h3.host)
				FH.settle(50)
			end)
		end)

		t.it("is loading while the source is open", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.q3.loading
				end)
			)
		end)

		t.it("has no matches() while loading", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.match.matches(_G.q3) == nil
				end)
			)
		end)

		t.it("starts the spinner", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.h3.busy_log[1]
				end)
			)
		end)

		t.describe("once the source finishes", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.pending(_G.item("a.lua"))
					_G.pending(nil)
					FH.wait(function()
						return not _G.q3.loading
					end)
					FH.settle(50)
				end)
			end)

			t.it("is done loading", function()
				t.eq(
					false,
					n.exec_lua(function()
						return _G.q3.loading
					end)
				)
			end)

			t.it("has matches() again", function()
				t.eq(
					1,
					n.exec_lua(function()
						return #(_G.match.matches(_G.q3) or {})
					end)
				)
			end)

			t.it("stops the spinner", function()
				t.eq(
					false,
					n.exec_lua(function()
						return _G.h3.busy_log[#_G.h3.busy_log]
					end)
				)
			end)
		end)
	end)

	t.describe("match engine: preloaded items and aborted queries", function()
		t.it("knows the total at once for preloaded items", function()
			t.eq(
				30,
				n.exec_lua(function()
					local q = _G.Query(_G.sync_source({}), { cwd = "/tmp", preloaded_items = _G.make_items(30) })
					q.source.async = true
					_G.match.start(q, _G.counting_host().host)
					local total = q.total
					_G.match.abort(q)
					return total
				end)
			)
		end)

		t.it("has all preloaded items in matches()", function()
			t.eq(
				30,
				n.exec_lua(function()
					local q = _G.Query(_G.sync_source({}), { cwd = "/tmp", preloaded_items = _G.make_items(30) })
					q.source.async = true
					_G.match.start(q, _G.counting_host().host)
					FH.wait(function()
						return #q.matched == 30
					end)
					local count = #(_G.match.matches(q) or {})
					_G.match.abort(q)
					return count
				end)
			)
		end)

		t.it("never reports a partial set for an aborted mid-load query", function()
			t.eq(
				true,
				n.exec_lua(function()
					local q = _G.Query({
						live = false,
						async = true,
						get = function(_, cb)
							cb(_G.item("a.lua"))
						end,
					}, { cwd = "/tmp" })
					_G.match.start(q, _G.counting_host().host)
					FH.settle(60)
					_G.match.abort(q)
					return _G.match.matches(q) == nil
				end)
			)
		end)
	end)

	t.describe("match engine: a pattern typed while loading", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.hm = _G.counting_host()
				_G.qm = _G.Query({
					live = false,
					async = true,
					get = function(_, cb)
						cb({ idx = 1, score = 0, text = "keep1.lua", file = "keep1.lua" })
						cb({ idx = 2, score = 0, text = "skip1.lua", file = "skip1.lua" })
						_G.feed = cb
					end,
				}, { cwd = "/tmp" })
				_G.match.start(_G.qm, _G.hm.host)
				FH.settle(60)
				_G.qm.filter:update("keep")
				_G.match.run(_G.qm, _G.hm.host)
				FH.wait(function()
					return not _G.qm.matching
				end)
				_G.feed({ idx = 3, score = 0, text = "skip2.lua", file = "skip2.lua" })
				_G.feed({ idx = 4, score = 0, text = "keep2.lua", file = "keep2.lua" })
				FH.settle(100)
			end)
		end)

		t.it("is not overwritten by unscored arrivals", function()
			t.eq(
				{ "keep1.lua" },
				n.exec_lua(function()
					return _G.texts_of(_G.qm.matched)
				end)
			)
		end)

		t.describe("once loaded", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.feed(nil)
					FH.wait(function()
						return not _G.qm.loading and not _G.qm.matching
					end)
					FH.settle(100)
				end)
			end)

			t.it("shows everything that matches", function()
				t.eq(
					{ "keep1.lua", "keep2.lua" },
					n.exec_lua(function()
						local texts = _G.texts_of(_G.qm.matched)
						table.sort(texts)
						return texts
					end)
				)
			end)

			t.it("agrees with the full set", function()
				t.eq(
					2,
					n.exec_lua(function()
						return #(_G.match.matches(_G.qm) or {})
					end)
				)
			end)
		end)
	end)

	t.describe("match engine: an open but idle source", function()
		t.it("does not spin", function()
			local renders = n.exec_lua(function()
				local idle = _G.counting_host()
				local q = _G.Query({
					live = false,
					async = true,
					get = function(_, cb)
						cb(_G.item("a.lua"))
					end,
				}, { cwd = "/tmp" })
				_G.match.start(q, idle.host)
				FH.settle(400)
				_G.match.abort(q)
				return idle.renders
			end)
			t.eq(true, renders < 20)
		end)
	end)

	t.describe("match engine: late work is dropped", function()
		t.it("survives an answer after abort", function()
			t.eq(
				true,
				n.exec_lua(function()
					local c = _G.counting_host()
					local late
					local q = _G.Query({
						live = false,
						async = true,
						get = function(_, cb)
							late = cb
						end,
					}, { cwd = "/tmp" })
					_G.match.start(q, c.host)
					FH.settle(50)
					_G.match.abort(q)
					return (pcall(function()
						late(_G.item("late.lua"))
						late(nil)
						FH.settle(100)
					end))
				end)
			)
		end)

		t.it("does not render or add items after abort", function()
			t.eq(
				{ 0, 0 },
				n.exec_lua(function()
					local c = _G.counting_host()
					local late
					local q = _G.Query({
						live = false,
						async = true,
						get = function(_, cb)
							late = cb
						end,
					}, { cwd = "/tmp" })
					_G.match.start(q, c.host)
					FH.settle(50)
					_G.match.abort(q)
					local before = c.renders
					late(_G.item("late.lua"))
					late(nil)
					FH.settle(100)
					return { c.renders - before, #q.matched }
				end)
			)
		end)

		t.it("never renders to a host that is no longer alive", function()
			t.eq(
				0,
				n.exec_lua(function()
					local alive = true
					local c = _G.counting_host({
						alive = function()
							return alive
						end,
					})
					local q = _G.Query(_G.sync_source(_G.make_items(10)), { cwd = "/tmp" })
					_G.match.start(q, c.host)
					FH.wait(function()
						return c.renders > 0
					end)
					alive = false
					local renders = c.renders
					q.filter:update("file")
					_G.match.run(q, c.host)
					FH.settle(200)
					_G.match.abort(q)
					return c.renders - renders
				end)
			)
		end)
	end)

	t.describe("match engine: reload", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.gets = 0
				_G.c7 = _G.counting_host()
				_G.q7 = _G.Query({
					live = false,
					async = true,
					get = function(_, cb)
						_G.gets = _G.gets + 1
						cb(_G.item("gen" .. _G.gets .. ".lua"))
						cb(nil)
					end,
				}, { cwd = "/tmp" })
				_G.match.start(_G.q7, _G.c7.host)
				FH.wait(function()
					return not _G.q7.loading and #_G.q7.matched == 1
				end)
			end)
		end)

		t.it("loads the first time", function()
			t.eq(
				"gen1.lua",
				n.exec_lua(function()
					return _G.q7.matched[1] and _G.q7.matched[1].text
				end)
			)
		end)

		t.describe("when reloaded", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.match.reload(_G.q7, _G.c7.host)
					FH.wait(function()
						return _G.gets == 2 and not _G.q7.loading and _G.q7.matched[1] and _G.q7.matched[1].text == "gen2.lua"
					end)
				end)
			end)

			t.it("asks the source again", function()
				t.eq(
					2,
					n.exec_lua(function()
						return _G.gets
					end)
				)
			end)

			t.it("replaces the old items with the new ones", function()
				t.eq(
					{ "gen2.lua" },
					n.exec_lua(function()
						return _G.texts_of(_G.q7.matched)
					end)
				)
			end)
		end)
	end)

	t.describe("stream engine: results, count, title, staleness", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.calls = {}
				_G.h8 = _G.counting_host()
				_G.q8 = _G.Query({
					live = true,
					async = true,
					title = function(filter)
						return "T " .. filter.pattern
					end,
					count = function(items)
						return tostring(#items)
					end,
					get = function(filter, cb)
						_G.calls[#_G.calls + 1] = { pattern = filter.pattern, cb = cb }
					end,
					cancel = function() end,
				}, { cwd = "/tmp" })
				_G.q8.filter:update("a")
				_G.stream.run(_G.q8, _G.h8.host)
				_G.q8.filter:update("ab")
				_G.stream.run(_G.q8, _G.h8.host)
			end)
		end)

		t.it("starts two runs", function()
			t.eq(
				2,
				n.exec_lua(function()
					return #_G.calls
				end)
			)
		end)

		t.it("has no matches() while a run is open", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.stream.matches(_G.q8) == nil
				end)
			)
		end)

		t.it("follows the run in the title", function()
			t.eq(
				"T ab",
				n.exec_lua(function()
					return _G.h8.titles[#_G.h8.titles]
				end)
			)
		end)

		t.describe("after both runs answer", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.calls[1].cb({ idx = 1, score = 1, text = "old", file = "old" })
					_G.calls[1].cb(nil)
					_G.calls[2].cb({ idx = 1, score = 1, text = "new", file = "new" })
					_G.calls[2].cb(nil)
					FH.settle(100)
				end)
			end)

			t.it("keeps only the latest run's items", function()
				t.eq(
					{ "new" },
					n.exec_lua(function()
						return _G.texts_of(_G.q8.items)
					end)
				)
			end)

			t.it("follows the items in the total", function()
				t.eq(
					1,
					n.exec_lua(function()
						return _G.q8.total
					end)
				)
			end)

			t.it("has matches() after the run", function()
				t.eq(
					1,
					n.exec_lua(function()
						return #(_G.stream.matches(_G.q8) or {})
					end)
				)
			end)

			t.it("takes the count label from the source", function()
				t.eq(
					"1",
					n.exec_lua(function()
						return _G.h8.counts[#_G.h8.counts]
					end)
				)
			end)

			t.it("turns busy off", function()
				t.eq(
					false,
					n.exec_lua(function()
						return _G.h8.busy_log[#_G.h8.busy_log]
					end)
				)
			end)
		end)
	end)

	t.describe("stream engine: an empty prompt", function()
		local r

		t.before_each(function()
			r = n.exec_lua(function()
				local c = _G.counting_host()
				local q = _G.Query({
					live = true,
					async = true,
					get = function(_, cb)
						cb({ idx = 1, score = 1, text = "x", file = "x" })
					end,
					cancel = function() end,
				}, { cwd = "/tmp" })
				q.filter:update("x")
				_G.stream.run(q, c.host)
				q.filter:update("")
				_G.stream.run(q, c.host)
				FH.settle(100)
				local out = { items = #q.items, busy = c.busy_log[#c.busy_log] }
				_G.stream.abort(q)
				return out
			end)
		end)

		t.it("clears the results", function()
			t.eq(0, r.items)
		end)

		t.it("stops the spinner", function()
			t.eq(false, r.busy)
		end)
	end)

	t.describe("stream engine: callbacks after abort", function()
		local r

		t.before_each(function()
			r = n.exec_lua(function()
				local cbs = {}
				local c = _G.counting_host()
				local q = _G.Query({
					live = true,
					async = true,
					get = function(_, cb)
						cbs[#cbs + 1] = cb
					end,
					cancel = function() end,
				}, { cwd = "/tmp" })
				q.filter:update("x")
				_G.stream.run(q, c.host)
				_G.stream.abort(q)
				local renders = c.renders
				local ok = pcall(function()
					cbs[1]({ idx = 1, score = 1, text = "late", file = "late" })
					cbs[1](nil)
					FH.settle(100)
				end)
				return { ok = ok, renders = c.renders - renders, items = #q.items }
			end)
		end)

		t.it("do not error", function()
			t.eq(true, r.ok)
		end)

		t.it("do not render", function()
			t.eq(0, r.renders)
		end)

		t.it("add no items", function()
			t.eq(0, r.items)
		end)
	end)

	t.describe("stream engine: start", function()
		t.it("runs the initial query", function()
			t.eq(
				{ "is:pr " },
				n.exec_lua(function()
					local seen = {}
					local q = _G.Query({
						live = true,
						async = true,
						initial_query = "is:pr ",
						run_when_empty = true,
						get = function(filter, cb)
							seen[#seen + 1] = filter.pattern
							cb(nil)
						end,
						cancel = function() end,
					}, { cwd = "/tmp" })
					_G.stream.start(q, _G.counting_host().host)
					FH.settle(100)
					_G.stream.abort(q)
					return seen
				end)
			)
		end)
	end)
end)
