---@diagnostic disable: param-type-mismatch

local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Picker lifecycle (open / reopen / close / reentrancy / callbacks), through the public surface only,
-- so it must keep passing while the finder's internals are refactored
-- (docs/dev-specs/finder-levels-refactor.md).

---Focus the window the picker was opened from (a main window), as the user does leaving the picker.
local function focus_main()
	n.exec_lua(function()
		vim.api.nvim_set_current_win(_G.main)
		FH.settle()
	end)
end

t.describe("finder lifecycle", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			FH.list_source("fake_a", { "a.lua", "b.lua", "c.lua" })
			FH.list_source("fake_b", { "x.lua", "y.lua" })
			_G.main = require("beast.libs.view").win.find_normal() or vim.api.nvim_get_current_win()
		end)
	end)

	t.after_each(F.close)

	t.describe("open", function()
		t.before_each(function()
			F.open("fake_a")
		end)

		t.it("shows input, list, preview and backdrop", function()
			t.eq(
				{ true, true, true, true },
				n.exec_lua(function()
					local panes = FH.panes()
					return { panes.input ~= nil, panes.list ~= nil, panes.preview ~= nil, panes.backdrop ~= nil }
				end)
			)
		end)

		t.it("opens exactly four picker windows", function()
			t.eq(4, F.window_count())
		end)

		t.it("lists the rows", function()
			t.eq(true, F.has_row("a.lua") and F.has_row("c.lua"))
		end)
	end)

	t.describe("opening again", function()
		t.before_each(function()
			F.open("fake_a")
			F.open("fake_b")
		end)

		t.it("keeps one set of windows", function()
			t.eq(4, F.window_count())
		end)

		t.it("shows the new source", function()
			t.eq(true, F.has_row("x.lua") and not F.has_row("a.lua"))
		end)
	end)

	t.describe("close", function()
		t.before_each(function()
			F.open("fake_a")
			F.close()
		end)

		t.it("removes the windows", function()
			t.eq(0, F.window_count())
		end)

		t.it("is idempotent", function()
			t.eq(
				true,
				n.exec_lua(function()
					return (pcall(FH.close))
				end)
			)
			t.eq(0, F.window_count())
		end)
	end)

	t.describe("options hide panes", function()
		local panes

		t.before_each(function()
			F.open("fake_a", { preview = false, backdrop = false })
			panes = n.exec_lua(function()
				local p = FH.panes()
				return { preview = p.preview ~= nil, backdrop = p.backdrop ~= nil, input = p.input ~= nil, list = p.list ~= nil }
			end)
		end)

		t.it("hides the preview", function()
			t.eq(false, panes.preview)
		end)

		t.it("hides the backdrop", function()
			t.eq(false, panes.backdrop)
		end)

		t.it("keeps input and list", function()
			t.eq(true, panes.input and panes.list)
		end)
	end)

	t.it("closes when focus leaves the picker", function()
		F.open("fake_a")
		focus_main()
		t.eq(0, F.window_count())
	end)

	t.describe("Esc and Ctrl-C", function()
		t.before_each(function()
			F.open("fake_a")
		end)

		t.it("<Esc> is mapped in normal mode and closes the picker", function()
			t.eq(true, F.press("<Esc>", { mode = "n" }))
			t.eq(0, F.window_count())
		end)

		t.it("<C-c> is mapped and closes the picker", function()
			t.eq(true, F.press("<C-c>", { mode = "i" }))
			t.eq(0, F.window_count())
		end)
	end)

	t.describe("on_close reports whether the user confirmed", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.closed_with, _G.opened = {}, {}
				require("beast.libs.finder.action").open = function(...)
					for _, arg in ipairs({ ... }) do
						if type(arg) == "table" and arg.text then
							table.insert(_G.opened, arg.text)
							return
						end
					end
				end
				_G.open_with_on_close = function()
					FH.open("fake_a", {
						on_close = function(confirmed)
							_G.closed_with[#_G.closed_with + 1] = confirmed
						end,
					})
				end
			end)
		end)

		t.it("says false when closed without Enter", function()
			n.exec_lua(function()
				_G.open_with_on_close()
				FH.close()
			end)
			t.eq(
				{ false },
				n.exec_lua(function()
					return _G.closed_with
				end)
			)
		end)

		t.it("says true on Enter", function()
			n.exec_lua(function()
				_G.open_with_on_close()
			end)
			F.press("<CR>")
			t.eq(
				{ true },
				n.exec_lua(function()
					return _G.closed_with
				end)
			)
		end)

		t.it("says false then true across two pickers", function()
			n.exec_lua(function()
				_G.open_with_on_close()
				FH.close()
				_G.open_with_on_close()
			end)
			F.press("<CR>")
			t.eq(
				{ false, true },
				n.exec_lua(function()
					return _G.closed_with
				end)
			)
		end)

		t.it("opens exactly the selected item on Enter", function()
			n.exec_lua(function()
				_G.open_with_on_close()
			end)
			F.press("<CR>")
			t.eq(
				{ "a.lua" },
				n.exec_lua(function()
					return _G.opened
				end)
			)
		end)
	end)

	t.it("starts on the row matching initial_text", function()
		n.exec_lua(function()
			_G.previewed = {}
			FH.open("fake_a", {
				initial_text = "b.lua",
				on_preview = function(item)
					_G.previewed[#_G.previewed + 1] = item.text
				end,
			})
			FH.wait(function()
				return #_G.previewed > 0
			end)
		end)
		t.eq(
			"b.lua",
			n.exec_lua(function()
				return _G.previewed[#_G.previewed]
			end)
		)
	end)

	-- The first picker is completely gone (windows, autocmds) before on_close runs, so the picker
	-- opened from it is not closed by the first one's teardown and does not share its autocmd group.
	t.describe("opening a picker from on_close (reentrancy)", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.open("fake_a", {
					on_close = function()
						require("beast.libs.finder").open("fake_b")
					end,
				})
			end)
		end)

		t.it("closes the first picker without error", function()
			t.eq(
				true,
				n.exec_lua(function()
					return (pcall(FH.close))
				end)
			)
		end)

		t.it("keeps the picker opened from on_close", function()
			F.close()
			F.settle()
			t.eq(4, F.window_count())
		end)

		t.it("shows its own rows", function()
			F.close()
			F.settle()
			t.eq(true, F.has_row("x.lua") and not F.has_row("a.lua"))
		end)

		t.it("still closes when focus leaves it (its autocmds are intact)", function()
			F.close()
			F.settle()
			focus_main()
			t.eq(0, F.window_count())
		end)

		t.it("closes cleanly when reopened and closed", function()
			F.close()
			F.settle()
			focus_main()
			F.open("fake_b")
			t.eq(
				true,
				n.exec_lua(function()
					return (pcall(FH.close))
				end)
			)
			t.eq(0, F.window_count())
		end)
	end)

	t.it("returns focus to the window the picker was opened from", function()
		F.open("fake_a")
		F.close()
		t.eq(
			true,
			n.exec_lua(function()
				return vim.api.nvim_get_current_win() == _G.main
			end)
		)
	end)
end)
