local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Finder list separator rows + multi-chunk right align (docs/dev-specs/finder-colorscheme-swatches.md, Phase 2).

---The half-block edge above ("▄") / below ("▀") the selected item.
---@param line string
local function is_solid(line)
	return line ~= "" and (line:gsub("▄", "") == "" or line:gsub("▀", "") == "")
end

---Create the list view `_G.view` and render `count` items into it.
---@param height integer
---@param count integer
---@param separators? boolean
local function render(height, count, separators)
	n.exec_lua(function(height, count, separators)
		local list = require("beast.libs.finder.ui.list")
		_G.list = list
		_G.format = function(item)
			return {
				{ text = item.text, hl = "Normal" },
				{ text = "", right_align = true, chunks = { { "A", "Normal" }, { "B", "Normal" } } },
			}
		end
		_G.make_items = function(num)
			local items = {}
			for i = 1, num do
				items[i] = { idx = i, score = 0, text = "item" .. i }
			end
			return items
		end
		_G.view = separators and list.create(0, 0, 20, height, nil, true) or list.create(0, 0, 20, height)
		list.render(_G.view, _G.make_items(count), _G.format)
	end, height, count, separators)
end

---@return string[]
local function lines()
	return n.exec_lua(function()
		return vim.api.nvim_buf_get_lines(_G.view.buf, 0, -1, false)
	end)
end

---@return integer
local function visible()
	return n.exec_lua(function()
		return select(2, _G.list.visible_range(_G.view))
	end)
end

t.describe("finder list separators", function()
	t.before_each(F.setup)

	t.after_each(function()
		n.exec_lua(function()
			if _G.view then
				_G.view:close()
			end
		end)
	end)

	t.describe("card style: a slot above every item and below the last", function()
		t.before_each(function()
			render(7, 5, true)
		end)

		t.it("renders 7 rows", function()
			t.eq(7, #lines())
		end)

		t.it("shows 3 items", function()
			t.eq(3, visible())
		end)

		t.it("puts the items on rows 2, 4 and 6", function()
			local l = lines()
			t.eq(true, l[2]:find("item1") ~= nil)
			t.eq(true, l[4]:find("item2") ~= nil)
			t.eq(true, l[6]:find("item3") ~= nil)
		end)

		t.it("draws a solid line above and below the selected item", function()
			local l = lines()
			t.eq(true, is_solid(l[1]))
			t.eq(true, is_solid(l[3]))
		end)

		t.it("dashes the slot between unselected items", function()
			t.eq(true, lines()[5]:find("^%-+$") ~= nil)
		end)

		t.it("leaves the bottom edge blank when not next to the selection", function()
			t.eq("", lines()[7])
		end)

		t.it("snaps a slot row to the item below", function()
			t.eq(
				2,
				n.exec_lua(function()
					return _G.list.item_at_row(_G.view, 3)
				end)
			)
		end)

		t.it("maps an item row to itself", function()
			t.eq(
				3,
				n.exec_lua(function()
					return _G.list.item_at_row(_G.view, 6)
				end)
			)
		end)

		t.describe("after the selection moves down", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.list.set_cursor(_G.view, 2)
				end)
			end)

			t.it("blanks the top edge", function()
				t.eq("", lines()[1])
			end)

			t.it("draws solid lines around item2", function()
				local l = lines()
				t.eq(true, is_solid(l[3]))
				t.eq(true, is_solid(l[5]))
			end)

			t.it("has no dashes next to the selection above", function()
				t.eq(true, not lines()[1]:find("%-"))
			end)

			t.it("carries both chunks in the right-aligned virt_text", function()
				t.eq(
					true,
					n.exec_lua(function()
						local marks = vim.api.nvim_buf_get_extmarks(_G.view.buf, _G.view.ns, 0, -1, { details = true })
						for _, m in ipairs(marks) do
							local vt = m[4].virt_text
							if vt and #vt == 2 and vt[1][1] == "A" and vt[2][1] == "B" then
								return true
							end
						end
						return false
					end)
				)
			end)

			t.it("puts the pointer after the selected item", function()
				t.eq(
					true,
					n.exec_lua(function()
						local marks = vim.api.nvim_buf_get_extmarks(_G.view.buf, _G.view.ns, 0, -1, { details = true })
						for _, m in ipairs(marks) do
							local vt = m[4].virt_text
							if vt and vt[1][1] == " ◀" and m[2] == 3 then
								return true
							end
						end
						return false
					end)
				)
			end)
		end)
	end)

	t.describe("scrolling keeps the cursor visible", function()
		t.before_each(function()
			render(7, 10, true)
			n.exec_lua(function()
				_G.list.set_cursor(_G.view, 10)
			end)
		end)

		t.it("puts item10 last", function()
			t.eq(
				7,
				n.exec_lua(function()
					return _G.view._offset
				end)
			)
		end)

		t.it("shows item10 on the last item row", function()
			t.eq(true, lines()[6]:find("item10") ~= nil)
		end)

		t.it("closes the list with a solid line under item10", function()
			t.eq(true, is_solid(lines()[7]))
		end)

		t.it("selects item10", function()
			t.eq(
				"item10",
				n.exec_lua(function()
					return _G.list.selected(_G.view).text
				end)
			)
		end)

		t.it("wraps to the first item on move", function()
			t.eq(
				"item1",
				n.exec_lua(function()
					_G.list.move(_G.view, 1)
					return _G.list.selected(_G.view).text
				end)
			)
		end)

		t.it("starts the wrapped view at item1", function()
			n.exec_lua(function()
				_G.list.move(_G.view, 1)
			end)
			t.eq(true, lines()[2]:find("item1") ~= nil)
		end)
	end)

	t.describe("even window height and empty list", function()
		t.before_each(function()
			render(6, 5, true)
		end)

		t.it("fits 2 items at height 6", function()
			t.eq(2, visible())
		end)

		t.it("renders nothing selectable for an empty list", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.list.render(_G.view, {}, _G.format)
					return _G.list.selected(_G.view) == nil
				end)
			)
		end)
	end)

	t.describe("default lists (no separators)", function()
		t.before_each(function()
			render(4, 5)
		end)

		t.it("has no separator rows", function()
			t.eq(true, not lines()[2]:find("─"))
		end)

		t.it("shows 4 items", function()
			t.eq(4, visible())
		end)
	end)
end)
