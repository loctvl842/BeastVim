-- =========================================================================
-- Test: Autopairs skip rules (skip_next, skip_ts, skip_unbalanced, markdown)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-autopairs-skip.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed = 0
local failed = 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n         expected: " .. vim.inspect(expected) .. "\n         got:      " .. vim.inspect(got) .. "\n")
	end
end

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local KEY_UP = vim.api.nvim_replace_termcodes("<Up>", true, true, true)

local skip = require("beast.libs.autopairs.skip")

-- Build a context with sensible defaults; override per test.
local function ctx(t)
	return vim.tbl_deep_extend("force", {
		open = "(",
		close = ")",
		neigh_pattern = "[^\\].",
		before = " ",
		after = " ",
		line = "",
		before_full = "",
		row = 1,
		col = 0,
	}, t or {})
end

-- =========================================================================
-- skip_next
-- =========================================================================

io.write("\n--- skip_next ---\n")
do
	local nil_cfg = { skip_next = nil }
	local cfg = { skip_next = "[%w]" }

	assert_test("nil pattern → never skip", select(1, skip.should_skip(nil_cfg, ctx({ after = "f" }))) == false)
	assert_test("after='f' + [%w] → skip", select(1, skip.should_skip(cfg, ctx({ after = "f" }))) == true)
	assert_test("after=' ' + [%w] → no skip", select(1, skip.should_skip(cfg, ctx({ after = " " }))) == false)
	assert_test("after='' (EOL) → no skip", select(1, skip.should_skip(cfg, ctx({ after = "" }))) == false)
	-- LazyVim default set: alnum, %, ', [, ", ., `, $
	local lvz = { skip_next = [=[[%w%%%'%[%"%.%`%$]]=] }
	assert_test("LazyVim pattern: after='.' → skip", select(1, skip.should_skip(lvz, ctx({ after = "." }))))
	assert_test("LazyVim pattern: after='$' → skip", select(1, skip.should_skip(lvz, ctx({ after = "$" }))))
	assert_test("LazyVim pattern: after=' ' → no skip", select(1, skip.should_skip(lvz, ctx({ after = " " }))) == false)
end

-- =========================================================================
-- skip_unbalanced
-- =========================================================================

io.write("\n--- skip_unbalanced ---\n")
do
	local cfg = { skip_unbalanced = true }

	-- after must equal close for the rule to even apply
	assert_test("after != close → no skip", select(1, skip.should_skip(cfg, ctx({ after = "x", line = "((())" }))) == false)

	-- Balanced line: one ( and one ) so far
	assert_test("balanced line → no skip", select(1, skip.should_skip(cfg, ctx({ after = ")", line = "()", open = "(", close = ")" }))) == false)

	-- More closers than openers: e.g. user is at `foo))|` and now types `(`,
	-- skip_unbalanced fires because next-char veto checks the line state.
	-- For the rule to trigger from `open` action, we still need after==close.
	assert_test(
		"more closers than openers → skip",
		select(1, skip.should_skip(cfg, ctx({ after = ")", line = "))) ", open = "(", close = ")" }))) == true
	)

	-- Equal counts → no skip
	assert_test("equal counts → no skip", select(1, skip.should_skip(cfg, ctx({ after = ")", line = "()()", open = "(", close = ")" }))) == false)

	-- Symmetric pair (quotes) should NEVER trigger this rule (open == close)
	assert_test(
		"symmetric pair (quotes) → never skip via unbalanced",
		select(1, skip.should_skip(cfg, ctx({ after = '"', line = '""""""', open = '"', close = '"' }))) == false
	)

	-- Disabled
	local off = { skip_unbalanced = false }
	assert_test(
		"flag off → no skip even when unbalanced",
		select(1, skip.should_skip(off, ctx({ after = ")", line = "))) ", open = "(", close = ")" }))) == false
	)
end

-- =========================================================================
-- markdown fence expansion
-- =========================================================================

io.write("\n--- markdown ---\n")
do
	local cfg = { markdown = true }
	local expected = "`\n```" .. KEY_UP

	-- Set up a markdown buffer so vim.bo.filetype == "markdown"
	vim.cmd("enew")
	vim.bo.filetype = "markdown"

	-- Two backticks already on the line, typing the third → expand
	local skipped, override = skip.should_skip(cfg, ctx({ open = "`", before_full = "``" }))
	assert_test("markdown ``→``` expansion: skipped=true", skipped == true)
	assert_eq("markdown ``→``` expansion: override matches", override, expected)

	-- Only one backtick on the line → no expansion
	skipped, override = skip.should_skip(cfg, ctx({ open = "`", before_full = "`" }))
	assert_test("markdown `→ no expansion: skipped=false", skipped == false)
	assert_test("markdown `→ no override", override == nil)

	-- Wrong filetype
	vim.bo.filetype = "lua"
	skipped, override = skip.should_skip(cfg, ctx({ open = "`", before_full = "``" }))
	assert_test("non-markdown ft → no expansion", skipped == false and override == nil)

	-- Wrong open char
	vim.bo.filetype = "markdown"
	skipped, override = skip.should_skip(cfg, ctx({ open = "(", before_full = "``" }))
	assert_test("open != ` → no expansion", skipped == false and override == nil)

	-- markdown flag off
	local off = { markdown = false }
	skipped, override = skip.should_skip(off, ctx({ open = "`", before_full = "``" }))
	assert_test("markdown flag off → no expansion", skipped == false and override == nil)
end

-- =========================================================================
-- skip_ts (treesitter capture-at-cursor)
-- =========================================================================

io.write("\n--- skip_ts ---\n")
do
	-- Lua parser ships with Neovim core. Open a scratch buffer with Lua
	-- content and start the parser to enable capture lookups.
	vim.cmd("enew")
	vim.bo.filetype = "lua"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, {
		'local s = "hello world"',
		"local n = 42",
	})

	local ok = pcall(vim.treesitter.start, 0, "lua")
	if not ok then
		io.write("  SKIP: lua treesitter parser unavailable\n")
	else
		-- Force a parse so captures are available synchronously in headless mode.
		vim.treesitter.get_parser(0):parse()

		local cfg = { skip_ts = { "string" } }

		-- Place cursor inside the string "hello world" — col 18 (zero-based
		-- byte offset into line 1) sits on the 'w' inside the string.
		vim.api.nvim_win_set_cursor(0, { 1, 18 })
		local in_str = ctx({ row = 1, col = 18 })
		assert_test("inside string literal → skip", select(1, skip.should_skip(cfg, in_str)) == true)

		-- Place cursor on the `n` in `local n = 42` (line 2, col 6) — code, not string.
		vim.api.nvim_win_set_cursor(0, { 2, 6 })
		local in_code = ctx({ row = 2, col = 6 })
		assert_test("inside code → no skip", select(1, skip.should_skip(cfg, in_code)) == false)

		-- Empty skip_ts list → no skip
		local empty = { skip_ts = {} }
		assert_test("empty skip_ts list → no skip", select(1, skip.should_skip(empty, in_str)) == false)

		-- Multi-name list: matching one of several
		local multi = { skip_ts = { "comment", "string" } }
		vim.api.nvim_win_set_cursor(0, { 1, 18 })
		assert_test("multi-name list w/ match → skip", select(1, skip.should_skip(multi, in_str)) == true)
	end

	-- Buffer with no parser at all (plain scratch, no filetype) — must not raise.
	vim.cmd("enew")
	vim.bo.filetype = ""
	local cfg = { skip_ts = { "string" } }
	local ok2, result = pcall(skip.should_skip, cfg, ctx())
	assert_test("buffer w/o parser → no error", ok2)
	assert_test("buffer w/o parser → no skip", ok2 and result == false)
end

-- =========================================================================
-- Rule composition — first vote wins
-- =========================================================================

io.write("\n--- composition ---\n")
do
	-- markdown override beats skip_next: in a markdown buffer with `` and
	-- skip_next set to alnum, typing ` (next-char is space) should still
	-- give us the fence expansion.
	vim.cmd("enew")
	vim.bo.filetype = "markdown"
	local cfg = { skip_next = "[%w]", markdown = true }
	local skipped, override = skip.should_skip(cfg, ctx({ open = "`", before_full = "``", after = " " }))
	assert_test("markdown beats skip_next when both could fire", skipped and override ~= nil)

	-- Pure skip_next path returns no override
	vim.bo.filetype = "lua"
	local only_next = { skip_next = "[%w]" }
	local s, o = skip.should_skip(only_next, ctx({ after = "f" }))
	assert_test("skip_next: skipped without override", s == true and o == nil)
end

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
