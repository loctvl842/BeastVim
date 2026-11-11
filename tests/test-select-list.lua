-- =========================================================================
-- Test: select list panel - slot rows, framed selection, scrolling, empty state
-- (docs/dev-specs/select-card-style.md, Phase 1)
--
-- Run as: nvim --clean --headless -l tests/test-select-list.lua
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

local list = require("beast.libs.select.list")

local function items(n)
	local t = {}
	for i = 1, n do
		t[i] = "item" .. i
	end
	return t
end

local function ident(x)
	return x
end

local function lines(view)
	return vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
end

-- the half-block edge above ("▄") / below ("▀") the selected option
local function is_solid(line)
	return line ~= "" and (line:gsub("▄", "") == "" or line:gsub("▀", "") == "")
end

local function is_dashed(line)
	return line ~= "" and line:gsub("%-", "") == ""
end

io.write("\n--- window height follows the option count (2n + 1 rows + footer block) ---\n")
do
	local view = list.create(0, 0, 20, 13, " Confirm enter ")
	list.render(view, items(3), ident)
	assert_eq("3 options use 9 rows", vim.api.nvim_win_get_height(view.win), 9)
	list.render(view, items(1), ident)
	assert_eq("1 option uses 5 rows", vim.api.nvim_win_get_height(view.win), 5)
	list.render(view, items(20), ident)
	assert_eq("capped at the max height", vim.api.nvim_win_get_height(view.win), 13)
	view:close()
end

io.write("\n--- selection is framed by solid lines, dashes elsewhere ---\n")
do
	local view = list.create(0, 0, 20, 13, " Confirm enter ")
	list.render(view, items(4), function(x)
		return x
	end, function(x)
		return x == "item2" and "tag" or nil
	end)
	local l = lines(view)
	assert_eq("11 rows", #l, 11)
	assert_eq("top edge row above the selection is blank-or-solid: solid", is_solid(l[1]), true)
	assert_eq("row 2 is item1", l[2], "item1")
	assert_eq("solid below the selection", is_solid(l[3]), true)
	assert_eq("row 4 is item2", l[4], "item2")
	assert_eq("dashes between unselected options", is_dashed(l[5]), true)
	assert_eq("bottom edge is blank", l[9], "")
	assert_eq("footer padding row is blank", l[11], "")

	list.move(view, 1)
	l = lines(view)
	assert_eq("top edge goes blank once the selection moves", l[1], "")
	assert_eq("solid above item2", is_solid(l[3]), true)
	assert_eq("solid below item2", is_solid(l[5]), true)
	assert_eq("selected is item2", list.selected(view), "item2")

	local pointer, tag = false, false
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(view.buf, view.ns, 0, -1, { details = true })) do
		local vt = m[4].virt_text
		if vt and vt[1][1] == " ◀" and m[2] == 3 then
			pointer = true
		end
		if vt and vt[1][1]:find("tag") and m[2] == 3 then
			tag = true
		end
	end
	assert_test("pointer follows the selected row", pointer)
	assert_test("tag is drawn on its option's row", tag)
	view:close()
end

io.write("\n--- scrolling and wrap-around ---\n")
do
	local view = list.create(0, 0, 20, 9, " Confirm enter ") -- fits 3 options
	list.render(view, items(10), ident)
	assert_eq("3 options visible", #lines(view), 9)
	list.set_cursor(view, 10)
	local l = lines(view)
	assert_eq("last option row is item10", l[6], "item10")
	assert_eq("solid line closes the list under item10", is_solid(l[7]), true)
	list.move(view, 1)
	assert_eq("wraps to the first option", list.selected(view), "item1")
	assert_eq("wrapped view starts at item1", lines(view)[2], "item1")
	list.move(view, -1)
	assert_eq("wraps back to the last option", select(2, list.selected(view)), 10)
	view:close()
end

io.write("\n--- long labels are shortened so the pointer and tag fit ---\n")
do
	local view = list.create(0, 0, 30, 7, " Confirm enter ")
	list.render(view, { string.rep("x", 60) }, ident, function()
		return "tag"
	end)
	local label = lines(view)[2]
	assert_test("label ends with ...", label:sub(-3) == "...")
	assert_test("label leaves room for pad, tag and pointer", vim.fn.strdisplaywidth(label) <= 30 - 2 * 2 - 2 - (3 + 1))
	view:close()
end

io.write("\n--- empty state ---\n")
do
	local view = list.create(0, 0, 20, 13, " Confirm enter ")
	list.render(view, {}, ident)
	assert_eq("message, gap, footer, padding", vim.api.nvim_win_get_height(view.win), 4)
	assert_eq("nothing selectable", list.selected(view), nil)
	local msg, footer = false, false
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(view.buf, view.ns, 0, -1, { details = true })) do
		local vt = m[4].virt_text
		if vt and vt[1][1]:find("No matching items") and m[2] == 0 then
			msg = true
		end
		if vt and vt[1][1]:find("Confirm enter") and m[2] == 2 then
			footer = true
		end
	end
	assert_eq("first buffer line is the top visible line", vim.fn.getwininfo(view.win)[1].topline, 1)
	assert_test("empty message is drawn on the first row", msg)
	assert_test("footer is drawn on the third row, one gap row below the message", footer)
	view:close()
end

io.write("\n--- shrinking from a scrolled long list keeps the top row visible ---\n")
do
	local view = list.create(0, 0, 20, 13, " Confirm enter ")
	list.render(view, items(20), ident)
	list.set_cursor(view, 20)
	list.render(view, {}, ident)
	assert_eq("topline reset after shrinking to the empty state", vim.fn.getwininfo(view.win)[1].topline, 1)
	list.render(view, items(2), ident)
	assert_eq("topline reset when options return", vim.fn.getwininfo(view.win)[1].topline, 1)
	view:close()
end

io.write("\n--- footer block: one row under the trailing slot, then a padding row ---\n")
do
	local view = list.create(0, 0, 20, 13, " Confirm enter ")
	list.render(view, items(2), ident)
	local l = lines(view)
	assert_eq("2 options: 5 slot/option rows + footer + padding", #l, 7)
	local footer_row
	for _, m in ipairs(vim.api.nvim_buf_get_extmarks(view.buf, view.ns, 0, -1, { details = true })) do
		local vt = m[4].virt_text
		if vt and vt[1][1]:find("Confirm enter") then
			footer_row = m[2]
		end
	end
	assert_eq("footer sits right under the trailing slot", footer_row, 5)
	assert_eq("padding row below the footer is the last row", l[7], "")
	view:close()
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
