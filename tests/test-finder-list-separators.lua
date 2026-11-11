-- =========================================================================
-- Test: finder list separator rows + multi-chunk right align
-- (docs/dev-specs/finder-colorscheme-swatches.md, Phase 2)
--
-- Run as: nvim --clean --headless -l tests/test-finder-list-separators.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

local list = require("beast.libs.finder.ui.list")

---@param n integer
local function make_items(n)
	local items = {}
	for i = 1, n do
		items[i] = { idx = i, score = 0, text = "item" .. i }
	end
	return items
end

local function format(item)
	return {
		{ text = item.text, hl = "Normal" },
		{ text = "", right_align = true, chunks = { { "A", "Normal" }, { "B", "Normal" } } },
	}
end

local function is_solid(line)
	return line ~= "" and line:gsub("─", "") == ""
end

local function buf_lines(view)
	return vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
end

io.write("\n--- card style: a slot above every item and below the last ---\n")
do
	local view = list.create(0, 0, 20, 7, nil, true)
	list.render(view, make_items(5), format)
	local lines = buf_lines(view)
	assert_eq("7 rows rendered", #lines, 7)
	assert_eq("3 items visible", select(2, list.visible_range(view)), 3)
	assert_test("row 2 is item1", lines[2]:find("item1") ~= nil)
	assert_test("row 4 is item2", lines[4]:find("item2") ~= nil)
	assert_test("row 6 is item3", lines[6]:find("item3") ~= nil)
	-- cursor on item1: solid line above and below it, dashes between the others, blank bottom edge
	assert_test("slot above selected is solid", is_solid(lines[1]))
	assert_test("slot below selected is solid", is_solid(lines[3]))
	assert_test("slot between unselected items is dashed", lines[5]:find("^%-+$") ~= nil)
	assert_eq("bottom edge is blank when not next to the selection", lines[7], "")
	assert_eq("slot row snaps to the item below", list.item_at_row(view, 3), 2)
	assert_eq("item row maps to itself", list.item_at_row(view, 6), 3)

	list.set_cursor(view, 2)
	lines = buf_lines(view)
	assert_eq("top edge blank once selection moves down", lines[1], "")
	assert_test("solid above item2", is_solid(lines[3]))
	assert_test("solid below item2", is_solid(lines[5]))
	assert_test("dashes no longer next to the selection above", not lines[1]:find("%-"))

	local marks = vim.api.nvim_buf_get_extmarks(view.buf, view.ns, 0, -1, { details = true })
	local multi, pointer = false, false
	for _, m in ipairs(marks) do
		local vt = m[4].virt_text
		if vt and #vt == 2 and vt[1][1] == "A" and vt[2][1] == "B" then
			multi = true
		end
		if vt and vt[1][1] == " ◀" and m[2] == 3 then
			pointer = true
		end
	end
	assert_test("right-aligned virt_text carries both chunks", multi)
	assert_test("pointer sits after the selected item", pointer)
	view:close()
end

io.write("\n--- scrolling keeps the cursor visible ---\n")
do
	local view = list.create(0, 0, 20, 7, nil, true)
	list.render(view, make_items(10), format)
	list.set_cursor(view, 10)
	assert_eq("offset puts item10 last", view._offset, 7)
	local lines = buf_lines(view)
	assert_test("last item row is item10", lines[6]:find("item10") ~= nil)
	assert_test("solid line closes the list under item10", is_solid(lines[7]))
	assert_eq("selected is item10", list.selected(view).text, "item10")
	list.move(view, 1)
	assert_eq("move wraps to the first item", list.selected(view).text, "item1")
	assert_test("wrapped view starts at item1", buf_lines(view)[2]:find("item1") ~= nil)
	view:close()
end

io.write("\n--- even window height and empty list ---\n")
do
	local view = list.create(0, 0, 20, 6, nil, true)
	list.render(view, make_items(5), format)
	assert_eq("height 6 fits 2 items", select(2, list.visible_range(view)), 2)
	list.render(view, {}, format)
	assert_eq("empty list renders nothing selectable", list.selected(view), nil)
	view:close()
end

io.write("\n--- default lists are unchanged (no separators) ---\n")
do
	local view = list.create(0, 0, 20, 4)
	list.render(view, make_items(5), format)
	local lines = buf_lines(view)
	assert_test("no separator rows", not lines[2]:find("─"))
	assert_eq("4 items visible", select(2, list.visible_range(view)), 4)
	view:close()
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
