-- =========================================================================
-- Test: Git hunk preview row layout
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-git-preview.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = { colors = { set_hl = function() end } }

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	local function tbl_eq(a, b)
		if type(a) ~= type(b) then
			return false
		end
		if type(a) ~= "table" then
			return a == b
		end
		for k, v in pairs(a) do
			if not tbl_eq(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end
	if tbl_eq(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n")
		io.write("    expected: " .. vim.inspect(expected) .. "\n")
		io.write("    got:      " .. vim.inspect(got) .. "\n")
	end
end

---@param lines string[]
---@return integer buf
local function make_buf(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_current_buf(buf)
	return buf
end

local preview = require("beast.libs.git.preview")
local build_rows = preview._test.build_rows
local render_rows = preview._test.render_rows

-- Sample buffer of 30 baseline lines; we tweak it to match what the
-- fixture script produces, then construct hunks by hand.
local function baseline(n)
	local out = {}
	for i = 1, n do
		out[i] = ("line %02d — baseline"):format(i)
	end
	return out
end

local base_text = table.concat(baseline(30), "\n") .. "\n"

-- =========================================================================
-- Test: change hunk at line 5 (current b_start = 4)
-- =========================================================================
io.write("\n== change hunk (line 5 modified, b_start=4 after topdelete) ==\n")
do
	-- Current buffer: drop line 1, modify line 5. Result: 29 lines.
	local cur = baseline(30)
	table.remove(cur, 1)
	cur[4] = "line 05 — MODIFIED (change)"
	local buf = make_buf(cur)

	local hunk = { a_start = 5, a_count = 1, b_start = 4, b_count = 1 }
	local rows = build_rows(buf, { base = base_text }, { hunk }, 3)

	-- Expect the removed and added rows to share lnum=4.
	-- Find the - and + rows.
	local minus, plus
	for _, r in ipairs(rows) do
		if r.marker == "- " then
			minus = r
		end
		if r.marker == "+ " then
			plus = r
		end
	end
	assert_eq("removed line uses current b_start", minus and minus.lnum, 4)
	assert_eq("added line uses b_start", plus and plus.lnum, 4)

	local body = render_rows(rows)
	-- Context: lines 1,2,3 before; 5,6,7 after (in current buffer).
	assert_eq("body[1]", body[1], "line 02 — baseline") -- current line 1 = baseline 02
end

-- =========================================================================
-- Test: topdelete (baseline line 1 removed, b_start=0)
-- =========================================================================
io.write("\n== topdelete (b_start=0) ==\n")
do
	local cur = baseline(30)
	table.remove(cur, 1)
	local buf = make_buf(cur)

	local hunk = { a_start = 1, a_count = 1, b_start = 0, b_count = 0 }
	local rows = build_rows(buf, { base = base_text }, { hunk }, 3)

	local minus = rows[1]
	assert_eq("topdelete removed lnum is clamped to 1", minus.lnum, 1)
	assert_eq("topdelete first row is removed", minus.marker, "- ")

	-- Trailing context: current lines 1,2,3 = baseline 02,03,04.
	assert_eq("row[2] lnum (context after)", rows[2].lnum, 1)
	assert_eq("row[2] marker (context after)", rows[2].marker, "  ")
end

-- =========================================================================
-- Test: pure add hunk (a_count=0)
-- =========================================================================
io.write("\n== pure add (3 lines inserted at b_start=11) ==\n")
do
	local cur = baseline(30)
	-- Insert 3 new lines after baseline line 10.
	table.insert(cur, 11, "X")
	table.insert(cur, 12, "Y")
	table.insert(cur, 13, "Z")
	local buf = make_buf(cur)

	local hunk = { a_start = 10, a_count = 0, b_start = 11, b_count = 3 }
	local rows = build_rows(buf, { base = base_text }, { hunk }, 0)

	assert_eq("3 added rows", #rows, 3)
	assert_eq("first added lnum", rows[1].lnum, 11)
	assert_eq("second added lnum", rows[2].lnum, 12)
	assert_eq("third added lnum", rows[3].lnum, 13)
	for _, r in ipairs(rows) do
		assert_eq("added marker", r.marker, "+ ")
	end
end

-- =========================================================================
-- Test: render_rows gutter width
-- =========================================================================
io.write("\n== render_rows gutter ==\n")
do
	local rows = {
		{ lnum = 4, marker = "- ", text = "old", hl = "BeastGitPreviewDelete" },
		{ lnum = 4, marker = "+ ", text = "new", hl = "BeastGitPreviewAdd" },
		{ lnum = 100, marker = "  ", text = "ctx" },
	}
	local body, _, gutters, gw = render_rows(rows)
	assert_eq("gutter prefix width fits max lnum", gw, 6)
	assert_eq("removed gutter lnum", gutters[1].lnum_text, "  4 ")
	assert_eq("removed gutter marker", gutters[1].marker, "- ")
	assert_eq("removed gutter marker_hl", gutters[1].marker_hl, "BeastGitPreviewDelete")
	assert_eq("added gutter marker", gutters[2].marker, "+ ")
	assert_eq("added gutter marker_hl", gutters[2].marker_hl, "BeastGitPreviewAdd")
	assert_eq("removed gutter lnum_hl", gutters[1].lnum_hl, "BeastGitPreviewDelete")
	assert_eq("added gutter lnum_hl", gutters[2].lnum_hl, "BeastGitPreviewAdd")
	assert_eq("context gutter lnum_hl", gutters[3].lnum_hl, "LineNr")
	assert_eq("removed body row", body[1], "old")
	assert_eq("added body row", body[2], "new")
	assert_eq("context body row", body[3], "ctx")
end

-- =========================================================================
-- Summary
-- =========================================================================
io.write("\n== Summary ==\n")
io.write(("  Passed: %d\n  Failed: %d\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
