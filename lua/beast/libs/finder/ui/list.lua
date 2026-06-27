local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.ListView : Beast.View.Instance
---@field ns integer
---@field prefix_ns integer namespace for selection prefix extmarks
---@field items Beast.Finder.Item[]
---@field cursor integer 1-based index into items
---@field _format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
---@field _header_fn? fun(item: Beast.Finder.Item): Beast.Finder.Highlight[] optional group header (grouped sources)
---@field _offset integer 0-based index of the first visible item
---@field _win_height integer height of the window (viewport size)
---@field _item_to_row table<integer, integer> visible item index -> 1-based buffer row of its match line
---@field _row_to_item table<integer, integer> 1-based buffer row -> item index (match rows only)
---@field _visible_last integer last visible item index
---@overload fun(buf?: integer, win?: integer, ns: integer): Beast.Finder.ListView
local ListView = View:extend(
	---@param obj Beast.Finder.ListView
	function(obj, ns)
		obj.ns = ns
		obj.prefix_ns = vim.api.nvim_create_namespace("")
		obj.items = {}
		obj.cursor = 1
		obj._format_fn = nil
		obj._header_fn = nil
		obj._offset = 0
		obj._win_height = 0
		obj._item_to_row = {}
		obj._row_to_item = {}
		obj._visible_last = 0
	end
)

---@class Beast.Finder.UI.List
local M = {}

---@param win_row integer top row of the picker layout (below input)
---@param win_col integer left col of the picker layout
---@param win_w integer width available for list
---@param win_h integer height available for list
---@param border? table border chars
---@return Beast.Finder.ListView
function M.create(win_row, win_col, win_w, win_h, border)
	local buf = View.buf.new("beast-finder-list")
	local ns = vim.api.nvim_create_namespace("beast-finder-list")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = border or { "", "", "", "│", "┘", "─", "╰", "│" },
		zindex = 101,
	})

	View.win.wo(win, "cursorline", true)
	View.win.wo(win, "scrolloff", 0)
	View.win.wo(win, "wrap", false)
	View.win.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,CursorLine:BeastFinderListCursorLine")

	return ListView(buf, win, ns)
end

-- ---------------------------------------------------------------------------
-- Virtual rendering internals
-- ---------------------------------------------------------------------------

--- How many buffer rows item `idx` occupies: 1 for the match line, plus 1 for a
--- group header when grouping is active and this item starts a new file group.
---@param view Beast.Finder.ListView
---@param idx integer 1-based item index
---@return integer 1 or 2
local function item_cost(view, idx)
	if not view._header_fn then
		return 1
	end
	local items = view.items
	if idx == 1 or items[idx].file ~= items[idx - 1].file then
		return 2
	end
	return 1
end

--- Last item index visible when the viewport starts at `offset` (0-based),
--- accounting for header rows.
---@param view Beast.Finder.ListView
---@param offset integer
---@return integer
local function last_visible(view, offset)
	local total = #view.items
	local rows, idx = 0, offset + 1
	while idx <= total do
		local cost = item_cost(view, idx)
		if rows + cost > view._win_height and rows > 0 then
			break
		end
		rows = rows + cost
		idx = idx + 1
	end
	return math.max(offset, idx - 1)
end

--- Smallest offset (0-based) such that `cursor` is the last fully-visible item.
---@param view Beast.Finder.ListView
---@param cursor integer
---@return integer
local function offset_for_cursor(view, cursor)
	local rows, idx = 0, cursor
	while idx >= 1 do
		local cost = item_cost(view, idx)
		if rows + cost > view._win_height then
			break
		end
		rows = rows + cost
		idx = idx - 1
	end
	return math.min(idx, cursor - 1)
end

--- Compute the visible offset so that `cursor` is within the viewport.
---@param view Beast.Finder.ListView
---@param cursor integer 1-based cursor into items
---@param offset integer current 0-based offset
---@return integer new_offset 0-based
local function clamp_offset(view, cursor, offset)
	-- stylua: ignore
	if #view.items == 0 then return 0 end
	-- Cursor above viewport → scroll up so cursor is at the top.
	if cursor - 1 < offset then
		return cursor - 1
	end
	-- Cursor below viewport → scroll down so cursor is at the bottom.
	if cursor > last_visible(view, offset) then
		return offset_for_cursor(view, cursor)
	end
	return offset
end

--- Concatenate the non-right-aligned text parts of a highlight list.
---@param highlights Beast.Finder.Highlight[]
---@return string
local function line_text(highlights)
	local parts = {}
	for _, h in ipairs(highlights) do
		if not h.right_align then
			parts[#parts + 1] = h.text
		end
	end
	return table.concat(parts)
end

--- Apply per-row highlight + right-align extmarks for a rendered line.
---@param view Beast.Finder.ListView
---@param row0 integer 0-based buffer row
---@param highlights Beast.Finder.Highlight[]
local function apply_row_highlights(view, row0, highlights)
	local col = 0
	local right_virt = nil
	for _, h in ipairs(highlights) do
		if h.right_align then
			right_virt = { h.text, h.hl or "BeastFinderNormal" }
		elseif h.hl then
			vim.api.nvim_buf_set_extmark(view.buf, view.ns, row0, col, {
				end_col = col + #h.text,
				hl_group = h.hl,
			})
			col = col + #h.text
		else
			col = col + #h.text
		end
	end
	if right_virt then
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, row0, 0, {
			virt_text = { right_virt },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		})
	end
end

--- Write the visible slice of items to the buffer with extmarks. When grouping
--- is active, a file-group header line is inserted above the first match of each
--- file; the logical cursor always targets the match line, never a header.
---@param view Beast.Finder.ListView
local function render_visible(view)
	-- stylua: ignore
	if not view:is_valid() or not view._format_fn then return end

	local items = view.items
	local total = #items
	local win_height = view._win_height
	local offset = view._offset
	local format_fn = view._format_fn
	local header_fn = view._header_fn

	local lines = {} ---@type string[]
	local row_hl = {} ---@type table<integer, Beast.Finder.Highlight[]> 1-based row -> highlights
	local row_is_match = {} ---@type table<integer, boolean>
	local item_to_row = {} ---@type table<integer, integer>
	local row_to_item = {} ---@type table<integer, integer>

	local rows = 0
	local idx = offset + 1
	while idx <= total and rows < win_height do
		local needs_header = header_fn ~= nil and (idx == 1 or items[idx].file ~= items[idx - 1].file)
		local cost = needs_header and 2 or 1
		if rows + cost > win_height and rows > 0 then
			break
		end
		if needs_header and header_fn then
			rows = rows + 1
			local h = header_fn(items[idx])
			row_hl[rows] = h
			row_is_match[rows] = false
			lines[rows] = line_text(h)
		end
		rows = rows + 1
		local hl = format_fn(items[idx])
		row_hl[rows] = hl
		row_is_match[rows] = true
		item_to_row[idx] = rows
		row_to_item[rows] = idx
		lines[rows] = line_text(hl)
		idx = idx + 1
	end

	view._item_to_row = item_to_row
	view._row_to_item = row_to_item
	view._visible_last = idx - 1

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)

	local sel_prefix = config.selection_prefix .. " "
	local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))
	local cursor_row = item_to_row[view.cursor]

	for r = 1, rows do
		-- Selection prefix on match rows (selected on the cursor's match line);
		-- headers get the pad so their text aligns with the match column.
		local prefix_text = pad
		if row_is_match[r] and r == cursor_row then
			prefix_text = sel_prefix
		end
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, r - 1, 0, {
			virt_text = { { prefix_text, "BeastFinderListSelectionPrefix" } },
			virt_text_pos = "inline",
		})
		apply_row_highlights(view, r - 1, row_hl[r])
	end

	if cursor_row then
		pcall(vim.api.nvim_win_set_cursor, view.win, { cursor_row, 0 })
	elseif rows > 0 then
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param view Beast.Finder.ListView
---@param items Beast.Finder.Item[]
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
---@param header_fn? fun(item: Beast.Finder.Item): Beast.Finder.Highlight[] group header (grouped sources)
function M.render(view, items, format_fn, header_fn)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.items = items
	view._format_fn = format_fn
	view._header_fn = header_fn
	view._win_height = vim.api.nvim_win_get_height(view.win)
	view.cursor = math.min(view.cursor, math.max(1, #items))
	view._offset = clamp_offset(view, view.cursor, view._offset)
	render_visible(view)
end

---@param view Beast.Finder.ListView
---@param idx integer 1-based
function M.set_cursor(view, idx)
	-- stylua: ignore
	if not view:is_valid() or #view.items == 0 then return end
	view.cursor = math.max(1, math.min(idx, #view.items))
	local new_offset = clamp_offset(view, view.cursor, view._offset)
	if new_offset ~= view._offset or view._header_fn then
		-- Grouped lists have a variable item↔row mapping, so re-render to keep
		-- headers and the cursor row correct. Flat lists can take the cheap path.
		view._offset = new_offset
		render_visible(view)
	else
		-- Only update prefix extmarks (cheap)
		local sel_prefix = config.selection_prefix .. " "
		local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))
		local visible_count = math.min(view._win_height, #view.items - view._offset)
		vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
		local cursor_buf_row = view.cursor - view._offset
		for vi = 1, visible_count do
			local prefix_text = (vi == cursor_buf_row) and sel_prefix or pad
			vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, vi - 1, 0, {
				virt_text = { { prefix_text, "BeastFinderListSelectionPrefix" } },
				virt_text_pos = "inline",
			})
		end
		pcall(vim.api.nvim_win_set_cursor, view.win, { math.max(1, cursor_buf_row), 0 })
	end
end

---@param view Beast.Finder.ListView
---@param delta integer positive = down, negative = up
function M.move(view, delta)
	-- stylua: ignore
	if #view.items == 0 then return end
	local new_idx = view.cursor + delta
	-- Cycle: past bottom → top, past top → bottom
	if new_idx > #view.items then
		new_idx = 1
	elseif new_idx < 1 then
		new_idx = #view.items
	end
	M.set_cursor(view, new_idx)
end

--- Get the selected item under the cursor, or nil if no items
---@param view Beast.Finder.ListView
---@return Beast.Finder.Item|nil
function M.selected(view)
	return view.items[view.cursor]
end

--- Return the 1-based visible range (from, to) into view.items
---@param view Beast.Finder.ListView
---@return integer from 1-based first visible item index
---@return integer to 1-based last visible item index
function M.visible_range(view)
	local from = view._offset + 1
	local to = view._visible_last
	if to == nil or to < from then
		to = last_visible(view, view._offset)
	end
	return from, math.min(to, #view.items)
end

--- Map a 1-based buffer row to the item index it represents. Match rows map
--- directly; a header row maps to the match directly below it (its file's first
--- match). Returns nil if the row maps to no item.
---@param view Beast.Finder.ListView
---@param buf_row integer 1-based buffer row
---@return integer|nil item_idx
function M.item_at_row(view, buf_row)
	if not view._header_fn then
		local idx = view._offset + buf_row
		if idx >= 1 and idx <= #view.items then
			return idx
		end
		return nil
	end
	local map = view._row_to_item or {}
	if map[buf_row] then
		return map[buf_row]
	end
	-- Header row: snap to the match line just below it.
	if map[buf_row + 1] then
		return map[buf_row + 1]
	end
	return nil
end

return M
