local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder count label", function()
	t.before_each(F.setup)

	t.describe("format.ratio", function()
		t.it("is the plain total for an unfiltered list", function()
			t.eq(
				"3",
				n.exec_lua(function()
					return require("beast.libs.finder.format").ratio({ {}, {}, {} }, 3)
				end)
			)
		end)

		t.it("shows matches over total for a filtered list", function()
			t.eq(
				"1/3",
				n.exec_lua(function()
					return require("beast.libs.finder.format").ratio({ {}, {}, {} }, 1)
				end)
			)
		end)
	end)

	t.describe("sync source", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.list_source("zz_count_sync", { "alpha.lua", "beta.lua", "alphabet.lua" }, {
					count = require("beast.libs.finder.format").ratio,
				})
			end)
			F.open("zz_count_sync")
		end)

		t.after_each(F.close)

		t.it("shows the plain total on an empty prompt", function()
			t.eq("3", F.count())
		end)

		t.it("shows matches over total while typing", function()
			F.type("alpha")
			t.eq("2/3", F.count())
		end)

		t.it("shows zero over total when nothing matches", function()
			F.type("zzzz")
			t.eq("0/3", F.count())
		end)
	end)

	t.describe("async source", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.fake_source("zz_count_async", {
					live = false,
					async = true,
					count = require("beast.libs.finder.format").ratio,
					get = function(_, cb)
						vim.schedule(function()
							for i, name in ipairs({ "one.lua", "two.lua", "three.lua", "ten.lua" }) do
								cb({ idx = i, score = 0, text = name, file = name })
							end
							cb(nil)
						end)
					end,
				})
			end)
			F.open("zz_count_async")
		end)

		t.after_each(F.close)

		t.it("shows the total once loading ends", function()
			t.eq("4", F.count())
		end)

		t.it("shows a ratio after typing", function()
			F.type("t")
			t.matches("^%d/4$", F.count())
		end)
	end)
end)
