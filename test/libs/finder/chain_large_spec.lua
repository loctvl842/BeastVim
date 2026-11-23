local F = require("test.libs.finder.helpers.finder")
local t = require("test.testutil")

-- A scope bigger than the 1000 rows a list keeps is still searched in full.
t.describe("finder chain over a large scope", function()
	local total = 1300
	local dir

	t.before_each(function()
		F.setup()
		local files = {}
		for i = 1, total do
			files[("f%04d.lua"):format(i)] = "needle " .. i
		end
		-- The last file (worst fuzzy rank for "f") must be reachable by the grep.
		dir = F.tmpdir(files)
		F.open("files", { cwd = dir })
		F.settle(1500)
		F.type("f")
	end)

	t.after_each(function()
		F.close()
		F.rmdir(dir)
	end)

	t.it("counts all the matches, not the 1000 shown", function()
		t.eq(tostring(total), F.count())
	end)

	t.it("titles the grep with every file", function()
		F.press("<C-g>")
		F.settle(300)
		t.eq(total .. " Files › Live Grep", F.title())
	end)

	t.it("finds a file beyond the first 1000", function()
		F.press("<C-g>")
		F.settle(300)
		F.type("needle " .. total, 1500)
		t.eq(true, F.has_row("f" .. total .. ".lua") or F.has_row("f1300.lua"))
	end)
end)
