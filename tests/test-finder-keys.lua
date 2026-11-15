-- =========================================================================
-- Test: picker keys per pane (input, list, preview)
-- =========================================================================
-- Characterizes which key does what in which pane, through the real mappings, so the
-- key-table rewrite (docs/dev-specs/finder-levels-refactor.md, phase 4) stays equivalent.
-- The only intended difference afterwards: <C-v> in the list pane opens a vertical split.
--
-- Run as: nvim --clean --headless -l tests/test-finder-keys.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()
local action = require("beast.libs.finder.action")

H.list_source("fake_keys", { "a.lua", "b.lua", "c.lua" })

local opened, splits, vsplits, copies
local restore = {}

local function spy_all()
	local o, r1 = H.spy(action, "open")
	local s, r2 = H.spy(action, "open_split")
	local v, r3 = H.spy(action, "open_vsplit")
	local c, r4 = H.spy(action, "copy_path")
	opened, splits, vsplits, copies = o, s, v, c
	restore = { r1, r2, r3, r4 }
end
local function unspy_all()
	for _, r in ipairs(restore) do
		r()
	end
end

local last ---@type string?
--- Open a fresh picker and track which item the preview was last asked to show.
local function fresh()
	last = nil
	H.open("fake_keys", {
		on_preview = function(item)
			last = item.text
		end,
	})
	H.settle(150)
end
local function selected()
	H.settle(150)
	return last
end
local function cur_pane()
	local win = vim.api.nvim_get_current_win()
	for role, pane in pairs(H.panes()) do
		if pane.win == win then
			return role
		end
	end
end

spy_all()

for _, pane in ipairs({ "input", "list" }) do
	local mode = pane == "input" and "i" or "n"
	local function press(lhs)
		return H.press(lhs, { pane = pane, mode = mode })
	end

	t.section(pane .. " pane: moving the selection")
	fresh()
	t.eq("starts on the first row", selected(), "a.lua")
	for _, key in ipairs({ "<C-j>", "<C-n>", "<Down>", "<Tab>" }) do
		fresh()
		t.ok(key .. " is mapped", press(key))
		t.eq(key .. " moves down", selected(), "b.lua")
	end
	for _, key in ipairs({ "<C-k>", "<C-p>", "<Up>", "<S-Tab>" }) do
		fresh()
		press("<C-j>")
		t.eq("(moved down first)", selected(), "b.lua")
		t.ok(key .. " is mapped", press(key))
		t.eq(key .. " moves up", selected(), "a.lua")
	end

	t.section(pane .. " pane: Enter, splits, copy")
	fresh()
	opened[1] = nil
	press("<CR>")
	t.eq("<CR> opens the selected item", opened[1] and opened[1][2].text, "a.lua")
	t.eq("<CR> closes the picker", H.window_count(), 0)

	fresh()
	press("<C-j>")
	splits[1], vsplits[1] = nil, nil
	press("<C-s>")
	t.eq("<C-s> splits with the selected item", splits[1] and splits[1][2].text, "b.lua")
	t.eq("<C-s> closes the picker", H.window_count(), 0)

	fresh()
	splits[1], vsplits[1] = nil, nil
	press("<C-v>")
	if pane == "input" then
		t.eq("<C-v> opens a vertical split", vsplits[1] and vsplits[1][2].text, "a.lua")
	else
		-- KNOWN BUG, fixed in phase 4 of the refactor: the list pane's <C-v> opens a horizontal split.
		t.eq("<C-v> opens a split (list pane: horizontal, known bug)", splits[1] and splits[1][2].text, "a.lua")
		t.eq("<C-v> does not open a vertical split (known bug)", vsplits[1], nil)
	end
	t.eq("<C-v> closes the picker", H.window_count(), 0)

	fresh()
	copies[1] = nil
	press("<C-y>")
	if pane == "input" then
		t.eq("<C-y> copies the selected item", copies[1] and copies[1][1].text, "a.lua")
		t.ok("<C-y> keeps the picker open", H.window_count() > 0)
	else
		t.ok("<C-y> is not mapped in the list pane", copies[1] == nil)
	end
	H.close()

	t.section(pane .. " pane: closing")
	fresh()
	press(mode == "n" and "<Esc>" or "<C-c>")
	t.eq("closes the picker", H.window_count(), 0)
	fresh()
	press("<C-c>")
	t.eq("<C-c> closes the picker", H.window_count(), 0)
end

t.section("focus moves between panes")
fresh()
H.press("<C-l>", { pane = "input", mode = "i" })
t.eq("input: <C-l> focuses the preview", cur_pane(), "preview")
H.press("<C-h>", { pane = "preview", mode = "n" })
t.eq("preview: <C-h> focuses the input", cur_pane(), "input")
H.press("<C-l>", { pane = "list", mode = "n" })
t.eq("list: <C-l> focuses the preview", cur_pane(), "preview")
H.press("<C-l>", { pane = "preview", mode = "n" })
t.eq("preview: <C-l> does nothing", cur_pane(), "preview")
H.press("<C-h>", { pane = "list", mode = "n" })
t.eq("list: <C-h> focuses the input", cur_pane(), "input")
H.press("<C-h>", { pane = "input", mode = "i" })
t.eq("input: <C-h> does nothing", cur_pane(), "input")
H.press("x", { pane = "list", mode = "n" })
t.eq("list: a printable key goes back to the input", cur_pane(), "input")
H.close()

t.section("preview pane keys")
fresh()
H.press("<C-j>", { pane = "preview", mode = "n" })
t.eq("<C-j> moves the selection down", selected(), "b.lua")
H.press("<C-k>", { pane = "preview", mode = "n" })
t.eq("<C-k> moves it back up", selected(), "a.lua")
for _, key in ipairs({ "<CR>", "<C-s>", "<C-v>", "<C-y>" }) do
	t.ok("preview has no " .. key, not H.press(key, { pane = "preview", mode = "n" }))
end
H.press("<Esc>", { pane = "preview", mode = "n" })
t.eq("<Esc> closes the picker", H.window_count(), 0)

unspy_all()
t.done()
