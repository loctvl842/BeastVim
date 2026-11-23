local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Shared diff renderer (word-level spans, row rendering).
t.describe("view diff", function()
	t.before_each(h.clear)

	t.describe("word_spans", function()
		---Texts of the emphasised spans on each side; `old`/`new` are nil when the lines are too different.
		---@param old string
		---@param new string
		---@return { old: string[]?, new: string[]?, old_nil: boolean, new_nil: boolean }
		local function spans(old, new)
			return n.exec_lua(function(o, nw)
				local function texts(line, sp)
					if sp == nil then
						return nil
					end
					local out = {}
					for i, s in ipairs(sp) do
						out[i] = line:sub(s[1] + 1, s[2])
					end
					return out
				end
				local so, sn = require("beast.libs.view.diff").word_spans(o, nw)
				return { old = texts(o, so), new = texts(nw, sn), old_nil = so == nil, new_nil = sn == nil }
			end, old, new)
		end

		t.it("marks only an appended phrase", function()
			local r = spans("    if not confirmed then", "    if not confirmed and vim.g.colors_name ~= original then")
			t.eq({}, r.old)
			t.eq({ "and vim.g.colors_name ~= original " }, r.new)
		end)

		t.it("marks a replaced word on both sides", function()
			local r = spans("local count = old_name(x)", "local count = new_name(x)")
			t.eq({ "old_name" }, r.old)
			t.eq({ "new_name" }, r.new)
		end)

		t.it("returns no spans for identical lines", function()
			local r = spans("same line", "same line")
			t.eq({}, r.old)
			t.eq({}, r.new)
		end)

		t.it("returns nil when the lines are too different", function()
			local r = spans("foo(a, b)", "return bar")
			t.eq(true, r.old_nil)
			t.eq(true, r.new_nil)
		end)

		t.it("marks a punctuation change", function()
			local r = spans("if a == b then", "if a ~= b then")
			t.eq({ "=" }, r.old)
			t.eq({ "~" }, r.new)
		end)

		t.it("marks a whitespace-only change", function()
			local r = spans("local x = 1", "local  x = 1")
			t.eq({ " " }, r.old)
			t.eq({ "  " }, r.new)
		end)

		t.it("handles multibyte text", function()
			local r = spans("msg = 'héllo wörld'", "msg = 'héllo there wörld'")
			t.eq({}, r.old)
			t.eq({ "there " }, r.new)
		end)

		t.it("does not throw on stray bytes", function()
			t.eq(
				true,
				n.exec_lua(function()
					return (pcall(require("beast.libs.view.diff").word_spans, "abc \255 def", "abc \200 deff"))
				end)
			)
		end)

		t.it("returns nil for an over-length line", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					local long = string.rep("a", 1001)
					local so, sn = require("beast.libs.view.diff").word_spans(long, long .. "b")
					return { so == nil, sn == nil }
				end)
			)
		end)
	end)

	t.describe("render", function()
		t.it("renders one number column (git float)", function()
			t.eq(
				{
					width = 6,
					body = { "old", "new", "ctx" },
					g1 = { { text = "  4 ", hl = "BeastViewDiffDeleteSign" }, { text = "- ", hl = "BeastViewDiffDeleteSign" } },
					g2 = { { text = "  4 ", hl = "BeastViewDiffAddSign" }, { text = "+ ", hl = "BeastViewDiffAddSign" } },
					g3 = { { text = "100 ", hl = "LineNr" }, { text = "  ", hl = "LineNr" } },
					hls = { "BeastViewDiffDelete", "BeastViewDiffAdd" },
				},
				n.exec_lua(function()
					local rows = {
						{ new = 4, sign = "-", text = "old" },
						{ new = 4, sign = "+", text = "new" },
						{ new = 100, sign = " ", text = "ctx" },
					}
					local r = require("beast.libs.view.diff").render(rows, { columns = 1 })
					return { width = r.width, body = r.body, g1 = r.gutters[1], g2 = r.gutters[2], g3 = r.gutters[3], hls = r.hls }
				end)
			)
		end)

		t.it("renders two number columns (finder)", function()
			t.eq(
				{ width = 2 * 2 + 2 + 2, g1 = "23    ", g2 = "   23 ", g3 = "24 24 " },
				n.exec_lua(function()
					local rows = {
						{ old = 23, sign = "-", text = "a" },
						{ new = 23, sign = "+", text = "b" },
						{ old = 24, new = 24, sign = " ", text = "c" },
					}
					local r = require("beast.libs.view.diff").render(rows, { columns = 2 })
					return { width = r.width, g1 = r.gutters[1][1].text, g2 = r.gutters[2][1].text, g3 = r.gutters[3][1].text }
				end)
			)
		end)

		t.it("renders plain rows (headers, bands, notes)", function()
			t.eq(
				{
					gutter = { { text = "        ", hl = "BeastViewDiffHead" } },
					hl = "BeastViewDiffHead",
					marks = { { 0, 8, "BeastViewDiffStatAdd" } },
					width = 8,
					blank_width = true,
				},
				n.exec_lua(function()
					local rows = {
						{
							plain = true,
							sign = " ",
							text = "modified  +1 -1",
							hl = "BeastViewDiffHead",
							marks = { { 0, 8, "BeastViewDiffStatAdd" } },
						},
						{ old = 7, new = 7, sign = " ", text = "ctx" },
					}
					local r = require("beast.libs.view.diff").render(rows, { columns = 2 })
					return {
						gutter = r.gutters[1],
						hl = r.hls[1],
						marks = r.marks[1],
						width = r.width,
						-- the blank gutter is as wide as the numbers
						blank_width = #r.gutters[1][1].text == r.width,
					}
				end)
			)
		end)
	end)

	t.describe("pair", function()
		t.it("gives paired rows spans and leaves a surplus row plain", function()
			t.eq(
				{ paired = { true, true }, surplus_plain = true, word_hl = "BeastViewDiffAddWord" },
				n.exec_lua(function()
					local diff = require("beast.libs.view.diff")
					local removed = { { text = "if not confirmed then", sign = "-" }, { text = "unrelated", sign = "-" } }
					local added = { { text = "if not confirmed and ready then", sign = "+" } }
					diff.pair(removed, added)
					local r = diff.render({ added[1] }, { columns = 1 })
					return {
						paired = { removed[1].spans ~= nil, added[1].spans ~= nil },
						surplus_plain = removed[2].spans == nil,
						word_hl = r.spans[1].hl,
					}
				end)
			)
		end)
	end)

	t.describe("gutter_text", function()
		t.it("joins chunks as statuscolumn items", function()
			t.eq(
				"%#A# 1 %#B#+ ",
				n.exec_lua(function()
					return require("beast.libs.view.diff").gutter_text({ { text = " 1 ", hl = "A" }, { text = "+ ", hl = "B" } })
				end)
			)
		end)

		t.it("returns no text for no chunks", function()
			t.eq("", n.exec_lua('return require("beast.libs.view.diff").gutter_text(nil)'))
		end)

		t.it("wrapped rows show only blanks in the mark's color", function()
			t.eq(
				{ "%#B#     ", "%#B#     ", "%#A# 1 %#B#+ " },
				n.exec_lua(function()
					local diff = require("beast.libs.view.diff")
					local chunks = { { text = " 1 ", hl = "A" }, { text = "+ ", hl = "B" } }
					-- continuation row, virtual line, first screen row
					return { diff.gutter_text(chunks, 1), diff.gutter_text(chunks, -1), diff.gutter_text(chunks, 0) }
				end)
			)
		end)
	end)

	t.describe("attach / detach", function()
		t.before_each(function()
			n.exec_lua(function()
				local buf = vim.api.nvim_create_buf(false, true)
				_G.win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 3, style = "minimal" })
				_G.opts = function()
					local w = _G.win
					return { vim.wo[w].number, vim.wo[w].signcolumn, vim.wo[w].statuscolumn, vim.wo[w].numberwidth }
				end
				_G.original = _G.opts()
				_G.diff = require("beast.libs.view.diff")
			end)
		end)

		t.it("attach turns the gutter on", function()
			t.eq(
				{ true, true, 9 },
				n.exec_lua(function()
					_G.diff.attach(_G.win, 9)
					return { vim.wo[_G.win].number, vim.wo[_G.win].statuscolumn ~= "", vim.wo[_G.win].numberwidth }
				end)
			)
		end)

		t.it("attaching again only changes the width", function()
			t.eq(
				6,
				n.exec_lua(function()
					_G.diff.attach(_G.win, 9)
					_G.diff.attach(_G.win, 6)
					return vim.wo[_G.win].numberwidth
				end)
			)
		end)

		t.it("detach gives back what the window had", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.diff.attach(_G.win, 9)
					_G.diff.detach(_G.win)
					return vim.deep_equal(_G.opts(), _G.original)
				end)
			)
		end)

		t.it("a second detach changes nothing", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.diff.attach(_G.win, 9)
					_G.diff.detach(_G.win)
					_G.diff.detach(_G.win)
					return vim.deep_equal(_G.opts(), _G.original)
				end)
			)
		end)
	end)

	t.describe("paint / clear", function()
		---@param action? boolean also clear before counting
		local function marks(action)
			return n.exec_lua(function(clear)
				local diff = require("beast.libs.view.diff")
				local buf = vim.api.nvim_create_buf(false, true)
				local rendered = diff.render(
					{ { new = 1, sign = "-", text = "old" }, { new = 1, sign = "+", text = "new", spans = { { 0, 3 } } } },
					{ columns = 1 }
				)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.body)
				diff.paint(buf, rendered)
				local ns = vim.api.nvim_create_namespace("beast_view_diff")
				if clear then
					diff.clear(buf)
				end
				return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
			end, action)
		end

		t.it("paints a tint per row plus one per changed word", function()
			t.eq(3, marks(false))
		end)

		t.it("clear removes them", function()
			t.eq(0, marks(true))
		end)
	end)
end)
