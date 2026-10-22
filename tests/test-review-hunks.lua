-- =========================================================================
-- Test: beast.libs.review.hunks (buffer-vs-proposal hunk computation)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-review-hunks.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local hunks = require("beast.libs.review.hunks")

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

--- Apply every hunk to `old` (bottom-up so rows stay valid) and return the result.
local function apply_all(old, hs)
	local out = vim.deepcopy(old)
	for i = #hs, 1, -1 do
		local h = hs[i]
		for _ = 1, h.old_count do
			table.remove(out, h.row + 1)
		end
		for j, line in ipairs(h.new) do
			table.insert(out, h.row + j, line)
		end
	end
	return out
end

--- Compute hunks and verify the round-trip invariant: applying them reproduces `new`.
local function check(name, old, new, expected_count)
	local hs = hunks.compute(old, new)
	assert_eq(name .. " (round-trip)", apply_all(old, hs), new)
	if expected_count then
		assert_eq(name .. " (hunk count)", #hs, expected_count)
	end
	return hs
end

print("== split ==")
do
	assert_eq("split plain", hunks.split("a\nb\n"), { lines = { "a", "b" }, eol = true, crlf = false })
	assert_eq("split no trailing newline", hunks.split("a\nb"), { lines = { "a", "b" }, eol = false, crlf = false })
	assert_eq("split empty", hunks.split(""), { lines = {}, eol = false, crlf = false })
	assert_eq("split lone newline is one empty line", hunks.split("\n").lines, { "" })
	assert_eq("split crlf", hunks.split("a\r\nb\r\n"), { lines = { "a", "b" }, eol = true, crlf = true })
end

print("== compute ==")
do
	local old = { "a", "b", "c" }

	assert_eq("identical -> no hunks", hunks.compute(old, { "a", "b", "c" }), {})

	local h = check("replace middle", old, { "a", "X", "c" }, 1)
	assert_eq("replace middle: row", h[1].row, 1)
	assert_eq("replace middle: old", h[1].old, { "b" })
	assert_eq("replace middle: new", h[1].new, { "X" })

	h = check("insert at start", old, { "X", "a", "b", "c" }, 1)
	assert_eq("insert at start: row", h[1].row, 0)
	assert_eq("insert at start: old_count", h[1].old_count, 0)

	h = check("insert in middle", old, { "a", "X", "b", "c" }, 1)
	assert_eq("insert in middle: row", h[1].row, 1)
	assert_eq("insert in middle: old_count", h[1].old_count, 0)

	h = check("insert at end", old, { "a", "b", "c", "X" }, 1)
	assert_eq("insert at end: row", h[1].row, 3)

	h = check("delete middle", old, { "a", "c" }, 1)
	assert_eq("delete middle: row", h[1].row, 1)
	assert_eq("delete middle: old", h[1].old, { "b" })
	assert_eq("delete middle: new empty", h[1].new, {})

	check("delete first", old, { "b", "c" }, 1)
	check("delete last", old, { "a", "b" }, 1)
	check("delete everything", old, {}, 1)

	h = check("multi hunk", { "a", "b", "c", "d", "e" }, { "A", "b", "c", "X", "Y", "e" }, 2)
	assert_eq("multi hunk: first row", h[1].row, 0)
	assert_eq("multi hunk: second row", h[2].row, 3)

	h = check("empty file -> content", {}, { "a", "b" }, 1)
	assert_eq("empty file: row", h[1].row, 0)
	assert_eq("empty file: old_count", h[1].old_count, 0)
	assert_eq("empty file: new", h[1].new, { "a", "b" })

	check("empty -> empty", {}, {}, 0)
	check("duplicate lines", { "x", "x", "x" }, { "x", "x" }, 1)
	check("blank lines", { "a", "", "b" }, { "a", "", "", "b" }, 1)
	check("whole file rewritten", { "a", "b" }, { "c", "d", "e" }, 1)

	-- Neovim reports an empty buffer as { "" }, not {}. Callers (session.lua)
	-- must pass {} for an empty/new file, otherwise "Current" is one blank line.
	assert_eq("lone newline vs empty buffer -> no hunks", hunks.compute({ "" }, hunks.split("\n").lines), {})
	local h2 = check("{''} buffer -> content replaces the blank line", { "" }, { "a", "b" }, 1)
	assert_eq("{''} buffer: old_count is 1, not 0", h2[1].old_count, 1)
end

print("== compute on split output (eol / crlf variants) ==")
do
	local old = { "a", "b" }
	assert_eq("trailing newline proposal == same lines", hunks.compute(old, hunks.split("a\nb\n").lines), {})
	assert_eq("no trailing newline proposal == same lines", hunks.compute(old, hunks.split("a\nb").lines), {})
	assert_eq("crlf proposal == same lines", hunks.compute(old, hunks.split("a\r\nb\r\n").lines), {})
	check("crlf proposal with change", old, hunks.split("a\r\nX\r\n").lines, 1)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
