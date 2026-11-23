local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Characterizes which key does what in which pane, through the real mappings, so the key-table
-- rewrite (docs/dev-specs/finder-levels-refactor.md, phase 4) stays equivalent.
-- (The list pane's <C-v> used to open a horizontal split; it is a vertical split like the other panes since phase 4.)

---Open a fresh picker and track which item the preview was last asked to show (`_G.last`).
local function fresh()
	n.exec_lua(function()
		_G.last = nil
		FH.open("fake_keys", {
			on_preview = function(item)
				_G.last = item.text
			end,
		})
		FH.settle(150)
	end)
end

---The item the preview was last asked to show, once it has caught up with `want`.
---@param want string
---@return string?
local function selected(want)
	return n.exec_lua(function(want)
		FH.wait(function()
			return _G.last == want
		end, 1000)
		return _G.last
	end, want)
end

---The role of the pane holding the focus.
---@return string?
local function cur_pane()
	return n.exec_lua(function()
		local win = vim.api.nvim_get_current_win()
		for role, pane in pairs(FH.panes()) do
			if pane.win == win then
				return role
			end
		end
	end)
end

---What the spied actions received: `{ open = { "a.lua" }, ... }` (the text of the item argument).
---@return table<string, string[]>
local function got()
	return n.exec_lua(function()
		return _G.spied
	end)
end

t.describe("finder keys", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			FH.list_source("fake_keys", { "a.lua", "b.lua", "c.lua" })
			local action = require("beast.libs.finder.action")
			_G.spied = { open = {}, open_split = {}, open_vsplit = {}, copy_path = {} }
			for name in pairs(_G.spied) do
				action[name] = function(...)
					for _, arg in ipairs({ ... }) do
						if type(arg) == "table" and arg.text then
							table.insert(_G.spied[name], arg.text)
							return
						end
					end
					table.insert(_G.spied[name], "?")
				end
			end
		end)
	end)

	t.after_each(F.close)

	for _, pane in ipairs({ "input", "list" }) do
		local mode = pane == "input" and "i" or "n"

		---@param lhs string
		---@return boolean
		local function press(lhs)
			return F.press(lhs, { pane = pane, mode = mode })
		end

		t.describe(pane .. " pane", function()
			t.it("starts on the first row", function()
				fresh()
				t.eq("a.lua", selected("a.lua"))
			end)

			for _, key in ipairs({ "<C-j>", "<C-n>", "<Down>", "<Tab>" }) do
				t.it(key .. " is mapped and moves down", function()
					fresh()
					t.eq(true, press(key))
					t.eq("b.lua", selected("b.lua"))
				end)
			end

			for _, key in ipairs({ "<C-k>", "<C-p>", "<Up>", "<S-Tab>" }) do
				t.it(key .. " is mapped and moves up", function()
					fresh()
					press("<C-j>")
					t.eq("b.lua", selected("b.lua"))
					t.eq(true, press(key))
					t.eq("a.lua", selected("a.lua"))
				end)
			end

			t.it("<CR> opens the selected item", function()
				fresh()
				press("<CR>")
				t.eq({ "a.lua" }, got().open)
			end)

			t.it("<CR> closes the picker", function()
				fresh()
				press("<CR>")
				t.eq(0, F.window_count())
			end)

			t.it("<C-s> splits with the selected item", function()
				fresh()
				press("<C-j>")
				press("<C-s>")
				t.eq({ "b.lua" }, got().open_split)
			end)

			t.it("<C-s> closes the picker", function()
				fresh()
				press("<C-s>")
				t.eq(0, F.window_count())
			end)

			t.it("<C-v> opens a vertical split", function()
				fresh()
				press("<C-v>")
				t.eq({ "a.lua" }, got().open_vsplit)
			end)

			t.it("<C-v> does not open a horizontal split", function()
				fresh()
				press("<C-v>")
				t.eq({}, got().open_split)
			end)

			t.it("<C-v> closes the picker", function()
				fresh()
				press("<C-v>")
				t.eq(0, F.window_count())
			end)

			if pane == "input" then
				t.it("<C-y> copies the selected item", function()
					fresh()
					press("<C-y>")
					t.eq({ "a.lua" }, got().copy_path)
				end)

				t.it("<C-y> keeps the picker open", function()
					fresh()
					press("<C-y>")
					t.eq(true, F.window_count() > 0)
				end)
			else
				t.it("<C-y> is not mapped", function()
					fresh()
					press("<C-y>")
					t.eq({}, got().copy_path)
				end)
			end

			t.it((mode == "n" and "<Esc>" or "<C-c>") .. " closes the picker", function()
				fresh()
				press(mode == "n" and "<Esc>" or "<C-c>")
				t.eq(0, F.window_count())
			end)

			t.it("<C-c> closes the picker", function()
				fresh()
				press("<C-c>")
				t.eq(0, F.window_count())
			end)
		end)
	end

	t.describe("focus moves between panes", function()
		t.before_each(fresh)

		t.it("input: <C-l> focuses the preview", function()
			F.press("<C-l>", { pane = "input", mode = "i" })
			t.eq("preview", cur_pane())
		end)

		t.it("preview: <C-h> focuses the input", function()
			F.press("<C-h>", { pane = "preview", mode = "n" })
			t.eq("input", cur_pane())
		end)

		t.it("list: <C-l> focuses the preview", function()
			F.press("<C-l>", { pane = "list", mode = "n" })
			t.eq("preview", cur_pane())
		end)

		t.it("preview: <C-l> does nothing", function()
			F.press("<C-l>", { pane = "preview", mode = "n" })
			t.eq("preview", cur_pane())
		end)

		t.it("list: <C-h> focuses the input", function()
			F.press("<C-h>", { pane = "list", mode = "n" })
			t.eq("input", cur_pane())
		end)

		t.it("input: <C-h> does nothing", function()
			F.press("<C-h>", { pane = "input", mode = "i" })
			t.eq("input", cur_pane())
		end)

		t.it("list: a printable key goes back to the input", function()
			F.press("x", { pane = "list", mode = "n" })
			t.eq("input", cur_pane())
		end)
	end)

	t.describe("preview pane keys", function()
		t.before_each(fresh)

		t.it("<C-j> moves the selection down", function()
			F.press("<C-j>", { pane = "preview", mode = "n" })
			t.eq("b.lua", selected("b.lua"))
		end)

		t.it("<C-k> moves it back up", function()
			F.press("<C-j>", { pane = "preview", mode = "n" })
			t.eq("b.lua", selected("b.lua"))
			F.press("<C-k>", { pane = "preview", mode = "n" })
			t.eq("a.lua", selected("a.lua"))
		end)

		for _, key in ipairs({ "<CR>", "<C-s>", "<C-v>", "<C-y>" }) do
			t.it("has no " .. key, function()
				t.eq(false, F.press(key, { pane = "preview", mode = "n" }))
			end)
		end

		t.it("<Esc> closes the picker", function()
			F.press("<Esc>", { pane = "preview", mode = "n" })
			t.eq(0, F.window_count())
		end)
	end)
end)
