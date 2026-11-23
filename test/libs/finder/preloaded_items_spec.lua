local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers the Phase 3 optimization in docs/dev-specs/finder-auto-select.md: when finder/init.lua's
-- pre-flight already fetched the full result set (more than one item), opening the picker must not
-- call source.get() again.

---Start the match pipeline over a source that answers `a`, `b`, with or without preloaded items.
---@param preloaded boolean
---@return { gets: integer, matched: integer }
local function run(preloaded)
	return n.exec_lua(function(preloaded)
		local Query = require("beast.libs.finder.query")
		local gets = 0
		local source = {
			async = true,
			get = function(_, cb)
				gets = gets + 1
				cb({ text = "a" })
				cb({ text = "b" })
				cb(nil)
			end,
		}
		local query = Query(source, {
			cwd = "/tmp",
			preloaded_items = preloaded and { { text = "a" }, { text = "b" } } or nil,
		})
		require("beast.libs.finder.pipeline.match").start(query, require("beast.libs.finder.host").headless())
		FH.wait(function()
			return #query.matched > 0
		end, 200)
		return { gets = gets, matched = #query.matched }
	end, preloaded)
end

t.describe("finder preloaded items", function()
	t.before_each(F.setup)

	t.describe("with preloaded items", function()
		t.it("never calls source.get", function()
			t.eq(0, run(true).gets)
		end)

		t.it("matches both preloaded items", function()
			t.eq(2, run(true).matched)
		end)
	end)

	t.describe("without preloaded items", function()
		t.it("calls source.get exactly once", function()
			t.eq(1, run(false).gets)
		end)

		t.it("matches both streamed items", function()
			t.eq(2, run(false).matched)
		end)
	end)
end)
