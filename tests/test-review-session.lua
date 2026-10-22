-- =========================================================================
-- Test: beast.libs.review (propose -> inline hunks -> accept/reject -> save)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-review-session.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local render = require("beast.libs.review.render")
local review = require("beast.libs.review")
local session = require("beast.libs.review.session")

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

-- Silence and capture notices.
local notices = {}
vim.notify = function(msg)
	notices[#notices + 1] = msg
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local counter = 0

--- Write a fresh file and return its path.
local function make_file(content)
	counter = counter + 1
	local path = dir .. "/f" .. counter .. ".txt"
	local f = assert(io.open(path, "wb"))
	f:write(content)
	f:close()
	return path
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

--- Propose and return the buffer plus a table that records the callback result.
local function propose(path, contents)
	local result = {}
	review.propose(path, contents, function(outcome, stats)
		result.outcome, result.stats = outcome, stats
	end)
	return vim.fn.bufnr(vim.fn.fnamemodify(path, ":p")), result
end

local ACTIONS = {
	accept = "accept",
	reject = "reject",
	accept_all = "accept_all",
	reject_all = "reject_all",
	next = "next_hunk",
	prev = "prev_hunk",
}

--- Run a review action the way the global key does: against the current buffer.
local function press(buf, action)
	vim.api.nvim_buf_call(buf, review[ACTIONS[action]])
end

local function marks(buf)
	return #vim.api.nvim_buf_get_extmarks(buf, render.namespace, 0, -1, {})
end

local function lines(buf)
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

print("== accept all ==")
do
	local path = make_file("a\nb\nc\n")
	local buf, res = propose(path, "a\nX\nc\nd\n")
	assert_test("bands painted", marks(buf) > 0)
	assert_eq("buffer untouched while pending", lines(buf), { "a", "b", "c" })
	assert_eq("disk untouched while pending", read(path), "a\nb\nc\n")
	assert_test("no conflict markers in buffer", not vim.tbl_contains(lines(buf), "<<<<<<<"))
	press(buf, "accept_all")
	assert_eq("outcome saved", res.outcome, "saved")
	assert_eq("stats accepted", res.stats.accepted, 2)
	assert_eq("file has proposed content", read(path), "a\nX\nc\nd\n")
	assert_eq("marks cleared", marks(buf), 0)
	assert_test("session released", session.get(buf) == nil)
end

print("== reject all ==")
do
	local path = make_file("a\nb\nc\n")
	local buf, res = propose(path, "a\nX\nc\nd\n")
	press(buf, "reject_all")
	assert_eq("outcome rejected", res.outcome, "rejected")
	assert_eq("stats rejected", res.stats.rejected, 2)
	assert_eq("disk unchanged", read(path), "a\nb\nc\n")
	assert_eq("buffer unchanged", lines(buf), { "a", "b", "c" })
	assert_eq("marks cleared", marks(buf), 0)
end

print("== hunk by hunk, with line shifts ==")
do
	-- Three hunks; the first accept adds lines, shifting the others down.
	local path = make_file("1\n2\n3\n4\n5\n6\n7\n8\n9\n")
	local buf, res = propose(path, "1\nA\nB\nC\n3\n4\n5\nX\n7\n8\n9\nZ\n")
	assert_eq("cursor starts on first hunk", vim.api.nvim_win_get_cursor(0)[1], 2)
	press(buf, "accept") -- 2 -> A B C
	assert_test("still pending after one decision", res.outcome == nil)
	press(buf, "reject") -- 6 -> X rejected
	assert_test("still pending after two decisions", res.outcome == nil)
	press(buf, "accept") -- append Z
	assert_eq("outcome saved", res.outcome, "saved")
	assert_eq("stats", { res.stats.accepted, res.stats.rejected }, { 2, 1 })
	assert_eq("only accepted hunks saved", read(path), "1\nA\nB\nC\n3\n4\n5\n6\n7\n8\n9\nZ\n")
end

print("== all rejected one by one -> rejected, nothing written ==")
do
	local path = make_file("a\nb\n")
	local buf, res = propose(path, "A\nB\n")
	press(buf, "reject")
	assert_eq("outcome rejected", res.outcome, "rejected")
	assert_eq("disk unchanged", read(path), "a\nb\n")
end

print("== new file ==")
do
	local path = dir .. "/sub/new.txt"
	local buf, res = propose(path, "x\ny\n")
	assert_eq("no Current text (buffer is still blank)", lines(buf), { "" })
	press(buf, "accept_all")
	assert_eq("outcome saved", res.outcome, "saved")
	assert_eq("created with exact content", read(path), "x\ny\n")
	assert_eq("no stray blank line in buffer", lines(buf), { "x", "y" })
end

print("== new file rejected ==")
do
	local path = dir .. "/sub/never.txt"
	local buf, res = propose(path, "x\n")
	press(buf, "reject_all")
	assert_eq("outcome rejected", res.outcome, "rejected")
	assert_eq("nothing created", read(path), nil)
	assert_eq("buffer still blank", lines(buf), { "" })
end

print("== close buffer mid-review = reject all ==")
do
	local path = make_file("a\nb\n")
	local buf, res = propose(path, "A\nb\n")
	vim.cmd("bwipeout! " .. buf)
	assert_eq("outcome rejected", res.outcome, "rejected")
	assert_eq("disk unchanged", read(path), "a\nb\n")
end

print("== cancel (Claude gives up) ==")
do
	local path = make_file("a\nb\n")
	local buf, res = propose(path, "A\nb\n")
	session.get(buf):cancel()
	assert_eq("outcome cancelled", res.outcome, "cancelled")
	assert_eq("marks cleared", marks(buf), 0)
	assert_eq("buffer unchanged", lines(buf), { "a", "b" })
	assert_eq("disk unchanged", read(path), "a\nb\n")
end

print("== second proposal waits its turn ==")
do
	local path = make_file("a\nb\n")
	local buf, res1 = propose(path, "A\nb\n")
	local res2 = {}
	review.propose(path, "A\nB\n", function(o)
		res2.outcome = o
	end)
	assert_test("second not started yet", res2.outcome == nil and session.get(buf) ~= nil)
	press(buf, "accept_all")
	assert_eq("first saved", res1.outcome, "saved")
	vim.wait(500, function()
		return session.get(buf) ~= nil
	end)
	assert_test("second session started after first resolved", session.get(buf) ~= nil)
	press(buf, "accept_all")
	assert_eq("second saved", res2.outcome, "saved")
	assert_eq("both applied in order", read(path), "A\nB\n")
end

print("== cancel handles: queued requests ==")
do
	local path = make_file("a\nb\n")
	local res = { a = {}, b = {}, c = {} }
	local function sub(key, text)
		return review.propose(path, text, function(o)
			res[key].outcome = o
		end)
	end
	local cancel_a = sub("a", "A\nb\n")
	local buf = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
	local cancel_b = sub("b", "A\nB\n")
	local cancel_c = sub("c", "A\nb\nC\n")

	cancel_c()
	assert_eq("queued request cancelled", res.c.outcome, "cancelled")
	cancel_b()
	assert_eq("second queued request cancelled", res.b.outcome, "cancelled")
	assert_test("active review undisturbed", session.get(buf) ~= nil and res.a.outcome == nil)

	cancel_c() -- already completed: no-op, no second callback
	cancel_a()
	assert_eq("active request cancelled", res.a.outcome, "cancelled")
	vim.wait(100)
	assert_test("cancelled queue entries never start a session", session.get(buf) == nil)
	assert_eq("file untouched", read(path), "a\nb\n")
	cancel_a() -- after finish: no-op
end

print("== unsaved edits are the Current side and get saved ==")
do
	local path = make_file("a\nb\n")
	vim.fn.bufload(vim.fn.bufadd(path))
	local pre = vim.fn.bufnr(path)
	vim.api.nvim_buf_set_lines(pre, 2, 2, false, { "mine" })
	assert_eq("buffer has unsaved edit", lines(pre), { "a", "b", "mine" })
	local buf, res = propose(path, "A\nb\nmine\n")
	press(buf, "accept_all")
	assert_eq("outcome saved", res.outcome, "saved")
	assert_test("stats flag unsaved edits", res.stats.user_edits == true)
	assert_eq("file saved with edits", read(path), "A\nb\nmine\n")
end

print("== identical proposal ==")
do
	local path = make_file("a\nb\n")
	local buf, res = propose(path, "a\nb\n")
	assert_eq("saved immediately", res.outcome, "saved")
	assert_eq("nothing accepted", res.stats.accepted, 0)
	assert_test("no session left", session.get(buf) == nil)
end

print("== actions with nothing pending ==")
do
	local path = make_file("a\n")
	vim.fn.bufload(vim.fn.bufadd(path))
	local buf = vim.fn.bufnr(path)
	for name, fn in pairs(ACTIONS) do
		notices = {}
		local ok = pcall(vim.api.nvim_buf_call, buf, review[fn])
		assert_test(name .. " does not error", ok)
		assert_eq(name .. " says nothing is pending", notices, { "no review pending in this buffer" })
	end
	assert_eq("buffer untouched", lines(buf), { "a" })
end

print("== actions only affect the current buffer's review ==")
do
	local p1, p2 = make_file("1\n"), make_file("2\n")
	local b1, r1 = propose(p1, "one\n")
	local b2, r2 = propose(p2, "two\n")
	press(b2, "reject_all")
	assert_eq("buffer 2 rejected", r2.outcome, "rejected")
	assert_test("buffer 1 still pending", session.get(b1) ~= nil and r1.outcome == nil)
	press(b1, "accept_all")
	assert_eq("buffer 1 saved", r1.outcome, "saved")
end

print("== next / prev wrap ==")
do
	local path = make_file("1\n2\n3\n4\n5\n6\n7\n")
	local buf, res = propose(path, "1\nA\n3\n4\nB\n6\n7\n")
	assert_eq("starts on first", vim.api.nvim_win_get_cursor(0)[1], 2)
	press(buf, "next")
	assert_eq("next -> second", vim.api.nvim_win_get_cursor(0)[1], 5)
	press(buf, "next")
	assert_eq("next wraps -> first", vim.api.nvim_win_get_cursor(0)[1], 2)
	press(buf, "prev")
	assert_eq("prev wraps -> last", vim.api.nvim_win_get_cursor(0)[1], 5)
	press(buf, "reject_all")
	assert_eq("cleanup", res.outcome, "rejected")
end

print("== queue: a synchronously-completing proposal does not strand the rest ==")
do
	local path = make_file("a\nb\n")
	local buf, res_a = propose(path, "A\nb\n")
	local res_b, res_c = {}, {}
	review.propose(path, "A\nb\n", function(o)
		res_b.outcome = o -- identical to A's result: completes with no session
	end)
	review.propose(path, "A\nB\n", function(o)
		res_c.outcome = o
	end)
	press(buf, "accept_all")
	assert_eq("A saved", res_a.outcome, "saved")
	vim.wait(500, function()
		return session.get(buf) ~= nil
	end)
	assert_eq("B (identical) completed", res_b.outcome, "saved")
	assert_test("C got its session", session.get(buf) ~= nil)
	press(buf, "accept_all")
	assert_eq("C saved", res_c.outcome, "saved")
	assert_eq("final content", read(path), "A\nB\n")
end

print("== queue: a throwing on_done does not strand the queue ==")
do
	local path = make_file("a\nb\n")
	local buf = vim.fn.bufnr(path, true)
	review.propose(path, "A\nb\n", function()
		error("boom")
	end)
	local res2 = {}
	review.propose(path, "A\nB\n", function(o)
		res2.outcome = o
	end)
	press(buf, "accept_all")
	vim.wait(500, function()
		return session.get(buf) ~= nil
	end)
	assert_test("queued proposal still started", session.get(buf) ~= nil)
	assert_test(
		"failure was reported",
		vim.iter(notices):any(function(n)
			return n:find("on_done callback failed", 1, true) ~= nil
		end)
	)
	press(buf, "accept_all")
	assert_eq("queued proposal saved", res2.outcome, "saved")
end

print("== queue: closing the buffer resolves queued proposals ==")
do
	local path = make_file("a\nb\n")
	local buf, res1 = propose(path, "A\nb\n")
	local res2 = {}
	review.propose(path, "A\nB\n", function(o)
		res2.outcome = o
	end)
	vim.cmd("bwipeout! " .. buf)
	vim.wait(500, function()
		return res2.outcome ~= nil
	end)
	assert_eq("pending rejected", res1.outcome, "rejected")
	assert_eq("queued rejected, not left hanging", res2.outcome, "rejected")
	assert_eq("disk unchanged", read(path), "a\nb\n")
end

print("== user deletes a hunk's lines: accept skips instead of clobbering ==")
do
	local path = make_file("a\nb\nc\n")
	local buf, res = propose(path, "a\nX\nc\n")
	vim.api.nvim_buf_set_lines(buf, 1, 2, false, {}) -- user removes the Current line
	press(buf, "accept")
	assert_eq("nothing accepted", res.stats.accepted, 0)
	assert_eq("outcome rejected", res.outcome, "rejected")
	assert_eq("neighbouring lines intact", lines(buf), { "a", "c" })
	assert_test(
		"user was told",
		vim.iter(notices):any(function(n)
			return n:find("moved out of reach", 1, true) ~= nil
		end)
	)
end

print("== write failure is reported ==")
do
	local path = make_file("a\nb\n")
	local buf, res = propose(path, "A\nb\n")
	vim.bo[buf].readonly = true
	press(buf, "accept_all")
	assert_eq("outcome error", res.outcome, "error")
	assert_test("error carries a message", type(res.stats.message) == "string")
	vim.bo[buf].readonly = false
end

print(string.format("\n%d passed, %d failed", passed, failed))
vim.fn.delete(dir, "rf")
os.exit(failed == 0 and 0 or 1)
