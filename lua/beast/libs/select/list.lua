local View = require("beast.libs.view")

local BULLET = "● "
local BULLET_PAD = string.rep(" ", vim.fn.strdisplaywidth(BULLET))
local EMPTY_TEXT = "No matching items"

---@class Beast.Select.ListView : Beast.View.Instance
---@field ns integer
---@field prefix_ns integer namespace for the bullet-marker extmarks
---@field items any[]
---@field cursor integer 1-based index into items
---@field _format_item fun(item: any): string
---@field _format_tag? fun(item: any): string?
---@field _offset integer 0-based index of the first visible item
---@field _win_height integer current window height (viewport size)
---@field _max_height integer height cap the window never grows past
---@overload fun(buf?: integer, win?: integer, ns: integer, max_height: integer): Beast.Select.ListView
local ListView = View:extend(
	---@param obj Beast.Select.ListView
	function(obj, ns, max_height)
		obj.ns = ns
		obj.prefix_ns = vim.api.nvim_create_namespace("")
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

---@param win_row integer
---@param win_col integer
---@param win_w integer
---@param win_h integer initial (and maximum) height
---@param border? table border chars
---@param footer? string
---@return Beast.Select.ListView
function M.create(win_row, win_col, win_w, win_h, border, footer)
	local buf = View.buf.new("beast-select-list")
	local ns = vim.api.nvim_create_namespace("beast-select-list")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = border or { "", "", "", "│", "╯", "─", "╰", "│" },
		footer = footer,
		footer_pos = footer and "right" or nil,
		zindex = 101,
	})

	View.win.wo(win, "cursorline", true)
	View.win.wo(win, "scrolloff", 0)
	View.win.wo(win, "wrap", false)
	View.win.wo(
		win,
		"winhl",
		"Normal:BeastSelectNormal,FloatBorder:BeastSelectBorder,FloatFooter:BeastSelectFooter,CursorLine:BeastSelectListCursorLine"
	)

	return ListView(buf, win, ns, win_h)
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
	-- A prior scroll offset can be stale after the item count shrinks (e.g.
	-- filtering a scrolled-down list down to a handful of matches) — cap it
	-- to the current list's valid range before adjusting for cursor visibility.
	local max_offset = math.max(0, total - view._win_height)
	offset = math.max(0, math.min(offset, max_offset))

	if cursor - 1 < offset then
		return cursor - 1
	end
	local last_visible = offset + view._win_height
	if cursor > last_visible then
		return cursor - view._win_height
	end
	return offset
end

--- Resize the window to fit the current item count, capped at `_max_height`
--- and floored at 1 (so the empty state always has a row to render into).
---@param view Beast.Select.ListView
local function resize_to_fit(view)
	local desired = math.max(1, math.min(#view.items, view._max_height))
	if desired ~= view._win_height then
		vim.api.nvim_win_set_config(view.win, { height = desired })
		view._win_height = desired
	end
end

--- Draw the bullet marker on the cursor's row, blank padding elsewhere, so
--- label columns stay aligned regardless of which row is selected.
---@param view Beast.Select.ListView
---@param visible_count integer
local function render_bullets(view, visible_count)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
	local cursor_row0 = view.cursor - view._offset - 1
	for row0 = 0, visible_count - 1 do
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, row0, 0, {
			virt_text = { { row0 == cursor_row0 and BULLET or BULLET_PAD, "BeastSelectListBullet" } },
			virt_text_pos = "inline",
		})
	end
end

--- Write the visible slice of items to the buffer, with the bullet marker
--- and an optional right-aligned dim tag per row.
---@param view Beast.Select.ListView
local function render_visible(view)
	if not view:is_valid() then
		return
	end

	if #view.items == 0 then
		vim.bo[view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "" })
		vim.bo[view.buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
		vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
			virt_text = { { BULLET_PAD .. EMPTY_TEXT, "BeastSelectListEmpty" } },
			virt_text_pos = "inline",
		})
		return
	end

	local items = view.items
	local visible_count = math.min(view._win_height, #items - view._offset)

	local lines = {} ---@type string[]
	local tags = {} ---@type table<integer, string>
	for i = 1, visible_count do
		local item = items[view._offset + i]
		lines[i] = view._format_item(item)
		if view._format_tag then
			local tag = view._format_tag(item)
			if tag then
				tags[i] = tag
			end
		end
	end

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	for i, tag in pairs(tags) do
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, i - 1, 0, {
			virt_text = { { tag, "BeastSelectListTag" } },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		})
	end

	render_bullets(view, visible_count)

	local cursor_row0 = view.cursor - view._offset - 1
	pcall(vim.api.nvim_win_set_cursor, view.win, { cursor_row0 + 1, 0 })
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
	local new_offset = clamp_offset(view, view.cursor, view._offset)
	if new_offset ~= view._offset then
		view._offset = new_offset
		render_visible(view)
	else
		local visible_count = math.min(view._win_height, #view.items - view._offset)
		render_bullets(view, visible_count)
		local cursor_row0 = view.cursor - view._offset - 1
		pcall(vim.api.nvim_win_set_cursor, view.win, { cursor_row0 + 1, 0 })
	end
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
