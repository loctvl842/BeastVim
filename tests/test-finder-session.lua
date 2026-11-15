-- =========================================================================
-- Test: Session + Level (docs/dev-specs/finder-levels-refactor.md, phase 3)
-- =========================================================================
-- A session shows a stack of levels in the same windows: `push` remembers the current one,
-- `pop` brings it back exactly as it was (prompt, results, cursor) without searching again.
--
-- Run as: nvim --clean --headless -l tests/test-finder-session.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()
local Level = require("beast.libs.finder.level")
local Session = require("beast.libs.finder.session")

local a_gets = 0
H.fake_source("fake_a", {
	live = false,
	async = false,
	get = function()
		a_gets = a_gets + 1
		local items = {}
		for i = 1, 30 do
			items[i] = { idx = i, score = 0, text = ("a%02d.lua"):format(i), file = ("a%02d.lua"):format(i) }
		end
		return items
	end,
})
H.list_source("fake_b", { "x1.lua", "x2.lua", "y1.lua" })

local function wins()
	local out = {}
	for role, pane in pairs(H.panes()) do
		out[role] = pane.win
	end
	return out
end

-- ---------------------------------------------------------------------------
t.section("a session starts with one level")
H.open("fake_a")
local session = Session.current()
t.ok("there is a current session", session ~= nil)
t.eq("one level, nothing stacked", #session.stack, 0)
t.eq("the level knows its source", session.level.source.name, "fake_a")
t.eq("source asked once", a_gets, 1)

t.section("push shows a new level in the same windows")
H.type("a1")
H.press("<C-j>")
H.press("<C-j>")
H.settle(150)
local before = wins()
local cursor_before = session.view.list.cursor
local rows_before = H.rows()
t.ok("the parent shows its filtered rows", H.has_row("a10.lua") and not H.has_row("a02.lua"))
session:push(Level.new("fake_b"))
H.settle(200)
t.eq("same windows (nothing was closed and reopened)", wins(), before)
t.eq("one level is stacked", #session.stack, 1)
t.eq("the new level is current", session.level.source.name, "fake_b")
t.ok("shows the new level's rows", H.has_row("x1.lua") and not H.has_row("a10.lua"))
t.eq("the prompt starts empty", H.prompt(), "")

t.section("the pushed level works like any picker")
H.type("y")
t.ok("typing filters it", H.has_row("y1.lua") and not H.has_row("x1.lua"))
t.eq("the parent's source was not asked again", a_gets, 1)

t.section("pop brings the parent back without searching")
t.ok("pop succeeds", session:pop())
H.settle(200)
t.eq("same windows again", wins(), before)
t.eq("back to one level", #session.stack, 0)
t.eq("the parent is current", session.level.source.name, "fake_a")
t.eq("its prompt is back", H.prompt(), "a1")
t.eq("its rows are back", H.rows(), rows_before)
t.eq("its cursor is back", session.view.list.cursor, cursor_before)
t.eq("no search was made for it", a_gets, 1)
t.ok("nothing left to pop", not session:pop())

-- ---------------------------------------------------------------------------
t.section("late answers of a popped level are ignored")
local pending
H.fake_source("fake_stream", {
	live = true,
	async = true,
	debounce_ms = 10,
	get = function(_, cb)
		pending = cb
	end,
	cancel = function() end,
})
session:push(Level.new("fake_stream"))
H.type("q")
local late = pending
t.ok("the pushed level started a search", late ~= nil)
session:pop()
H.settle(100)
local rows_now = H.rows()
local ok = pcall(function()
	late({ idx = 1, score = 1, text = "late.lua", file = "late.lua" })
	late(nil)
	H.settle(150)
end)
t.ok("a late answer does not error", ok)
t.eq("and draws nothing over the parent", H.rows(), rows_now)
t.ok("the parent's rows are intact", H.has_row("a10.lua"))

-- ---------------------------------------------------------------------------
t.section("closing aborts every level in the stack")
local gate
H.fake_source("fake_async_open", {
	live = false,
	async = true,
	get = function(_, cb)
		gate = cb
	end,
})
H.open("fake_async_open")
session = Session.current()
local root_cb = gate
session:push(Level.new("fake_b"))
H.close()
t.eq("windows are gone", H.window_count(), 0)
t.ok("no current session", Session.current() == nil)
t.ok(
	"answers for the levels of a closed session do nothing",
	pcall(function()
		root_cb({ idx = 1, score = 0, text = "z.lua", file = "z.lua" })
		root_cb(nil)
		H.settle(100)
	end)
)
t.eq("and open nothing", H.window_count(), 0)
t.ok(
	"push on a closed session is ignored",
	pcall(function()
		session:push(Level.new("fake_b"))
	end)
)
t.eq("it opens nothing", H.window_count(), 0)

-- ---------------------------------------------------------------------------
t.section("each session has its own autocmd group")
H.open("fake_b")
local first = Session.current()
local first_group = first.augroup
H.open("fake_b")
local second = Session.current()
t.ok("a new session", second ~= first)
t.ok("with its own group", second.augroup ~= first_group and second.id ~= first.id)
t.ok("the old group is deleted", not pcall(vim.api.nvim_get_autocmds, { group = first_group }))
H.close()

-- ---------------------------------------------------------------------------
t.section("the prompt write of a push or pop does not search again")
local searches = {}
H.fake_source("fake_counting", {
	live = true,
	async = true,
	debounce_ms = 10,
	get = function(filter, cb)
		searches[#searches + 1] = filter.pattern
		cb({ idx = 1, score = 1, text = filter.pattern .. ".lua", file = filter.pattern .. ".lua" })
		cb(nil)
	end,
	cancel = function() end,
})
H.open("fake_counting")
H.type("one")
t.eq("typed once", searches, { "one" })
session = Session.current()
session:push(Level.new("fake_b"))
H.settle(300)
session:pop()
H.settle(400)
t.eq("pushing and popping caused no extra search", searches, { "one" })
t.eq("the prompt is restored", H.prompt(), "one")
t.ok("and its rows", H.has_row("one.lua"))
H.type("two")
t.eq("typing afterwards still searches", searches, { "one", "two" })
H.close()

t.done()
