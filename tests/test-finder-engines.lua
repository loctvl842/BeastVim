-- =========================================================================
-- Test: finder pipelines (match and stream) seen through the real picker
-- =========================================================================
-- Characterizes today's behavior so the pipeline refactor
-- (docs/dev-specs/finder-levels-refactor.md, phases 1 and 3) cannot change it unnoticed.
--
-- Run as: nvim --clean --headless -l tests/test-finder-engines.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()

-- ---------------------------------------------------------------------------
t.section("match pipeline: sync source")
H.list_source("fake_sync", { "alpha.lua", "beta.lua", "gamma.lua", "delta/beta2.lua" })
H.open("fake_sync")
t.ok("empty prompt lists everything", H.has_row("alpha.lua") and H.has_row("gamma.lua") and H.has_row("beta2.lua"))
local rows = H.rows()
t.ok("in source order", rows[1]:find("alpha", 1, true) ~= nil, vim.inspect(rows))
H.type("beta")
t.ok("typing filters", H.has_row("beta.lua") and H.has_row("beta2.lua") and not H.has_row("alpha.lua") and not H.has_row("gamma.lua"))
H.type("gmm")
t.ok("fuzzy: subsequence matches", H.has_row("gamma.lua") and not H.has_row("beta.lua"))
H.type("zzz")
t.ok("no match shows no rows", not H.has_row("alpha.lua") and not H.has_row("gamma.lua") and not H.has_row("beta"))
H.type("")
t.ok("clearing the prompt restores the list", H.has_row("alpha.lua") and H.has_row("gamma.lua"))
H.type("alp")
H.type("alph")
t.ok("narrowing a query keeps the right rows", H.has_row("alpha.lua") and not H.has_row("beta.lua"))
H.close()

-- ---------------------------------------------------------------------------
t.section("match pipeline: async source")
-- NOTE: a source that stays open without delivering items makes today's match loader spin and
-- re-render on every loop tick (it yields without suspending), which starves the test loop.
-- The refactor (phase 1) fixes that; until then this source delivers in short bursts and finishes.
local got = 0
H.fake_source("fake_async", {
	live = false,
	async = true,
	get = function(_, cb)
		got = got + 1
		cb({ idx = 1, score = 0, text = "one.lua", file = "one.lua" })
		cb({ idx = 2, score = 0, text = "two.lua", file = "two.lua" })
		vim.defer_fn(function()
			cb({ idx = 3, score = 0, text = "three.lua", file = "three.lua" })
			cb(nil)
		end, 40)
	end,
})
H.open("fake_async")
t.eq("source asked once", got, 1)
H.wait(function()
	return H.has_row("three.lua")
end, 2000)
t.ok("streamed items all appear", H.has_row("one.lua") and H.has_row("two.lua") and H.has_row("three.lua"), vim.inspect(H.rows()))
H.type("thr")
t.ok("typing filters the streamed items", H.has_row("three.lua") and not H.has_row("one.lua"))
H.close()
local closed_early = 0
H.fake_source("fake_async_late", {
	live = false,
	async = true,
	get = function(_, cb)
		vim.defer_fn(function()
			closed_early = closed_early + 1
			cb({ idx = 1, score = 0, text = "late.lua", file = "late.lua" })
			cb(nil)
		end, 60)
	end,
})
H.open("fake_async_late", { backdrop = false })
H.close()
H.settle(200)
t.eq("the late answer arrived after the picker was gone", closed_early, 1)
t.eq("and opened nothing", H.window_count(), 0)

-- ---------------------------------------------------------------------------
t.section("stream pipeline: one search per prompt change")
local calls, cancels = {}, 0
H.fake_source("fake_live", {
	live = true,
	async = true,
	debounce_ms = 10,
	get = function(filter, cb)
		calls[#calls + 1] = filter.pattern
		cb({ idx = 1, score = 1, text = filter.pattern .. "-1", file = filter.pattern .. "-1" })
		cb({ idx = 2, score = 1, text = filter.pattern .. "-2", file = filter.pattern .. "-2" })
		cb(nil)
	end,
	cancel = function()
		cancels = cancels + 1
	end,
})
H.open("fake_live")
t.eq("an empty prompt searches nothing", #calls, 0)
t.ok("and shows nothing", not H.has_row("-1"))
H.type("ab")
t.eq("typing runs the source with the prompt text", calls[#calls], "ab")
t.ok("results are shown as they are (no local filtering)", H.has_row("ab-1") and H.has_row("ab-2"))
H.type("abc")
t.eq("each change searches again", calls[#calls], "abc")
t.ok("previous results are replaced", H.has_row("abc-1") and not H.has_row("ab-1"))
t.ok("the running search was cancelled before each new one", cancels >= 2, "cancels=" .. cancels)
H.type("")
t.ok("an empty prompt clears the list", not H.has_row("abc-1"))
H.close()

-- ---------------------------------------------------------------------------
t.section("stream pipeline: answers of a replaced search are dropped")
local pending = {}
H.fake_source("fake_manual", {
	live = true,
	async = true,
	debounce_ms = 10,
	get = function(_, cb)
		pending[#pending + 1] = cb
	end,
	cancel = function() end,
})
H.open("fake_manual")
H.type("a")
H.type("ab")
t.eq("two searches started", #pending, 2)
pending[1]({ idx = 1, score = 1, text = "old.lua", file = "old.lua" })
pending[1](nil)
pending[2]({ idx = 1, score = 1, text = "new.lua", file = "new.lua" })
pending[2](nil)
H.settle(300)
t.ok("only the latest search shows", H.has_row("new.lua") and not H.has_row("old.lua"), vim.inspect(H.rows()))
H.close()

-- ---------------------------------------------------------------------------
t.section("stream pipeline: retain_results keeps the old list until new items arrive")
pending = {}
H.fake_source("fake_retain", {
	live = true,
	async = true,
	retain_results = true,
	debounce_ms = 10,
	get = function(_, cb)
		pending[#pending + 1] = cb
	end,
	cancel = function() end,
})
H.open("fake_retain")
H.type("a")
pending[1]({ idx = 1, score = 1, text = "first.lua", file = "first.lua" })
pending[1](nil)
H.settle(200)
t.ok("first results shown", H.has_row("first.lua"))
H.type("ab")
t.ok("old results stay while the next search is running", H.has_row("first.lua"))
pending[2]({ idx = 1, score = 1, text = "second.lua", file = "second.lua" })
pending[2](nil)
H.settle(300)
t.ok("replaced once the first new item lands", H.has_row("second.lua") and not H.has_row("first.lua"))
H.close()

-- ---------------------------------------------------------------------------
t.section("stream pipeline: initial_query searches at once and fills the prompt")
local seen = {}
H.fake_source("fake_initial", {
	live = true,
	async = true,
	initial_query = "q ",
	run_when_empty = true,
	debounce_ms = 10,
	get = function(filter, cb)
		seen[#seen + 1] = filter.pattern
		cb({ idx = 1, score = 1, text = "hit.lua", file = "hit.lua" })
		cb(nil)
	end,
	cancel = function() end,
})
H.open("fake_initial")
t.eq("searched once with the initial text", seen, { "q " })
t.eq("prompt shows it", H.prompt(), "q ")
t.ok("results are listed", H.has_row("hit.lua"))
H.close()

t.done()
