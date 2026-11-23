local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("git hunk preview", function()
	t.before_each(function()
		h.clear()
		-- Child-side helpers: `_G.gp` builds rows for unstaged hunks (live buffer is the source, the removed side
		-- comes from the base text).
		n.exec_lua(function()
			local preview = require("beast.libs.git.preview")
			local gp = { preview = preview }
			---@param lines string[]
			function gp.make_buf(lines)
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.api.nvim_set_current_buf(buf)
				return buf
			end
			---Baseline of `count` lines, matching the fixture script.
			function gp.baseline(count)
				local out = {}
				for i = 1, count do
					out[i] = ("line %02d - baseline"):format(i)
				end
				return out
			end
			function gp.base_text()
				return table.concat(gp.baseline(30), "\n") .. "\n"
			end
			function gp.rows(buf, base_text, hunks, ctx_n)
				local build_rows = preview._test.build_rows
				return build_rows(preview._test.buffer_source(buf), base_text, nil, hunks, ctx_n)
			end
			_G.gp = gp
		end)
	end)

	t.describe("change hunk (line 5 modified, b_start=4 after topdelete)", function()
		---@return { minus_new: integer?, plus_new: integer?, body1: string }
		local function run()
			return n.exec_lua(function()
				local gp = _G.gp
				-- Current buffer: drop line 1, modify line 5. Result: 29 lines.
				local cur = gp.baseline(30)
				table.remove(cur, 1)
				cur[4] = "line 05 - MODIFIED (change)"
				local buf = gp.make_buf(cur)
				local rows = gp.rows(buf, gp.base_text(), { { a_start = 5, a_count = 1, b_start = 4, b_count = 1 } }, 3)
				local minus, plus
				for _, r in ipairs(rows) do
					if r.sign == "-" then
						minus = r
					end
					if r.sign == "+" then
						plus = r
					end
				end
				local body = require("beast.libs.view.diff").render(rows, { columns = 1 }).body
				return { minus_new = minus and minus.new, plus_new = plus and plus.new, body1 = body[1] }
			end)
		end

		t.it("removed line uses current b_start", function()
			t.eq(4, run().minus_new)
		end)
		t.it("added line uses b_start", function()
			t.eq(4, run().plus_new)
		end)
		t.it("body starts with the first context line", function()
			-- current line 1 = baseline 02
			t.eq("line 02 - baseline", run().body1)
		end)
	end)

	t.describe("topdelete (baseline line 1 removed, b_start=0)", function()
		---@return table
		local function run()
			return n.exec_lua(function()
				local gp = _G.gp
				local cur = gp.baseline(30)
				table.remove(cur, 1)
				local buf = gp.make_buf(cur)
				local rows = gp.rows(buf, gp.base_text(), { { a_start = 1, a_count = 1, b_start = 0, b_count = 0 } }, 3)
				return {
					first_new = rows[1].new,
					first_sign = rows[1].sign,
					second_new = rows[2].new,
					second_sign = rows[2].sign,
				}
			end)
		end

		t.it("removed lnum is clamped to 1", function()
			t.eq(1, run().first_new)
		end)
		t.it("first row is removed", function()
			t.eq("-", run().first_sign)
		end)
		t.it("trailing context lnum", function()
			t.eq(1, run().second_new)
		end)
		t.it("trailing context marker", function()
			t.eq(" ", run().second_sign)
		end)
	end)

	t.describe("pure add (3 lines inserted at b_start=11)", function()
		---@return { new: integer, sign: string }[]
		local function run()
			return n.exec_lua(function()
				local gp = _G.gp
				local cur = gp.baseline(30)
				-- Insert 3 new lines after baseline line 10.
				table.insert(cur, 11, "X")
				table.insert(cur, 12, "Y")
				table.insert(cur, 13, "Z")
				local buf = gp.make_buf(cur)
				local rows = gp.rows(buf, gp.base_text(), { { a_start = 10, a_count = 0, b_start = 11, b_count = 3 } }, 0)
				return vim.tbl_map(function(r)
					return { new = r.new, sign = r.sign }
				end, rows)
			end)
		end

		t.it("yields 3 added rows with consecutive line numbers", function()
			t.eq({ { new = 11, sign = "+" }, { new = 12, sign = "+" }, { new = 13, sign = "+" } }, run())
		end)
	end)

	t.describe("expand_adjacent", function()
		---@param all table[] every hunk
		---@param current table[] the hunks being previewed (elements of `all`; matched by identity in the child)
		---@param adj_gap integer
		---@return integer
		local function expanded(all, current, adj_gap)
			local idx = {}
			for _, c in ipairs(current) do
				idx[#idx + 1] = vim.fn.index(all, c) + 1
			end
			return n.exec_lua(function(a, ci, g)
				package.loaded["beast.libs.git.preview"] = nil
				local expand = require("beast.libs.git.preview")._test.expand_adjacent
				local cur = vim.tbl_map(function(i)
					return a[i]
				end, ci)
				return #expand(a, cur, g)
			end, all, idx, adj_gap)
		end

		local function hunk(start, count)
			return { a_start = start, a_count = count or 1, b_start = start, b_count = count or 1 }
		end

		local h1, h2, h3 = hunk(1), hunk(5), hunk(50)

		t.it("adj_gap=0 keeps a single hunk", function()
			t.eq(1, expanded({ h1, h2, h3 }, { h2 }, 0))
		end)
		t.it("gap 3 does NOT merge with adj_gap=0", function()
			t.eq(1, expanded({ h1, h2, h3 }, { h2 }, 0))
		end)
		t.it("gap 3 merges with adj_gap=5", function()
			t.eq(2, expanded({ h1, h2, h3 }, { h2 }, 5))
		end)
		t.it("a far hunk (gap 44) is still skipped", function()
			t.eq(1, expanded({ h1, h2, h3 }, { h2 }, 0))
		end)
		t.it("touching hunks (gap 0) merge", function()
			local a, b = hunk(10), hunk(11, 2)
			t.eq(2, expanded({ a, b }, { a }, 0))
		end)
		t.it("palette regression: gap 7 with ctx=3 does NOT merge", function()
			local a, b = hunk(76), hunk(84)
			t.eq(1, expanded({ a, b }, { a }, 0))
		end)
		t.it("palette regression: hunk@84-85 + hunk@88-98 (gap 2) does NOT merge", function()
			local a, b = hunk(84, 2), hunk(88, 11)
			t.eq(1, expanded({ a, b }, { a }, 0))
		end)
	end)

	t.describe("trim blank edge context", function()
		t.it("context rows are never blank at the edges", function()
			t.eq(
				{},
				n.exec_lua(function()
					local gp = _G.gp
					local buf = gp.make_buf({ "", "", "MIDDLE", "", "" })
					local base = "x\n\nMIDDLE\n\nx\n"
					local rows = gp.rows(buf, base, { { a_start = 3, a_count = 1, b_start = 3, b_count = 1 } }, 2)
					local blank = {}
					for _, r in ipairs(rows) do
						if r.sign == " " and r.text == "" then
							blank[#blank + 1] = r
						end
					end
					return blank
				end)
			)
		end)
	end)

	t.describe("word spans on paired rows", function()
		-- 2 lines replaced by 3: first two pair up, the extra added line stays soft.
		---@return table<string, { has_spans: boolean, spans: table? }>
		local function run()
			return n.exec_lua(function()
				local gp = _G.gp
				local base = "ctx\nif not confirmed then\nlocal count = old_name(x)\nend\n"
				local cur = { "ctx", "if not confirmed and ok then", "local count = new_name(x)", "extra line here", "end" }
				local buf = gp.make_buf(cur)
				local rows = gp.rows(buf, base, { { a_start = 2, a_count = 2, b_start = 2, b_count = 3 } }, 1)
				local by = {}
				for _, r in ipairs(rows) do
					by[r.sign .. " " .. r.text] = { has_spans = r.spans ~= nil, spans = r.spans }
				end
				return by
			end)
		end

		t.it("context row has no spans", function()
			t.eq(false, run()["  ctx"].has_spans)
		end)
		t.it("removed row 1 pairs (nothing removed)", function()
			t.eq({ has_spans = true, spans = {} }, run()["- if not confirmed then"])
		end)
		t.it("added row 1 marks the phrase", function()
			t.eq({ { 17, 24 } }, run()["+ if not confirmed and ok then"].spans)
		end)
		t.it("removed row 2 marks old word", function()
			t.eq({ { 14, 22 } }, run()["- local count = old_name(x)"].spans)
		end)
		t.it("added row 2 marks new word", function()
			t.eq({ { 14, 22 } }, run()["+ local count = new_name(x)"].spans)
		end)
		t.it("unpaired added row has no spans", function()
			t.eq(false, run()["+ extra line here"].has_spans)
		end)
	end)
end)
