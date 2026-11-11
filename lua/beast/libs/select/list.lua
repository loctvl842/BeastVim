local View = require("beast.libs.view")

local PAD = "  "
local EMPTY_TEXT = "No matching items"

---@class Beast.Select.ListView : Beast.View.Instance
---@field ns integer
---@field items any[]
---@field cursor integer 1-based index into items
---@field _format_item fun(item: any): string
---@field _format_tag? fun(item: any): string?
---@field _offset integer 0-based index of the first visible item
---@field _win_height integer current window height in rows (viewport size)
---@field _max_height integer row cap the window never grows past
---@field _footer? string key hints shown on the row below the options
---@overload fun(buf?: integer, win?: integer, ns: integer, max_height: integer): Beast.Select.ListView
local ListView = View:extend(
	---@param obj Beast.Select.ListView
	function(obj, ns, max_height)
		obj.ns = ns
		obj.items = {}
		obj.cursor = 1
		obj._format_item = nil
		obj._format_tag = nil
		obj._offset = 0
		obj._win_height = max_height
		obj._max_height = max_height
	end
)

---@class Beast.Select.UI.List
local M = {}

--- Rows below the options: the footer row and one blank row of padding under it.
local FOOTER_ROWS = 2

--- Rows needed for `count` options: a slot row above each option plus one below the last,
--- then the footer block. The empty state is the message, a gap and the footer block.
---@param count integer
---@return integer
local function rows_for(count)
	return (count == 0 and 2 or 2 * count + 1) + FOOTER_ROWS
end

---@param view Beast.Select.ListView
---@return integer options that fit in the current window
local function capacity(view)
	return math.max(1, math.floor((view._win_height - 1 - FOOTER_ROWS) / 2))
end

---@param win_row integer
---@param win_col integer
---@param win_w integer content width (the blank side borders add one cell each)
---@param max_rows integer initial (and maximum) height in rows
---@param footer? string
---@return Beast.Select.ListView
function M.create(win_row, win_col, win_w, max_rows, footer)
	local buf = View.buf.new("beast-select-list")
	local ns = vim.api.nvim_create_namespace("beast-select-list")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = max_rows,
		row = win_row,
		col = win_col,
		style = "minimal",
		-- Blank side pads only; the footer is a buffer row so it can be padded on both sides.
		border = { "", "", "", " ", "", "", "", " " },
		zindex = 101,
	})

	View.win.wo(win, "cursorline", false)
	View.win.wo(win, "scrolloff", 0)
	View.win.wo(win, "wrap", false)
	View.win.wo(win, "winhl", "Normal:BeastSelectNormal,FloatBorder:BeastSelectBorder")

	local view = ListView(buf, win, ns, max_rows)
	view._footer = footer
	return view
end

--- Clamp the viewport offset so `cursor` stays visible.
---@param view Beast.Select.ListView
---@param cursor integer
---@param offset integer
---@return integer
local function clamp_offset(view, cursor, offset)
	local total = #view.items
	if total == 0 then
		return 0
	end
	local n = capacity(view)
	-- A prior scroll offset can be stale after the item count shrinks (e.g.
	-- filtering a scrolled-down list down to a handful of matches) - cap it
	-- to the current list's valid range before adjusting for cursor visibility.
	offset = math.max(0, math.min(offset, math.max(0, total - n)))

	if cursor - 1 < offset then
		return cursor - 1
	end
	if cursor > offset + n then
		return cursor - n
	end
	return offset
end

--- Resize the window to fit the current item count, capped at `_max_height`.
---@param view Beast.Select.ListView
local function resize_to_fit(view)
	local desired = math.min(rows_for(#view.items), view._max_height)
	if desired ~= view._win_height then
		vim.api.nvim_win_set_config(view.win, { height = desired })
		view._win_height = desired
	end
end

--- Text and highlight of the slot row above option `idx` (or below the last one):
--- solid next to the selection, dashes between options, blank at the outer edges.
---@param view Beast.Select.ListView
---@param idx integer option the slot sits above
---@param first boolean top edge
---@param last boolean bottom edge
---@param width integer
---@return string text, string? hl
local function slot(view, idx, first, last, width)
	if idx == view.cursor or idx - 1 == view.cursor then
		return string.rep("─", width), "BeastSelectListSelectedLine"
	end
	if first or last then
		return "", nil
	end
	return string.rep("-", width), "BeastSelectListSeparator"
end

--- The window is always exactly as tall as its rows, so it must show from the first line;
--- a stale scroll position (left over from a taller list) would hide the top rows.
---@param view Beast.Select.ListView
local function reset_scroll(view)
	vim.api.nvim_win_call(view.win, function()
		vim.fn.winrestview({ topline = 1, lnum = 1 })
	end)
end

--- Right-aligned key hints on buffer row `row0`.
---@param view Beast.Select.ListView
---@param row0 integer
local function draw_footer(view, row0)
	if view._footer then
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, row0, 0, {
			virt_text = { { vim.trim(view._footer) .. PAD, "BeastSelectFooter" } },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		})
	end
end

--- Write the visible slice of options with their slot rows to the buffer.
---@param view Beast.Select.ListView
local function render_visible(view)
	if not view:is_valid() then
		return
	end
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)

	if #view.items == 0 then
		-- message row, a gap, then the footer block
		vim.bo[view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "", "", "", "" })
		vim.bo[view.buf].modifiable = false
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
			virt_text = { { PAD .. EMPTY_TEXT, "BeastSelectListEmpty" } },
			virt_text_pos = "inline",
		})
		draw_footer(view, 2)
		reset_scroll(view)
		return
	end

	local items = view.items
	local width = vim.api.nvim_win_get_width(view.win) - 2 * #PAD
	local visible_count = math.min(capacity(view), #items - view._offset)

	local lines = {} ---@type string[]
	local marks = {} ---@type { row0: integer, col_end: integer, hl: string }[]
	local tags = {} ---@type table<integer, string>
	local cursor_row0 ---@type integer?

	for i = 1, visible_count do
		local idx = view._offset + i
		local text, hl = slot(view, idx, i == 1, false, width)
		lines[#lines + 1] = text
		if hl then
			marks[#marks + 1] = { row0 = #lines - 1, col_end = #text, hl = hl }
		end

		local tag = view._format_tag and view._format_tag(items[idx]) or nil
		-- Keep room for both side pads, the pointer (2) and the tag so none of them get clipped.
		local room = vim.api.nvim_win_get_width(view.win) - 2 * #PAD - 2 - (tag and (vim.fn.strdisplaywidth(tag) + 1) or 0)
		local label = view._format_item(items[idx])
		if vim.fn.strdisplaywidth(label) > room then
			label = vim.fn.strcharpart(label, 0, math.max(0, room - 3)) .. "..."
		end
		lines[#lines + 1] = label
		if idx == view.cursor then
			cursor_row0 = #lines - 1
			marks[#marks + 1] = { row0 = cursor_row0, col_end = #label, hl = "BeastSelectListSelected" }
		end
		if tag then
			tags[#lines - 1] = tag
		end
	end
	local text, hl = slot(view, view._offset + visible_count + 1, false, true, width)
	lines[#lines + 1] = text
	if hl then
		marks[#marks + 1] = { row0 = #lines - 1, col_end = #text, hl = hl }
	end

	-- footer row and its padding row sit right under the trailing slot
	local footer_row0 = #lines
	lines[#lines + 1] = ""
	lines[#lines + 1] = ""

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	draw_footer(view, footer_row0)
	reset_scroll(view)
	for row0 = 0, #lines - 1 do
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, row0, 0, { virt_text = { { PAD } }, virt_text_pos = "inline" })
	end
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, m.row0, 0, { end_col = m.col_end, hl_group = m.hl })
	end
	for row0, tag in pairs(tags) do
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, row0, 0, {
			virt_text = { { tag .. PAD, "BeastSelectListTag" } },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		})
	end
	if cursor_row0 then
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, cursor_row0, 0, {
			virt_text = { { " ◀", "BeastSelectListPointer" } },
			virt_text_pos = "eol",
		})
		pcall(vim.api.nvim_win_set_cursor, view.win, { cursor_row0 + 1, 0 })
	end
end

---@param view Beast.Select.ListView
---@param items any[]
---@param format_item fun(item: any): string
---@param format_tag? fun(item: any): string?
function M.render(view, items, format_item, format_tag)
	if not view:is_valid() then
		return
	end
	view.items = items
	view._format_item = format_item
	view._format_tag = format_tag
	resize_to_fit(view)
	view.cursor = math.min(view.cursor, math.max(1, #items))
	view._offset = clamp_offset(view, view.cursor, view._offset)
	render_visible(view)
end

---@param view Beast.Select.ListView
---@param idx integer 1-based
function M.set_cursor(view, idx)
	if not view:is_valid() or #view.items == 0 then
		return
	end
	view.cursor = math.max(1, math.min(idx, #view.items))
	view._offset = clamp_offset(view, view.cursor, view._offset)
	-- The frame follows the cursor, so every move redraws the visible slice.
	render_visible(view)
end

---@param view Beast.Select.ListView
---@param delta integer positive = down, negative = up
function M.move(view, delta)
	if #view.items == 0 then
		return
	end
	local new_idx = view.cursor + delta
	if new_idx > #view.items then
		new_idx = 1
	elseif new_idx < 1 then
		new_idx = #view.items
	end
	M.set_cursor(view, new_idx)
end

--- Get the item under the cursor, or nil if the list is empty.
---@param view Beast.Select.ListView
---@return any|nil item
---@return integer|nil idx 1-based index into `view.items`
function M.selected(view)
	return view.items[view.cursor], view.items[view.cursor] and view.cursor or nil
end

return M
