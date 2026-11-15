-- =========================================================================
-- Test: the count label in the prompt row of match sources
-- (docs/dev-specs/finder-continuous.md, Phase 2 step 1)
--
-- Run as: nvim --clean --headless -l tests/test-finder-count.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()
local format = require("beast.libs.finder.format")

t.eq("ratio of an unfiltered list is the plain total", format.ratio({ {}, {}, {} }, 3), "3")
t.eq("ratio of a filtered list shows matches over total", format.ratio({ {}, {}, {} }, 1), "1/3")

H.list_source("zz_count_sync", { "alpha.lua", "beta.lua", "alphabet.lua" }, { count = format.ratio })
H.open("zz_count_sync")
t.eq("sync source: plain total on an empty prompt", H.count(), "3")
H.type("alpha")
t.eq("sync source: matches over total while typing", H.count(), "2/3")
H.type("zzzz")
t.eq("no match: zero over total", H.count(), "0/3")
H.close()

H.fake_source("zz_count_async", {
	live = false,
	async = true,
	count = format.ratio,
	get = function(_, cb)
		vim.schedule(function()
			for i, name in ipairs({ "one.lua", "two.lua", "three.lua", "ten.lua" }) do
				cb({ idx = i, score = 0, text = name, file = name })
			end
			cb(nil)
		end)
	end,
})
H.open("zz_count_async")
t.eq("async source: total once loading ends", H.count(), "4")
H.type("t")
t.ok("async source: ratio after typing", H.count():match("^%d/4$") ~= nil, H.count())
H.close()

t.done()
