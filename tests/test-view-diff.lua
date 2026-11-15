-- =========================================================================
-- Test: shared diff renderer (word-level spans, row rendering)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-view-diff.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n")
		io.write("    expected: " .. vim.inspect(expected) .. "\n")
		io.write("    got:      " .. vim.inspect(got) .. "\n")
	end
end

local diff = require("beast.libs.view.diff")
local word_spans = diff.word_spans

---@param line string
---@param spans integer[][]
---@return string[]
local function texts(line, spans)
	local out = {}
	for i, sp in ipairs(spans) do
		out[i] = line:sub(sp[1] + 1, sp[2])
	end
	return out
end

io.write("\n== appended phrase ==\n")
do
	local old = "    if not confirmed then"
	local new = "    if not confirmed and vim.g.colors_name ~= original then"
	local o, n = word_spans(old, new)
	assert_eq("old side has no emphasis", o, {})
	assert_eq("new side marks only the phrase", texts(new, n), { "and vim.g.colors_name ~= original " })
end

io.write("\n== replaced word ==\n")
do
	local old, new = "local count = old_name(x)", "local count = new_name(x)"
	local o, n = word_spans(old, new)
	assert_eq("old word", texts(old, o), { "old_name" })
	assert_eq("new word", texts(new, n), { "new_name" })
end

io.write("\n== identical lines ==\n")
do
	local o, n = word_spans("same line", "same line")
	assert_eq("no spans on old", o, {})
	assert_eq("no spans on new", n, {})
end

io.write("\n== too different ==\n")
do
	local o, n = word_spans("foo(a, b)", "return bar")
	assert_eq("old is nil", o, nil)
	assert_eq("new is nil", n, nil)
end

io.write("\n== punctuation change ==\n")
do
	local old, new = "if a == b then", "if a ~= b then"
	local o, n = word_spans(old, new)
	assert_eq("old operator char", texts(old, o), { "=" })
	assert_eq("new operator char", texts(new, n), { "~" })
end

io.write("\n== whitespace-only change ==\n")
do
	local old, new = "local x = 1", "local  x = 1"
	local o, n = word_spans(old, new)
	assert_eq("old marks the single space", texts(old, o), { " " })
	assert_eq("new marks the double space", texts(new, n), { "  " })
end

io.write("\n== multibyte text ==\n")
do
	local old, new = "msg = 'héllo wörld'", "msg = 'héllo there wörld'"
	local o, n = word_spans(old, new)
	assert_eq("old has no emphasis", o, {})
	assert_eq("new marks the inserted word", texts(new, n), { "there " })
end

io.write("\n== invalid bytes ==\n")
do
	local ok = pcall(word_spans, "abc \255 def", "abc \200 deff")
	assert_eq("does not throw on stray bytes", ok, true)
end

io.write("\n== over-length line ==\n")
do
	local long = string.rep("a", 1001)
	local o, n = word_spans(long, long .. "b")
	assert_eq("old is nil", o, nil)
	assert_eq("new is nil", n, nil)
end

io.write("\n== render, one number column (git float) ==\n")
do
	local rows = {
		{ new = 4, sign = "-", text = "old" },
		{ new = 4, sign = "+", text = "new" },
		{ new = 100, sign = " ", text = "ctx" },
	}
	local r = diff.render(rows, { columns = 1 })
	assert_eq("gutter width fits the widest number", r.width, 6)
	assert_eq("body is the code only", r.body, { "old", "new", "ctx" })
	assert_eq("removed gutter", r.gutters[1], { { text = "  4 ", hl = "BeastViewDiffDeleteSign" }, { text = "- ", hl = "BeastViewDiffDeleteSign" } })
	assert_eq("added gutter", r.gutters[2], { { text = "  4 ", hl = "BeastViewDiffAddSign" }, { text = "+ ", hl = "BeastViewDiffAddSign" } })
	assert_eq("context gutter", r.gutters[3], { { text = "100 ", hl = "LineNr" }, { text = "  ", hl = "LineNr" } })
	assert_eq("line tints", r.hls, { "BeastViewDiffDelete", "BeastViewDiffAdd" })
end

io.write("\n== render, two number columns (finder) ==\n")
do
	local rows = {
		{ old = 23, sign = "-", text = "a" },
		{ new = 23, sign = "+", text = "b" },
		{ old = 24, new = 24, sign = " ", text = "c" },
	}
	local r = diff.render(rows, { columns = 2 })
	assert_eq("width = old + new + mark", r.width, 2 * 2 + 2 + 2)
	assert_eq("removed row shows only the old number", r.gutters[1][1].text, "23    ")
	assert_eq("added row shows only the new number", r.gutters[2][1].text, "   23 ")
	assert_eq("context row shows both", r.gutters[3][1].text, "24 24 ")
end

io.write("\n== pair ==\n")
do
	local removed = { { text = "if not confirmed then", sign = "-" }, { text = "unrelated", sign = "-" } }
	local added = { { text = "if not confirmed and ready then", sign = "+" } }
	diff.pair(removed, added)
	assert_eq("paired rows get spans", { removed[1].spans ~= nil, added[1].spans ~= nil }, { true, true })
	assert_eq("a surplus row stays plain", removed[2].spans, nil)
	local r = diff.render({ added[1] }, { columns = 1 })
	assert_eq("spans use the word group of the row", r.spans[1].hl, "BeastViewDiffAddWord")
end

io.write("\n== gutter text ==\n")
do
	local chunks = { { text = " 1 ", hl = "A" }, { text = "+ ", hl = "B" } }
	assert_eq("chunks join as statuscolumn items", diff.gutter_text(chunks), "%#A# 1 %#B#+ ")
	assert_eq("no chunks, no text", diff.gutter_text(nil), "")
end

io.write("\n== plain rows (headers, bands, notes) ==\n")
do
	local rows = {
		{ plain = true, sign = " ", text = "modified  +1 -1", hl = "BeastViewDiffHead", marks = { { 0, 8, "BeastViewDiffStatAdd" } } },
		{ old = 7, new = 7, sign = " ", text = "ctx" },
	}
	local r = diff.render(rows, { columns = 2 })
	assert_eq("a plain row has a blank gutter as wide as the numbers", r.gutters[1], { { text = string.rep(" ", r.width), hl = "BeastViewDiffHead" } })
	assert_eq("a plain row is tinted by its own group", r.hls[1], "BeastViewDiffHead")
	assert_eq("its extra highlights are kept", r.marks[1], { { 0, 8, "BeastViewDiffStatAdd" } })
	assert_eq("it does not count for the number width", r.width, 8)
end

io.write("\n== wrapped rows ==\n")
do
	local chunks = { { text = " 1 ", hl = "A" }, { text = "+ ", hl = "B" } }
	assert_eq("a continuation row shows only blanks in the mark's color", diff.gutter_text(chunks, 1), "%#B#     ")
	assert_eq("a virtual line shows blanks too", diff.gutter_text(chunks, -1), "%#B#     ")
	assert_eq("the first screen row of a line has its numbers", diff.gutter_text(chunks, 0), "%#A# 1 %#B#+ ")
end

io.write("\n== attach / detach ==\n")
do
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 3, style = "minimal" })
	local function opts()
		return { vim.wo[win].number, vim.wo[win].signcolumn, vim.wo[win].statuscolumn, vim.wo[win].numberwidth }
	end
	local original = opts()
	diff.attach(win, 9)
	assert_eq("attach turns the gutter on", { vim.wo[win].number, vim.wo[win].statuscolumn ~= "", vim.wo[win].numberwidth }, { true, true, 9 })
	diff.attach(win, 6)
	assert_eq("attaching again only changes the width", vim.wo[win].numberwidth, 6)
	diff.detach(win)
	assert_eq("detach gives back what the window had", opts(), original)
	diff.detach(win)
	assert_eq("a second detach changes nothing", opts(), original)
	vim.api.nvim_win_close(win, true)
end

io.write("\n== paint / clear ==\n")
do
	local buf = vim.api.nvim_create_buf(false, true)
	local rendered = diff.render(
		{ { new = 1, sign = "-", text = "old" }, { new = 1, sign = "+", text = "new", spans = { { 0, 3 } } } },
		{ columns = 1 }
	)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.body)
	diff.paint(buf, rendered)
	local ns = vim.api.nvim_create_namespace("beast_view_diff")
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
	assert_eq("a tint per row plus one per changed word", #marks, 3)
	diff.clear(buf)
	assert_eq("clear removes them", #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0)
end

io.write("\n== Summary ==\n")
io.write(("  Passed: %d\n  Failed: %d\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
