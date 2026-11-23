local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local TWO_HUNKS = table.concat({
	"@@ -20,7 +20,7 @@ mesh = jarvis",
	" ",
	" - The file may define",
	" - `A >> B` means",
	"-- `harness`, `cwd` are read from each node.",
	"+- `harness`, `cwd` are read from each node (nothing else is).",
	" - A node with no cwd",
	" - A node that is defined",
	" - A node written as a function",
	"@@ -40,14 +40,13 @@ jarvix mesh down",
	" ",
	" `jarvis` is the one pane",
}, "\n")

local SYNTAX_PATCH = "@@ -1,2 +1,2 @@\n local a = 1\n-return a\n+return a + 2"

t.describe("finder diff rows", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.diff = require("beast.libs.finder.ui.diff")
			---@return string[] texts
			_G.texts = function(file)
				return vim.tbl_map(function(r)
					return r.text
				end, _G.diff.rows(file))
			end
			---Does a row carry a mark whose group contains `name`?
			_G.has_capture = function(row, name)
				for _, m in ipairs(row.marks or {}) do
					if m[3]:find(name, 1, true) then
						return true
					end
				end
				return false
			end
		end)
	end)

	---Texts of the rows of `file` (a patch description).
	---@param file table
	---@return string[]
	local function texts(file)
		return n.exec_lua(function(f)
			return _G.texts(f)
		end, file)
	end

	t.describe("two hunks", function()
		local file = { status = "modified", additions = 5, deletions = 6, patch = TWO_HUNKS }

		t.it("starts with header, gap above and the hunk band", function()
			local out = texts(file)
			t.eq({ "modified  +5 -6  ■■■■■", "⋯ 19 unchanged lines above", "▸ @@ -20,7 +20,7 @@ mesh = jarvis" }, { out[1], out[2], out[3] })
		end)

		t.it("shows the hidden lines between the hunks", function()
			t.eq(
				"⋯ 13 unchanged lines",
				n.exec_lua(function(f)
					for _, r in ipairs(_G.diff.rows(f)) do
						if r.text:find("unchanged lines$") then
							return r.text
						end
					end
				end, file)
			)
		end)

		t.it("gives a removed row the old number only and an added row the new number only", function()
			t.eq(
				{ removed = { old = 23 }, added = { new = 23 } },
				n.exec_lua(function(f)
					local removed, added
					for _, r in ipairs(_G.diff.rows(f)) do
						if r.sign == "-" then
							removed = { old = r.old, new = r.new }
						elseif r.sign == "+" then
							added = { old = r.old, new = r.new }
						end
					end
					return { removed = removed, added = added }
				end, file)
			)
		end)

		t.it("pairs the changed words of an edit", function()
			t.eq(
				{ true, true },
				n.exec_lua(function(f)
					local removed, added
					for _, r in ipairs(_G.diff.rows(f)) do
						if r.sign == "-" then
							removed = r
						elseif r.sign == "+" then
							added = r
						end
					end
					return { removed.spans ~= nil, added.spans ~= nil }
				end, file)
			)
		end)

		t.it("carries the numbers on after the gap", function()
			t.eq(
				{ old = 41, new = 41, text = "`jarvis` is the one pane" },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					local after = rows[#rows]
					return { old = after.old, new = after.new, text = after.text }
				end, file)
			)
		end)

		t.it("splits the stat bar into additions and deletions", function()
			t.eq(
				{ "BeastViewDiffStatAdd", "BeastViewDiffStatDelete" },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					return { rows[1].marks[1][3], rows[1].marks[5][3] }
				end, file)
			)
		end)
	end)

	t.describe("added and deleted files", function()
		t.it("has no gap above a new file and only new numbers", function()
			local file = { status = "added", additions = 2, deletions = 0, patch = "@@ -0,0 +1,2 @@\n+a\n+b" }
			t.eq({ "added     +2 -0  ■■■■■", "▸ @@ -0,0 +1,2 @@", "a", "b" }, texts(file))
			t.eq(
				{ new3 = 1, new4 = 2 },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					return { old3 = rows[3].old, new3 = rows[3].new, new4 = rows[4].new }
				end, file)
			)
		end)

		t.it("has no gap above a deleted file, only old numbers and an all red bar", function()
			local file = { status = "removed", additions = 0, deletions = 2, patch = "@@ -1,2 +0,0 @@\n-a\n-b" }
			t.eq({ "removed   +0 -2  ■■■■■", "▸ @@ -1,2 +0,0 @@", "a", "b" }, texts(file))
			t.eq(
				{ old3 = 1, old4 = 2, bar = "BeastViewDiffStatDelete" },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					return { old3 = rows[3].old, new3 = rows[3].new, old4 = rows[4].old, bar = rows[1].marks[1][3] }
				end, file)
			)
		end)
	end)

	t.describe("renamed file", function()
		local out = function()
			return texts({
				status = "renamed",
				previous = "old/name.lua",
				additions = 3,
				deletions = 1,
				patch = "@@ -4 +4 @@\n-a\n+b",
			})
		end

		t.it("names the old path in the header", function()
			t.eq(true, out()[1]:match("%(was old/name%.lua%)") ~= nil)
		end)

		t.it("shows a gap above a hunk that starts at line 4", function()
			t.eq("⋯ 3 unchanged lines above", out()[2])
		end)
	end)

	t.describe("hunk header edge cases", function()
		local patch = "@@ -1 +1 @@\n-a\n+b\n@@ -10,0 +11,2 @@ ctx\n+x\n+y"

		t.it("treats omitted counts as 1", function()
			t.eq(
				{ 1, 1 },
				n.exec_lua(function(p)
					local hunks = _G.diff.parse(p)
					return { hunks[1].old_count, hunks[1].new_count }
				end, patch)
			)
		end)

		t.it("gives a pure insertion no old lines", function()
			t.eq(
				{ 10, 0, 11, 2 },
				n.exec_lua(function(p)
					local hunks = _G.diff.parse(p)
					return { hunks[2].old_start, hunks[2].old_count, hunks[2].new_start, hunks[2].new_count }
				end, patch)
			)
		end)

		t.it("counts the gap after a pure insertion from the line after its anchor", function()
			t.eq("⋯ 9 unchanged lines", texts({ status = "modified", additions = 3, deletions = 1, patch = patch })[5])
		end)

		t.it("says a single hidden line is singular", function()
			t.eq("⋯ 1 unchanged line above", texts({ status = "modified", additions = 1, deletions = 0, patch = "@@ -1,0 +2 @@\n+a" })[2])
		end)
	end)

	t.describe("no newline, CRLF, blank context", function()
		t.it("drops CRLF and keeps the note as a plain row", function()
			t.eq(
				{ "a", "\\ No newline at end of file", true },
				n.exec_lua(function()
					local rows = _G.diff.rows({
						status = "modified",
						additions = 1,
						deletions = 1,
						patch = "@@ -1 +1 @@\r\n-a\r\n\\ No newline at end of file\r\n+b\r\n\\ No newline at end of file",
					})
					return { rows[3].text, rows[4].text, rows[4].plain }
				end)
			)
		end)

		t.it("reads a context line that lost its space as a blank line", function()
			local out = texts({ status = "modified", additions = 0, deletions = 0, patch = "@@ -1,3 +1,3 @@\n a\n\n c" })
			t.eq({ "a", "", "c" }, { out[3], out[4], out[5] })
		end)
	end)

	t.describe("no patch", function()
		t.it("shows the header and the placeholder", function()
			t.eq({ "modified  +0 -0", "(diff too large or binary)" }, texts({ status = "modified", additions = 0, deletions = 0 }))
		end)

		t.it("has no bar when there is no change to count", function()
			t.eq(
				{},
				n.exec_lua(function()
					return _G.diff.rows({ status = "modified", additions = 0, deletions = 0 })[1].marks
				end)
			)
		end)
	end)

	t.it("stops at the cap and counts the rest", function()
		t.eq(
			{ 7, "(6 more lines not shown)" },
			n.exec_lua(function()
				local lines = { "@@ -1,10 +1,10 @@" }
				for i = 1, 10 do
					lines[#lines + 1] = "+line " .. i
				end
				local cap = _G.diff.MAX_ROWS
				_G.diff.MAX_ROWS = 4
				local out = _G.texts({ status = "added", additions = 10, deletions = 0, patch = table.concat(lines, "\n") })
				_G.diff.MAX_ROWS = cap
				return { #out, out[#out] }
			end)
		)
	end)

	t.it("gives lines that share little no emphasis", function()
		t.eq(
			{ no_old = true, no_new = true },
			n.exec_lua(function()
				local rows = _G.diff.rows({
					status = "modified",
					additions = 1,
					deletions = 1,
					patch = "@@ -1 +1 @@\n-foo(a, b)\n+return bar",
				})
				return { no_old = rows[3].spans == nil, no_new = rows[4].spans == nil }
			end)
		)
	end)

	t.describe("syntax", function()
		---A lua file diff description with `extra` merged over it.
		local function lua_rows(extra)
			return vim.tbl_extend("force", { status = "modified", additions = 1, deletions = 1, path = "lib/a.lua", patch = SYNTAX_PATCH }, extra or {})
		end

		t.it("colors context code", function()
			t.eq(
				true,
				n.exec_lua(function(f)
					return _G.has_capture(_G.diff.rows(f)[3], "@keyword.lua")
				end, lua_rows())
			)
		end)

		t.it("colors a removed line from the old side", function()
			t.eq(
				true,
				n.exec_lua(function(f)
					local row = _G.diff.rows(f)[4]
					return _G.has_capture(row, "@keyword.return.lua") or _G.has_capture(row, "@keyword.lua")
				end, lua_rows())
			)
		end)

		t.it("colors an added line from the new side", function()
			t.eq(
				true,
				n.exec_lua(function(f)
					local row = _G.diff.rows(f)[5]
					return _G.has_capture(row, "@keyword.return.lua") or _G.has_capture(row, "@keyword.lua")
				end, lua_rows())
			)
		end)

		t.it("keeps only its bar in the header and leaves the band and notes uncolored", function()
			t.eq(
				{ header_syntax = false, band_marks_nil = true },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					return { header_syntax = _G.has_capture(rows[1], "@keyword"), band_marks_nil = rows[2].marks == nil }
				end, lua_rows())
			)
		end)

		t.it("keeps an unknown language plain", function()
			t.eq(
				true,
				n.exec_lua(function(f)
					return _G.diff.rows(f)[3].marks == nil
				end, { status = "modified", additions = 1, deletions = 1, file = "notes.unknownext", patch = SYNTAX_PATCH })
			)
		end)

		t.it("keeps a diff over the cap plain", function()
			t.eq(
				true,
				n.exec_lua(function(f)
					local cap = _G.diff.MAX_SYNTAX_ROWS
					_G.diff.MAX_SYNTAX_ROWS = 2
					local rows = _G.diff.rows(f)
					_G.diff.MAX_SYNTAX_ROWS = cap
					return rows[3].marks == nil
				end, lua_rows())
			)
		end)

		t.it("keeps the file plain when a line is very long", function()
			local long = "@@ -1 +1 @@\n-local a = '" .. string.rep("x", 1100) .. "'\n+local a = 1"
			t.eq(
				{ true, true },
				n.exec_lua(function(f)
					local rows = _G.diff.rows(f)
					return { rows[3].marks == nil, rows[4].marks == nil }
				end, lua_rows({ patch = long }))
			)
		end)

		t.it("colors 2000 rows well under a frame budget of 100 ms", function()
			local lines = { "@@ -1,2000 +1,2000 @@" }
			for i = 1, 2000 do
				lines[#lines + 1] = " local x" .. i .. " = " .. i
			end
			local ms = n.exec_lua(function(f)
				local cap = _G.diff.MAX_SYNTAX_ROWS
				_G.diff.MAX_SYNTAX_ROWS = 5000
				local t0 = vim.uv.hrtime()
				_G.diff.rows(f)
				_G.diff.MAX_SYNTAX_ROWS = cap
				return (vim.uv.hrtime() - t0) / 1e6
			end, lua_rows({ additions = 0, deletions = 0, patch = table.concat(lines, "\n") }))
			t.eq(true, ms < 100)
		end)
	end)
end)
