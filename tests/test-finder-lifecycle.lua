-- =========================================================================
-- Test: finder picker lifecycle (open / reopen / close / reentrancy / callbacks)
-- =========================================================================
-- Characterizes today's behavior through the public surface only, so it must keep
-- passing while the finder's internals are refactored (docs/dev-specs/finder-levels-refactor.md).
--
-- Run as: nvim --clean --headless -l tests/test-finder-lifecycle.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()
local finder = H.finder()

H.list_source("fake_a", { "a.lua", "b.lua", "c.lua" })
H.list_source("fake_b", { "x.lua", "y.lua" })

t.section("open shows the picker windows")
H.open("fake_a")
local panes = H.panes()
t.ok("input, list, preview and backdrop are open", panes.input and panes.list and panes.preview and panes.backdrop)
t.eq("exactly four picker windows", H.window_count(), 4)
t.ok("rows are listed", H.has_row("a.lua") and H.has_row("c.lua"))

t.section("opening again replaces the picker")
H.open("fake_b")
t.eq("still one set of windows", H.window_count(), 4)
t.ok("shows the new source", H.has_row("x.lua") and not H.has_row("a.lua"))

t.section("close is idempotent")
H.close()
t.eq("windows gone", H.window_count(), 0)
local ok = pcall(H.close)
t.ok("second close does not error", ok)
t.eq("still nothing open", H.window_count(), 0)

t.section("options hide panes")
H.open("fake_a", { preview = false, backdrop = false })
panes = H.panes()
t.ok("no preview", panes.preview == nil)
t.ok("no backdrop", panes.backdrop == nil)
t.ok("input and list remain", panes.input and panes.list)
H.close()

t.section("focus leaving the picker closes it")
local main = H.main_win()
H.open("fake_a")
vim.api.nvim_set_current_win(main)
H.settle()
t.eq("picker closed after WinEnter outside", H.window_count(), 0)

t.section("Esc and Ctrl-C close it")
H.open("fake_a")
t.ok("<Esc> is mapped in normal mode", H.press("<Esc>", { mode = "n" }))
t.eq("closed by <Esc>", H.window_count(), 0)
H.open("fake_a")
t.ok("<C-c> is mapped", H.press("<C-c>", { mode = "i" }))
t.eq("closed by <C-c>", H.window_count(), 0)

t.section("on_close reports whether the user confirmed")
local closed_with = {}
local open_calls = H.spy(require("beast.libs.finder.action"), "open")
H.open("fake_a", {
	on_close = function(confirmed)
		closed_with[#closed_with + 1] = confirmed
	end,
})
H.close()
t.eq("closing without Enter -> false", closed_with, { false })
H.open("fake_a", {
	on_close = function(confirmed)
		closed_with[#closed_with + 1] = confirmed
	end,
})
H.press("<CR>")
t.eq("Enter -> true", closed_with, { false, true })
t.eq("Enter opens exactly one item", #open_calls, 1)
t.eq("Enter opens the selected item", open_calls[1] and open_calls[1][2].text, "a.lua")

t.section("initial_text starts on the matching row")
local previewed = {}
H.open("fake_a", {
	initial_text = "b.lua",
	on_preview = function(item)
		previewed[#previewed + 1] = item.text
	end,
})
H.wait(function()
	return #previewed > 0
end)
t.eq("preview follows the requested item", previewed[#previewed], "b.lua")
H.close()

t.section("opening a picker from on_close (reentrancy)")
-- KNOWN LIMITATION (today): the picker opened inside on_close is closed again when the first
-- picker finishes closing its windows (focus returns to the main window -> WinEnter), and the
-- first close raises E367 deleting the autocmd group both pickers share. Nothing in the config
-- does this. Phase 3 of the levels refactor gives each Session its own group; revisit then.
H.open("fake_a", {
	on_close = function()
		finder.open("fake_b")
	end,
})
local outer_ok = pcall(H.close)
H.settle()
io.write("  NOTE: closing the first picker " .. (outer_ok and "works" or "raises (known limitation)") .. "\n")
t.eq("no picker survives (current behavior)", H.window_count(), 0)
local again = pcall(H.close)
t.ok("closing again never errors", again)
t.eq("nothing left open", H.window_count(), 0)

t.section("closing returns focus to the window the picker was opened from")
H.open("fake_a")
H.close()
t.eq("focus is back", vim.api.nvim_get_current_win(), main)

t.done()
