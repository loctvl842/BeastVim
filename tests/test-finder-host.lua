-- =========================================================================
-- Test: finder pipelines run without a UI (host contract, results, staleness)
-- =========================================================================
-- Covers docs/dev-specs/finder-levels-refactor.md phase 1: the match and stream
-- engines talk to a `Beast.Finder.Host`, expose the full match set and a total,
-- and drop every late callback once they are aborted or the host is gone.
--
-- Run as: nvim --clean --headless -l tests/test-finder-host.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()

local Query = require("beast.libs.finder.query")
local host_mod = require("beast.libs.finder.host")
local match = require("beast.libs.finder.pipeline.match")
local stream = require("beast.libs.finder.pipeline.stream")

--- A headless host that counts what the engine asked of it.
local function counting_host(extra)
	local h = { renders = 0, busy_log = {}, counts = {}, titles = {} }
	h.host = host_mod.headless(vim.tbl_extend("force", {
		render = function()
			h.renders = h.renders + 1
		end,
		busy = function(on)
			h.busy_log[#h.busy_log + 1] = on
		end,
		count = function(text)
			h.counts[#h.counts + 1] = text or "nil"
		end,
		title = function(text)
			h.titles[#h.titles + 1] = text
		end,
	}, extra or {}))
	return h
end

local function make_items(n, name)
	local items = {}
	for i = 1, n do
		items[i] = { idx = i, score = 0, text = (name or "file") .. i .. ".lua", file = (name or "file") .. i .. ".lua" }
	end
	return items
end

local function sync_source(items)
	return {
		live = false,
		async = false,
		get = function()
			return vim.deepcopy(items)
		end,
	}
end

-- ---------------------------------------------------------------------------
t.section("match engine: results beyond the display limit")
local h = counting_host()
local query = Query(sync_source(make_items(1500)), { cwd = "/tmp" })
match.start(query, h.host)
H.wait(function()
	return not query.matching and query.total == 1500
end)
t.eq("matched is capped at the limit", #query.matched, 1000)
t.eq("total counts every item", query.total, 1500)
local all = match.matches(query)
t.eq("matches() returns the whole set for an empty pattern", all and #all, 1500)
t.eq("not loading, not matching", { query.loading, query.matching }, { false, false })

query.filter:update("file1")
match.run(query, h.host)
H.wait(function()
	return not query.matching
end)
local matched_all = match.matches(query)
t.ok("a pattern narrows the total", query.total > 0 and query.total < 1500, "total=" .. query.total)
t.eq("matches() agrees with total", matched_all and #matched_all, query.total)
t.ok("matches() beyond the limit", query.total > 1000 and #matched_all > 1000 or query.total <= 1000)
local function subsequence(text, pattern)
	local i = 1
	for c in text:gmatch(".") do
		if c == pattern:sub(i, i) then
			i = i + 1
		end
	end
	return i > #pattern
end
local ok_only = true
for _, item in ipairs(matched_all or {}) do
	ok_only = ok_only and subsequence(item.text, "file1")
end
t.ok("and only real (fuzzy) matches", ok_only)
match.abort(query)

t.section("match engine: limit option")
local q2 = Query(sync_source(make_items(50)), { cwd = "/tmp", limit = 5 })
match.start(q2, h.host)
H.wait(function()
	return not q2.matching and q2.total == 50
end)
t.eq("matched honours the limit", #q2.matched, 5)
t.eq("total ignores it", q2.total, 50)
t.eq("matches() ignores it too", #(match.matches(q2) or {}), 50)
match.abort(q2)

t.section("match engine: matches() is nil while working")
local pending
local q3 = Query({
	live = false,
	async = true,
	get = function(_, cb)
		pending = cb
	end,
}, { cwd = "/tmp" })
local h3 = counting_host()
match.start(q3, h3.host)
H.settle(50)
t.eq("loading while the source is open", q3.loading, true)
t.eq("matches() is nil while loading", match.matches(q3), nil)
t.eq("the spinner was started", h3.busy_log[1], true)
pending({ idx = 1, score = 0, text = "a.lua", file = "a.lua" })
pending(nil)
H.wait(function()
	return not q3.loading
end)
H.settle(50)
t.eq("done loading", q3.loading, false)
t.eq("matches() available again", #(match.matches(q3) or {}), 1)
t.eq("the spinner was stopped", h3.busy_log[#h3.busy_log], false)
match.abort(q3)

t.section("match engine: preloaded items and aborted queries")
local hp = counting_host()
local qp = Query(sync_source({}), { cwd = "/tmp", preloaded_items = make_items(30) })
qp.source.async = true
match.start(qp, hp.host)
t.eq("total is known at once for preloaded items", qp.total, 30)
H.wait(function()
	return #qp.matched == 30
end)
t.eq("matches() has them all", #(match.matches(qp) or {}), 30)
match.abort(qp)

local q_open = Query({
	live = false,
	async = true,
	get = function(_, cb)
		cb({ idx = 1, score = 0, text = "a.lua", file = "a.lua" })
	end,
}, { cwd = "/tmp" })
match.start(q_open, counting_host().host)
H.settle(60)
match.abort(q_open)
t.eq("an aborted mid-load query never reports a partial set", match.matches(q_open), nil)

-- ---------------------------------------------------------------------------
t.section("match engine: an open but idle source does not spin")
local idle = counting_host()
local q4 = Query({
	live = false,
	async = true,
	get = function(_, cb)
		cb({ idx = 1, score = 0, text = "a.lua", file = "a.lua" })
	end,
}, { cwd = "/tmp" })
match.start(q4, idle.host)
H.settle(400)
t.ok("renders stay few while the source is quiet", idle.renders < 20, "renders=" .. idle.renders)
match.abort(q4)

-- ---------------------------------------------------------------------------
t.section("match engine: late work is dropped")
local late_cb
local h5 = counting_host()
local q5 = Query({
	live = false,
	async = true,
	get = function(_, cb)
		late_cb = cb
	end,
}, { cwd = "/tmp" })
match.start(q5, h5.host)
H.settle(50)
match.abort(q5)
local before = h5.renders
local ok = pcall(function()
	late_cb({ idx = 1, score = 0, text = "late.lua", file = "late.lua" })
	late_cb(nil)
	H.settle(100)
end)
t.ok("an answer after abort does not error", ok)
t.eq("and does not render", h5.renders, before)
t.eq("and adds nothing to the matched list", #q5.matched, 0)

local alive = true
local h6 = counting_host({
	alive = function()
		return alive
	end,
})
local q6 = Query(sync_source(make_items(10)), { cwd = "/tmp" })
match.start(q6, h6.host)
H.wait(function()
	return h6.renders > 0
end)
alive = false
local renders = h6.renders
q6.filter:update("file")
match.run(q6, h6.host)
H.settle(200)
t.eq("a host that is no longer alive is never rendered to", h6.renders, renders)
match.abort(q6)

-- ---------------------------------------------------------------------------
t.section("match engine: reload loads again")
local gets = 0
local h7 = counting_host()
local q7 = Query({
	live = false,
	async = true,
	get = function(_, cb)
		gets = gets + 1
		cb({ idx = 1, score = 0, text = "gen" .. gets .. ".lua", file = "gen" .. gets .. ".lua" })
		cb(nil)
	end,
}, { cwd = "/tmp" })
match.start(q7, h7.host)
H.wait(function()
	return not q7.loading and #q7.matched == 1
end)
t.eq("first load", q7.matched[1] and q7.matched[1].text, "gen1.lua")
match.reload(q7, h7.host)
H.wait(function()
	return gets == 2 and not q7.loading and q7.matched[1] and q7.matched[1].text == "gen2.lua"
end)
t.eq("the source was asked again", gets, 2)
t.eq("and its new items replaced the old ones", #q7.matched, 1)
t.eq("showing the new item", q7.matched[1] and q7.matched[1].text, "gen2.lua")
match.abort(q7)

-- ---------------------------------------------------------------------------
t.section("stream engine: results, count, title, staleness")
local calls = {}
local h8 = counting_host()
local q8 = Query({
	live = true,
	async = true,
	title = function(filter)
		return "T " .. filter.pattern
	end,
	count = function(items)
		return tostring(#items)
	end,
	get = function(filter, cb)
		calls[#calls + 1] = { pattern = filter.pattern, cb = cb }
	end,
	cancel = function() end,
}, { cwd = "/tmp" })
q8.filter:update("a")
stream.run(q8, h8.host)
q8.filter:update("ab")
stream.run(q8, h8.host)
t.eq("two runs started", #calls, 2)
t.eq("matches() is nil while a run is open", stream.matches(q8), nil)
t.eq("the title follows the run", h8.titles[#h8.titles], "T ab")
calls[1].cb({ idx = 1, score = 1, text = "old", file = "old" })
calls[1].cb(nil)
calls[2].cb({ idx = 1, score = 1, text = "new", file = "new" })
calls[2].cb(nil)
H.settle(100)
t.eq(
	"only the latest run's items are kept",
	vim.tbl_map(function(i)
		return i.text
	end, q8.items),
	{ "new" }
)
t.eq("total follows the items", q8.total, 1)
t.eq("matches() is available after the run", #(stream.matches(q8) or {}), 1)
t.eq("the count label comes from the source", h8.counts[#h8.counts], "1")
t.eq("busy was turned off", h8.busy_log[#h8.busy_log], false)
stream.abort(q8)

t.section("stream engine: an empty prompt clears and stops the spinner")
local h9 = counting_host()
local q9 = Query({
	live = true,
	async = true,
	get = function(_, cb)
		cb({ idx = 1, score = 1, text = "x", file = "x" })
	end,
	cancel = function() end,
}, { cwd = "/tmp" })
q9.filter:update("x")
stream.run(q9, h9.host)
q9.filter:update("")
stream.run(q9, h9.host)
H.settle(100)
t.eq("results cleared", #q9.items, 0)
t.eq("spinner is off", h9.busy_log[#h9.busy_log], false)
stream.abort(q9)

t.section("stream engine: callbacks after abort do nothing")
local cbs = {}
local h10 = counting_host()
local q10 = Query({
	live = true,
	async = true,
	get = function(_, cb)
		cbs[#cbs + 1] = cb
	end,
	cancel = function() end,
}, { cwd = "/tmp" })
q10.filter:update("x")
stream.run(q10, h10.host)
stream.abort(q10)
local renders10 = h10.renders
local ok10 = pcall(function()
	cbs[1]({ idx = 1, score = 1, text = "late", file = "late" })
	cbs[1](nil)
	H.settle(100)
end)
t.ok("no error", ok10)
t.eq("no render", h10.renders, renders10)
t.eq("no items", #q10.items, 0)

t.section("stream engine: start runs the initial query")
local seen = {}
local q11 = Query({
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
stream.start(q11, counting_host().host)
H.settle(100)
t.eq("searched once with the initial text", seen, { "is:pr " })
stream.abort(q11)

t.done()
