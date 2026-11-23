local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Select list panel: slot rows, framed selection, scrolling, empty state
-- (docs/dev-specs/select-card-style.md, Phase 1).
t.describe("select list", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.list = require("beast.libs.select.list")
			_G.items = function(count)
				local out = {}
				for i = 1, count do
					out[i] = "item" .. i
				end
				return out
			end
			_G.ident = function(x)
				return x
			end
			_G.lines = function(view)
				return vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
			end
			-- the half-block edge above ("▄") / below ("▀") the selected option
			_G.is_solid = function(line)
				return line ~= "" and (line:gsub("▄", "") == "" or line:gsub("▀", "") == "")
			end
			_G.is_dashed = function(line)
				return line ~= "" and line:gsub("%-", "") == ""
			end
			_G.new_view = function(width, height)
				_G.view = _G.list.create(0, 0, width or 20, height or 13, " Confirm enter ")
				return _G.view
			end
			---Virt-text extmarks of the view as { row, text }.
			_G.virt_marks = function(view)
				local out = {}
				for _, m in ipairs(vim.api.nvim_buf_get_extmarks(view.buf, view.ns, 0, -1, { details = true })) do
					local vt = m[4].virt_text
					if vt then
						out[#out + 1] = { row = m[2], text = vt[1][1] }
					end
				end
				return out
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua("if _G.view then _G.view:close() end")
	end)

	t.describe("window height (2n + 1 rows + footer block)", function()
		---@param count integer
		local function height_for(count)
			return n.exec_lua(function(c)
				_G.new_view()
				_G.list.render(_G.view, _G.items(c), _G.ident)
				return vim.api.nvim_win_get_height(_G.view.win)
			end, count)
		end

		t.it("3 options use 9 rows", function()
			t.eq(9, height_for(3))
		end)

		t.it("1 option uses 5 rows", function()
			t.eq(5, height_for(1))
		end)

		t.it("is capped at the max height", function()
			t.eq(13, height_for(20))
		end)
	end)

	t.describe("selection framing", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.new_view()
				_G.list.render(_G.view, _G.items(4), _G.ident, function(x)
					return x == "item2" and "tag" or nil
				end)
			end)
		end)

		t.it("draws solid lines around the first selection and dashes between others", function()
			t.eq(
				{
					count = 11,
					top_solid = true,
					row2 = "item1",
					below_solid = true,
					row4 = "item2",
					dashed = true,
					bottom = "",
					footer_pad = "",
				},
				n.exec_lua(function()
					local l = _G.lines(_G.view)
					return {
						count = #l,
						top_solid = _G.is_solid(l[1]),
						row2 = l[2],
						below_solid = _G.is_solid(l[3]),
						row4 = l[4],
						dashed = _G.is_dashed(l[5]),
						bottom = l[9],
						footer_pad = l[11],
					}
				end)
			)
		end)

		t.it("moves the frame when the selection moves", function()
			t.eq(
				{ top = "", above = true, below = true, selected = "item2" },
				n.exec_lua(function()
					_G.list.move(_G.view, 1)
					local l = _G.lines(_G.view)
					return {
						top = l[1],
						above = _G.is_solid(l[3]),
						below = _G.is_solid(l[5]),
						selected = _G.list.selected(_G.view),
					}
				end)
			)
		end)

		t.it("draws the pointer and tag on the selected row", function()
			t.eq(
				{ pointer = true, tag = true },
				n.exec_lua(function()
					_G.list.move(_G.view, 1)
					local pointer, tag = false, false
					for _, m in ipairs(_G.virt_marks(_G.view)) do
						if m.text == " ◀" and m.row == 3 then
							pointer = true
						end
						if m.text:find("tag") and m.row == 3 then
							tag = true
						end
					end
					return { pointer = pointer, tag = tag }
				end)
			)
		end)
	end)

	t.describe("scrolling and wrap-around", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.new_view(20, 9) -- fits 3 options
				_G.list.render(_G.view, _G.items(10), _G.ident)
			end)
		end)

		t.it("shows 3 options", function()
			t.eq(9, n.exec_lua("return #_G.lines(_G.view)"))
		end)

		t.it("scrolls to the last option and closes with a solid line", function()
			t.eq(
				{ "item10", true },
				n.exec_lua(function()
					_G.list.set_cursor(_G.view, 10)
					local l = _G.lines(_G.view)
					return { l[6], _G.is_solid(l[7]) }
				end)
			)
		end)

		t.it("wraps forward to the first option", function()
			t.eq(
				{ "item1", "item1" },
				n.exec_lua(function()
					_G.list.set_cursor(_G.view, 10)
					_G.list.move(_G.view, 1)
					return { _G.list.selected(_G.view), _G.lines(_G.view)[2] }
				end)
			)
		end)

		t.it("wraps back to the last option", function()
			t.eq(
				10,
				n.exec_lua(function()
					_G.list.move(_G.view, -1)
					return select(2, _G.list.selected(_G.view))
				end)
			)
		end)
	end)

	t.it("shortens long labels so the pointer and tag fit", function()
		t.eq(
			{ ellipsis = true, fits = true },
			n.exec_lua(function()
				local view = _G.new_view(30, 7)
				_G.list.render(view, { string.rep("x", 60) }, _G.ident, function()
					return "tag"
				end)
				local label = _G.lines(view)[2]
				return {
					ellipsis = label:sub(-3) == "...",
					fits = vim.fn.strdisplaywidth(label) <= 30 - 2 * 2 - 2 - (3 + 1),
				}
			end)
		)
	end)

	t.describe("empty state", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.new_view()
				_G.list.render(_G.view, {}, _G.ident)
			end)
		end)

		t.it("uses message, gap, footer and padding rows", function()
			t.eq(4, n.exec_lua("return vim.api.nvim_win_get_height(_G.view.win)"))
		end)

		t.it("has nothing selectable", function()
			t.eq(true, n.exec_lua("return _G.list.selected(_G.view) == nil"))
		end)

		t.it("shows the first buffer line as the top line", function()
			t.eq(1, n.exec_lua("return vim.fn.getwininfo(_G.view.win)[1].topline"))
		end)

		t.it("draws the message on the first row and the footer one gap row below", function()
			t.eq(
				{ msg = true, footer = true },
				n.exec_lua(function()
					local msg, footer = false, false
					for _, m in ipairs(_G.virt_marks(_G.view)) do
						if m.text:find("No matching items") and m.row == 0 then
							msg = true
						end
						if m.text:find("Confirm enter") and m.row == 2 then
							footer = true
						end
					end
					return { msg = msg, footer = footer }
				end)
			)
		end)
	end)

	t.it("keeps the top row visible when shrinking from a scrolled long list", function()
		t.eq(
			{ 1, 1 },
			n.exec_lua(function()
				local view = _G.new_view()
				_G.list.render(view, _G.items(20), _G.ident)
				_G.list.set_cursor(view, 20)
				_G.list.render(view, {}, _G.ident)
				local after_empty = vim.fn.getwininfo(view.win)[1].topline
				_G.list.render(view, _G.items(2), _G.ident)
				return { after_empty, vim.fn.getwininfo(view.win)[1].topline }
			end)
		)
	end)

	t.describe("footer block", function()
		t.it("sits one row under the trailing slot, then a padding row", function()
			t.eq(
				{ count = 7, footer_row = 5, last = "" },
				n.exec_lua(function()
					local view = _G.new_view()
					_G.list.render(view, _G.items(2), _G.ident)
					local l = _G.lines(view)
					local footer_row
					for _, m in ipairs(_G.virt_marks(view)) do
						if m.text:find("Confirm enter") then
							footer_row = m.row
						end
					end
					return { count = #l, footer_row = footer_row, last = l[7] }
				end)
			)
		end)
	end)
end)
