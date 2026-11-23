local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("review hunks", function()
	t.before_each(h.clear)

	t.describe("split", function()
		---@param text string
		local function split(text)
			return n.exec_lua(function(s)
				return require("beast.libs.review.hunks").split(s)
			end, text)
		end

		t.it("splits a plain text with a trailing newline", function()
			t.eq({ lines = { "a", "b" }, eol = true, crlf = false }, split("a\nb\n"))
		end)

		t.it("reports a missing trailing newline", function()
			t.eq({ lines = { "a", "b" }, eol = false, crlf = false }, split("a\nb"))
		end)

		t.it("splits the empty string into no lines", function()
			t.eq({ lines = {}, eol = false, crlf = false }, split(""))
		end)

		t.it("treats a lone newline as one empty line", function()
			t.eq({ "" }, split("\n").lines)
		end)

		t.it("detects crlf", function()
			t.eq({ lines = { "a", "b" }, eol = true, crlf = true }, split("a\r\nb\r\n"))
		end)
	end)

	t.describe("compute", function()
		---Compute hunks in the child and verify the round-trip invariant there: applying every
		---hunk to `old` (bottom-up so rows stay valid) reproduces `new`.
		---@param old string[]
		---@param new string[]
		---@return { hunks: table[], round_trip: string[] }
		local function check(old, new)
			return n.exec_lua(function(o, nw)
				local hs = require("beast.libs.review.hunks").compute(o, nw)
				local out = vim.deepcopy(o)
				for i = #hs, 1, -1 do
					local hunk = hs[i]
					for _ = 1, hunk.old_count do
						table.remove(out, hunk.row + 1)
					end
					for j, line in ipairs(hunk.new) do
						table.insert(out, hunk.row + j, line)
					end
				end
				return { hunks = hs, round_trip = out }
			end, old, new)
		end

		---Assert the round trip and the hunk count, return the hunks.
		---@param old string[]
		---@param new string[]
		---@param count integer
		local function hunks_of(old, new, count)
			local r = check(old, new)
			t.eq(new, r.round_trip)
			t.eq(count, #r.hunks)
			return r.hunks
		end

		local old = { "a", "b", "c" }

		t.it("yields no hunks for identical input", function()
			t.eq({}, check(old, { "a", "b", "c" }).hunks)
		end)

		t.it("replaces a middle line", function()
			local hs = hunks_of(old, { "a", "X", "c" }, 1)
			t.eq(1, hs[1].row)
			t.eq({ "b" }, hs[1].old)
			t.eq({ "X" }, hs[1].new)
		end)

		t.it("inserts at the start", function()
			local hs = hunks_of(old, { "X", "a", "b", "c" }, 1)
			t.eq(0, hs[1].row)
			t.eq(0, hs[1].old_count)
		end)

		t.it("inserts in the middle", function()
			local hs = hunks_of(old, { "a", "X", "b", "c" }, 1)
			t.eq(1, hs[1].row)
			t.eq(0, hs[1].old_count)
		end)

		t.it("inserts at the end", function()
			local hs = hunks_of(old, { "a", "b", "c", "X" }, 1)
			t.eq(3, hs[1].row)
		end)

		t.it("deletes a middle line", function()
			local hs = hunks_of(old, { "a", "c" }, 1)
			t.eq(1, hs[1].row)
			t.eq({ "b" }, hs[1].old)
			t.eq({}, hs[1].new)
		end)

		t.it("deletes the first line, the last line and everything", function()
			hunks_of(old, { "b", "c" }, 1)
			hunks_of(old, { "a", "b" }, 1)
			hunks_of(old, {}, 1)
		end)

		t.it("produces several hunks for separate changes", function()
			local hs = hunks_of({ "a", "b", "c", "d", "e" }, { "A", "b", "c", "X", "Y", "e" }, 2)
			t.eq(0, hs[1].row)
			t.eq(3, hs[2].row)
		end)

		t.it("turns an empty file into content", function()
			local hs = hunks_of({}, { "a", "b" }, 1)
			t.eq(0, hs[1].row)
			t.eq(0, hs[1].old_count)
			t.eq({ "a", "b" }, hs[1].new)
		end)

		t.it("handles empty to empty, duplicate lines, blank lines and full rewrites", function()
			hunks_of({}, {}, 0)
			hunks_of({ "x", "x", "x" }, { "x", "x" }, 1)
			hunks_of({ "a", "", "b" }, { "a", "", "", "b" }, 1)
			hunks_of({ "a", "b" }, { "c", "d", "e" }, 1)
		end)

		-- Neovim reports an empty buffer as { "" }, not {}. Callers (session.lua)
		-- must pass {} for an empty/new file, otherwise "Current" is one blank line.
		t.it("sees a lone newline against an empty buffer as no change", function()
			t.eq(
				{},
				n.exec_lua(function()
					local hunks = require("beast.libs.review.hunks")
					return hunks.compute({ "" }, hunks.split("\n").lines)
				end)
			)
		end)

		t.it("replaces the blank line of a { '' } buffer", function()
			local hs = hunks_of({ "" }, { "a", "b" }, 1)
			t.eq(1, hs[1].old_count)
		end)
	end)

	t.describe("compute on split output", function()
		---@param old string[]
		---@param text string
		local function against(old, text)
			return n.exec_lua(function(o, s)
				local hunks = require("beast.libs.review.hunks")
				return hunks.compute(o, hunks.split(s).lines)
			end, old, text)
		end

		t.it("ignores a trailing newline difference", function()
			t.eq({}, against({ "a", "b" }, "a\nb\n"))
			t.eq({}, against({ "a", "b" }, "a\nb"))
		end)

		t.it("ignores crlf line endings", function()
			t.eq({}, against({ "a", "b" }, "a\r\nb\r\n"))
		end)

		t.it("still finds a change in a crlf proposal", function()
			local r = n.exec_lua(function(o, s)
				local hunks = require("beast.libs.review.hunks")
				local new = hunks.split(s).lines
				local hs = hunks.compute(o, new)
				local out = vim.deepcopy(o)
				for i = #hs, 1, -1 do
					for _ = 1, hs[i].old_count do
						table.remove(out, hs[i].row + 1)
					end
					for j, line in ipairs(hs[i].new) do
						table.insert(out, hs[i].row + j, line)
					end
				end
				return { count = #hs, round_trip = out, new = new }
			end, { "a", "b" }, "a\r\nX\r\n")
			t.eq(1, r.count)
			t.eq(r.new, r.round_trip)
		end)
	end)
end)
