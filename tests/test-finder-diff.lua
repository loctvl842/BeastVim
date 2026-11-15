-- =========================================================================
-- Test: the finder's diff of a changed file (patch -> rows)
-- (docs/dev-specs/finder-diff-preview.md, Phase 3)
--
-- Run as: nvim --clean --headless -l tests/test-finder-diff.lua
-- =========================================================================
vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0
local function eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n    expected: " .. vim.inspect(expected) .. "\n    got:      " .. vim.inspect(got) .. "\n")
	end
end

local diff = require("beast.libs.finder.ui.diff")

---@param file table
---@return string[] texts, table[] rows
local function texts(file)
	local rows = diff.rows(file)
	local out = {}
	for i, r in ipairs(rows) do
		out[i] = r.text
	end
	return out, rows
end

local two_hunks = table.concat({
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

io.write("\n== two hunks ==\n")
do
	local file = { status = "modified", additions = 5, deletions = 6, patch = two_hunks }
	local t, rows = texts(file)
	eq(
		"header, gap above, band, rows, gap, band, rows",
		{ t[1], t[2], t[3] },
		{ "modified  +5 -6  ■■■■■", "⋯ 19 unchanged lines above", "▸ @@ -20,7 +20,7 @@ mesh = jarvis" }
	)
	local gap_between
	for _, r in ipairs(rows) do
		if r.text:find("unchanged lines$") then
			gap_between = r.text
		end
	end
	eq("hidden lines between the hunks", gap_between, "⋯ 13 unchanged lines")
	local removed, added
	for _, r in ipairs(rows) do
		if r.sign == "-" then
			removed = r
		elseif r.sign == "+" then
			added = r
		end
	end
	eq("removed row has the old number only", { removed.old, removed.new }, { 23, nil })
	eq("added row has the new number only", { added.old, added.new }, { nil, 23 })
	eq("an edit pairs the changed words", { removed.spans ~= nil, added.spans ~= nil }, { true, true })
	local after = rows[#rows]
	eq("numbers carry on after the gap", { after.old, after.new, after.text }, { 41, 41, "`jarvis` is the one pane" })
	eq(
		"the stat bar splits additions and deletions",
		{ rows[1].marks[1][3], rows[1].marks[5][3] },
		{ "BeastViewDiffStatAdd", "BeastViewDiffStatDelete" }
	)
end

io.write("\n== added and deleted files ==\n")
do
	local t, rows = texts({ status = "added", additions = 2, deletions = 0, patch = "@@ -0,0 +1,2 @@\n+a\n+b" })
	eq("no gap above a new file", t, { "added     +2 -0  ■■■■■", "▸ @@ -0,0 +1,2 @@", "a", "b" })
	eq("only new numbers", { rows[3].old, rows[3].new, rows[4].new }, { nil, 1, 2 })
	t, rows = texts({ status = "removed", additions = 0, deletions = 2, patch = "@@ -1,2 +0,0 @@\n-a\n-b" })
	eq("no gap above a deleted file", t, { "removed   +0 -2  ■■■■■", "▸ @@ -1,2 +0,0 @@", "a", "b" })
	eq("only old numbers", { rows[3].old, rows[3].new, rows[4].old }, { 1, nil, 2 })
	eq("a deleted file's bar is all red", rows[1].marks[1][3], "BeastViewDiffStatDelete")
end

io.write("\n== renamed file ==\n")
do
	local t = texts({ status = "renamed", previous = "old/name.lua", additions = 3, deletions = 1, patch = "@@ -4 +4 @@\n-a\n+b" })
	eq("the header names the old path", t[1]:match("%(was old/name%.lua%)") ~= nil, true)
	eq("a gap above a hunk that starts at line 4", t[2], "⋯ 3 unchanged lines above")
end

io.write("\n== hunk header edge cases ==\n")
do
	local h = diff.parse("@@ -1 +1 @@\n-a\n+b\n@@ -10,0 +11,2 @@ ctx\n+x\n+y")
	eq("omitted counts are 1", { h[1].old_count, h[1].new_count }, { 1, 1 })
	eq("a pure insertion has no old lines", { h[2].old_start, h[2].old_count, h[2].new_start, h[2].new_count }, { 10, 0, 11, 2 })
	local t = texts({ status = "modified", additions = 3, deletions = 1, patch = "@@ -1 +1 @@\n-a\n+b\n@@ -10,0 +11,2 @@ ctx\n+x\n+y" })
	eq("the gap after a pure insertion counts from the line after its anchor", t[5], "⋯ 9 unchanged lines")
	eq(
		"a single hidden line is singular",
		texts({ status = "modified", additions = 1, deletions = 0, patch = "@@ -1,0 +2 @@\n+a" })[2],
		"⋯ 1 unchanged line above"
	)
end

io.write("\n== no newline, CRLF, blank context ==\n")
do
	local t, rows = texts({
		status = "modified",
		additions = 1,
		deletions = 1,
		patch = "@@ -1 +1 @@\r\n-a\r\n\\ No newline at end of file\r\n+b\r\n\\ No newline at end of file",
	})
	eq("CRLF is dropped, the note stays a plain row", { t[3], t[4], rows[4].plain }, { "a", "\\ No newline at end of file", true })
	t = texts({ status = "modified", additions = 0, deletions = 0, patch = "@@ -1,3 +1,3 @@\n a\n\n c" })
	eq("a context line that lost its space is a blank line", { t[3], t[4], t[5] }, { "a", "", "c" })
end

io.write("\n== no patch ==\n")
do
	local t, rows = texts({ status = "modified", additions = 0, deletions = 0 })
	eq("the header and the placeholder", t, { "modified  +0 -0", "(diff too large or binary)" })
	eq("no bar when there is no change to count", rows[1].marks, {})
end

io.write("\n== more than the cap ==\n")
do
	local lines = { "@@ -1,10 +1,10 @@" }
	for i = 1, 10 do
		lines[#lines + 1] = "+line " .. i
	end
	local cap = diff.MAX_ROWS
	diff.MAX_ROWS = 4
	local t = texts({ status = "added", additions = 10, deletions = 0, patch = table.concat(lines, "\n") })
	diff.MAX_ROWS = cap
	eq("rows stop at the cap and a note counts the rest", { #t, t[#t] }, { 7, "(6 more lines not shown)" })
end

io.write("\n== lines that share little get no emphasis ==\n")
do
	local _, rows = texts({ status = "modified", additions = 1, deletions = 1, patch = "@@ -1 +1 @@\n-foo(a, b)\n+return bar" })
	eq("unrelated lines", { rows[3].spans, rows[4].spans }, { nil, nil })
end

io.write("\n== syntax ==\n")
do
	local patch = "@@ -1,2 +1,2 @@\n local a = 1\n-return a\n+return a + 2"
	local function has_capture(row, name)
		for _, m in ipairs(row.marks or {}) do
			if m[3]:find(name, 1, true) then
				return true
			end
		end
		return false
	end
	local rows = diff.rows({ status = "modified", additions = 1, deletions = 1, path = "lib/a.lua", patch = patch })
	-- header, band, context, removed, added
	eq("context code is colored", has_capture(rows[3], "@keyword.lua"), true)
	eq("a removed line is colored from the old side", has_capture(rows[4], "@keyword.return.lua") or has_capture(rows[4], "@keyword.lua"), true)
	eq("an added line is colored from the new side", has_capture(rows[5], "@keyword.return.lua") or has_capture(rows[5], "@keyword.lua"), true)
	eq("the header keeps only its bar", has_capture(rows[1], "@keyword"), false)
	eq("the band and notes are not colored", rows[2].marks, nil)

	rows = diff.rows({ status = "modified", additions = 1, deletions = 1, file = "notes.unknownext", patch = patch })
	eq("an unknown language stays plain", rows[3].marks, nil)

	local cap = diff.MAX_SYNTAX_ROWS
	diff.MAX_SYNTAX_ROWS = 2
	rows = diff.rows({ status = "modified", additions = 1, deletions = 1, path = "lib/a.lua", patch = patch })
	diff.MAX_SYNTAX_ROWS = cap
	eq("a diff over the cap stays plain", rows[3].marks, nil)

	local long = "@@ -1 +1 @@\n-local a = '" .. string.rep("x", 1100) .. "'\n+local a = 1"
	rows = diff.rows({ status = "modified", additions = 1, deletions = 1, path = "lib/a.lua", patch = long })
	eq("a very long line keeps the file plain", { rows[3].marks, rows[4].marks }, { nil, nil })

	local lines = { "@@ -1,2000 +1,2000 @@" }
	for i = 1, 2000 do
		lines[#lines + 1] = " local x" .. i .. " = " .. i
	end
	local t0 = vim.uv.hrtime()
	diff.MAX_SYNTAX_ROWS = 5000
	diff.rows({ status = "modified", additions = 0, deletions = 0, path = "lib/a.lua", patch = table.concat(lines, "\n") })
	diff.MAX_SYNTAX_ROWS = cap
	local ms = (vim.uv.hrtime() - t0) / 1e6
	io.write(("  colored 2000 rows in %.1f ms\n"):format(ms))
	eq("coloring 2000 rows takes well under a frame budget of 100 ms", ms < 100, true)
end

io.write("\n== Summary ==\n")
io.write(("  Passed: %d\n  Failed: %d\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
