---@diagnostic disable: param-type-mismatch

local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Session + Level (docs/dev-specs/finder-levels-refactor.md, phase 3): a session shows a stack of
-- levels in the same windows. `push` remembers the current one, `pop` brings it back exactly as it
-- was (prompt, results, cursor) without searching again.

---Evaluate `fn` in the child and return its result (arguments as for `n.exec_lua`).
local function child(fn, ...)
	return n.exec_lua(fn, ...)
end

t.describe("finder session", function()
	t.before_each(function()
		F.setup()
		child(function()
			_G.Level = require("beast.libs.finder.level")
			_G.Session = require("beast.libs.finder.session")
			_G.a_gets = 0
			FH.fake_source("fake_a", {
				live = false,
				async = false,
				get = function()
					_G.a_gets = _G.a_gets + 1
					local items = {}
					for i = 1, 30 do
						items[i] = { idx = i, score = 0, text = ("a%02d.lua"):format(i), file = ("a%02d.lua"):format(i) }
					end
					return items
				end,
			})
			FH.list_source("fake_b", { "x1.lua", "x2.lua", "y1.lua" })
			---The windows of the picker by role.
			_G.wins = function()
				local out = {}
				for role, pane in pairs(FH.panes()) do
					out[role] = pane.win
				end
				return out
			end
		end)
	end)

	t.after_each(F.close)

	t.describe("a session", function()
		t.before_each(function()
			F.open("fake_a")
		end)

		t.it("is current once the picker is open", function()
			t.eq(
				true,
				child(function()
					return _G.Session.current() ~= nil
				end)
			)
		end)

		t.it("starts with one level, nothing stacked", function()
			t.eq(
				0,
				child(function()
					return #_G.Session.current().stack
				end)
			)
		end)

		t.it("knows its level's source", function()
			t.eq(
				"fake_a",
				child(function()
					return _G.Session.current().level.source.name
				end)
			)
		end)

		t.it("asks the source once", function()
			t.eq(
				1,
				child(function()
					return _G.a_gets
				end)
			)
		end)
	end)

	t.describe("push", function()
		t.before_each(function()
			F.open("fake_a")
			F.type("a1")
			F.press("<C-j>")
			F.press("<C-j>")
			F.settle(150)
			child(function()
				local session = _G.Session.current()
				_G.before = _G.wins()
				_G.cursor_before = session.view.list.cursor
				_G.rows_before = FH.rows()
				_G.parent_filtered = FH.has_row("a10.lua") and not FH.has_row("a02.lua")
				session:push(_G.Level.new("fake_b"))
				FH.settle(200)
			end)
		end)

		t.it("starts from the parent's filtered rows", function()
			t.eq(
				true,
				child(function()
					return _G.parent_filtered
				end)
			)
		end)

		t.it("shows the new level in the same windows", function()
			t.eq(
				true,
				child(function()
					return vim.deep_equal(_G.wins(), _G.before)
				end)
			)
		end)

		t.it("stacks one level", function()
			t.eq(
				1,
				child(function()
					return #_G.Session.current().stack
				end)
			)
		end)

		t.it("makes the new level current", function()
			t.eq(
				"fake_b",
				child(function()
					return _G.Session.current().level.source.name
				end)
			)
		end)

		t.it("shows the new level's rows", function()
			t.eq(true, F.has_row("x1.lua") and not F.has_row("a10.lua"))
		end)

		t.it("starts with an empty prompt", function()
			t.eq("", F.prompt())
		end)

		t.describe("then typing", function()
			t.before_each(function()
				F.type("y")
			end)

			t.it("filters the pushed level like any picker", function()
				t.eq(true, F.has_row("y1.lua") and not F.has_row("x1.lua"))
			end)

			t.it("does not ask the parent's source again", function()
				t.eq(
					1,
					child(function()
						return _G.a_gets
					end)
				)
			end)
		end)

		t.describe("then pop", function()
			t.before_each(function()
				child(function()
					_G.popped = _G.Session.current():pop()
					FH.settle(200)
				end)
			end)

			t.it("succeeds", function()
				t.eq(
					true,
					child(function()
						return _G.popped
					end)
				)
			end)

			t.it("keeps the same windows", function()
				t.eq(
					true,
					child(function()
						return vim.deep_equal(_G.wins(), _G.before)
					end)
				)
			end)

			t.it("goes back to one level", function()
				t.eq(
					0,
					child(function()
						return #_G.Session.current().stack
					end)
				)
			end)

			t.it("makes the parent current", function()
				t.eq(
					"fake_a",
					child(function()
						return _G.Session.current().level.source.name
					end)
				)
			end)

			t.it("brings its prompt back", function()
				t.eq("a1", F.prompt())
			end)

			t.it("brings its rows back", function()
				t.eq(
					true,
					child(function()
						return vim.deep_equal(FH.rows(), _G.rows_before)
					end)
				)
			end)

			t.it("brings its cursor back", function()
				t.eq(
					true,
					child(function()
						return _G.Session.current().view.list.cursor == _G.cursor_before
					end)
				)
			end)

			t.it("makes no search for it", function()
				t.eq(
					1,
					child(function()
						return _G.a_gets
					end)
				)
			end)

			t.it("has nothing left to pop", function()
				t.eq(
					false,
					child(function()
						return _G.Session.current():pop()
					end)
				)
			end)
		end)
	end)

	t.describe("late answers of a popped level", function()
		t.before_each(function()
			F.open("fake_a")
			F.type("a1")
			child(function()
				FH.fake_source("fake_stream", {
					live = true,
					async = true,
					debounce_ms = 10,
					get = function(_, cb)
						_G.pending = cb
					end,
					cancel = function() end,
				})
				_G.Session.current():push(_G.Level.new("fake_stream"))
			end)
			F.type("q")
			child(function()
				_G.late = _G.pending
				_G.Session.current():pop()
				FH.settle(100)
				_G.rows_now = FH.rows()
			end)
		end)

		t.it("started a search in the pushed level", function()
			t.eq(
				true,
				child(function()
					return _G.late ~= nil
				end)
			)
		end)

		t.describe("when delivered", function()
			local ok

			t.before_each(function()
				ok = child(function()
					return (
						pcall(function()
							_G.late({ idx = 1, score = 1, text = "late.lua", file = "late.lua" })
							_G.late(nil)
							FH.settle(150)
						end)
					)
				end)
			end)

			t.it("do not error", function()
				t.eq(true, ok)
			end)

			t.it("draw nothing over the parent", function()
				t.eq(
					true,
					child(function()
						return vim.deep_equal(FH.rows(), _G.rows_now)
					end)
				)
			end)

			t.it("leave the parent's rows intact", function()
				t.eq(true, F.has_row("a10.lua"))
			end)
		end)
	end)

	t.describe("closing", function()
		t.before_each(function()
			child(function()
				FH.fake_source("fake_async_open", {
					live = false,
					async = true,
					get = function(_, cb)
						_G.gate = cb
					end,
				})
			end)
			F.open("fake_async_open")
			child(function()
				_G.session = _G.Session.current()
				_G.root_cb = _G.gate
				_G.session:push(_G.Level.new("fake_b"))
			end)
			F.close()
		end)

		t.it("removes the windows", function()
			t.eq(0, F.window_count())
		end)

		t.it("leaves no current session", function()
			t.eq(
				true,
				child(function()
					return _G.Session.current() == nil
				end)
			)
		end)

		t.it("makes answers for the levels of a closed session do nothing", function()
			t.eq(
				true,
				child(function()
					return (
						pcall(function()
							_G.root_cb({ idx = 1, score = 0, text = "z.lua", file = "z.lua" })
							_G.root_cb(nil)
							FH.settle(100)
						end)
					)
				end)
			)
			t.eq(0, F.window_count())
		end)

		t.it("ignores push on a closed session", function()
			t.eq(
				true,
				child(function()
					return (pcall(function()
						_G.session:push(_G.Level.new("fake_b"))
					end))
				end)
			)
			t.eq(0, F.window_count())
		end)
	end)

	t.describe("autocmd groups", function()
		local r

		t.before_each(function()
			r = child(function()
				FH.open("fake_b")
				local first = _G.Session.current()
				local first_group = first.augroup
				FH.open("fake_b")
				local second = _G.Session.current()
				return {
					new_session = second ~= first,
					own_group = second.augroup ~= first_group and second.id ~= first.id,
					old_deleted = not pcall(vim.api.nvim_get_autocmds, { group = first_group }),
				}
			end)
		end)

		t.it("gives each open a new session", function()
			t.eq(true, r.new_session)
		end)

		t.it("gives each session its own group", function()
			t.eq(true, r.own_group)
		end)

		t.it("deletes the old group", function()
			t.eq(true, r.old_deleted)
		end)
	end)

	t.describe("the prompt write of a push or pop", function()
		t.before_each(function()
			child(function()
				_G.searches = {}
				FH.fake_source("fake_counting", {
					live = true,
					async = true,
					debounce_ms = 10,
					get = function(filter, cb)
						_G.searches[#_G.searches + 1] = filter.pattern
						cb({ idx = 1, score = 1, text = filter.pattern .. ".lua", file = filter.pattern .. ".lua" })
						cb(nil)
					end,
					cancel = function() end,
				})
			end)
			F.open("fake_counting")
			F.type("one")
		end)

		---@return string[]
		local function searches()
			return child(function()
				return _G.searches
			end)
		end

		t.it("types once", function()
			t.eq({ "one" }, searches())
		end)

		t.describe("then push and pop", function()
			t.before_each(function()
				child(function()
					local session = _G.Session.current()
					session:push(_G.Level.new("fake_b"))
					FH.settle(300)
					session:pop()
					FH.settle(400)
				end)
			end)

			t.it("causes no extra search", function()
				t.eq({ "one" }, searches())
			end)

			t.it("restores the prompt", function()
				t.eq("one", F.prompt())
			end)

			t.it("restores the rows", function()
				t.eq(true, F.has_row("one.lua"))
			end)

			t.it("still searches when typing afterwards", function()
				F.type("two")
				t.eq({ "one", "two" }, searches())
			end)
		end)
	end)
end)
