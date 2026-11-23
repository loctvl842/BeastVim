local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("select filter", function()
	t.before_each(h.clear)

	---@param text string
	---@param query string
	local function matches(text, query)
		return n.exec_lua(function(s, q)
			return require("beast.libs.select.filter").matches(s, q)
		end, text, query)
	end

	t.describe("empty query", function()
		t.it("matches non-empty text", function()
			t.eq(true, matches("dracula", ""))
		end)

		t.it("matches empty text", function()
			t.eq(true, matches("", ""))
		end)
	end)

	t.describe("case-insensitive substring", function()
		t.it("matches exactly", function()
			t.eq(true, matches("dracula", "dracula"))
		end)

		t.it("matches an uppercase query against lowercase text", function()
			t.eq(true, matches("dracula", "DRAC"))
		end)

		t.it("matches a lowercase query against uppercase text", function()
			t.eq(true, matches("Dracula", "drac"))
		end)

		t.it("matches a substring not at the start", function()
			t.eq(true, matches("dracula-soft", "soft"))
		end)
	end)

	t.describe("literal matching", function()
		t.it("treats magic pattern chars literally", function()
			t.eq(true, matches("a.b", ".b"))
		end)

		t.it("treats the percent sign literally", function()
			t.eq(true, matches("100% done", "100%"))
		end)
	end)

	t.describe("no match", function()
		t.it("rejects an unrelated query", function()
			t.eq(false, matches("dracula", "zzz"))
		end)

		t.it("rejects a query longer than the text", function()
			t.eq(false, matches("ab", "abc"))
		end)
	end)
end)
