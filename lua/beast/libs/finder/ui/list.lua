local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.ListView : Beast.View.Instance
---@field ns integer
---@field prefix_ns integer namespace for selection prefix extmarks
---@field items Beast.Finder.Item[]
---@field cursor integer 1-based index into items
---@field _format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
---@field _offset integer 0-based index of the first visible item
---@field _win_height integer height of the window (viewport size)
---@overload fun(buf?: integer, win?: integer, ns: integer): Beast.Finder.ListView
local ListView = View:extend(
	---@param obj Beast.Finder.ListView
	function(obj, ns)
		obj.ns = ns
		obj.prefix_ns = vim.api.nvim_create_namespace("")
		obj.items = {}
		obj.cursor = 1
		obj._format_fn = nil
		obj._offset = 0
		obj._win_height = 0
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
	View.win.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,CursorLine:BeastFinderListCursorLine")

	return ListView(buf, win, ns)
end

-- ---------------------------------------------------------------------------
-- Virtual rendering internals
-- ---------------------------------------------------------------------------

--- Compute the visible offset so that `cursor` is within the viewport.
---@param cursor integer 1-based cursor into items
---@param offset integer current 0-based offset
---@param win_height integer viewport rows
---@param total integer total items
---@return integer new_offset 0-based
local function clamp_offset(cursor, offset, win_height, total)
	-- stylua: ignore
	if total <= win_height then return 0 end
	-- Cursor above viewport → scroll up
	if cursor - 1 < offset then
		return cursor - 1
	end
	-- Cursor below viewport → scroll down
	if cursor - 1 >= offset + win_height then
		return cursor - win_height
	end
	-- Clamp offset to valid range
	return math.min(offset, total - win_height)
end

--- Write the visible slice of items to the buffer with extmarks.
---@param view Beast.Finder.ListView
local function render_visible(view)
	-- stylua: ignore
	if not view:is_valid() or not view._format_fn then return end

	local items = view.items
	local total = #items
	local win_height = view._win_height
	local offset = view._offset
	local visible_count = math.min(win_height, total - offset)
	local format_fn = view._format_fn

	local lines = {}
	local all_highlights = {}
	for vi = 1, visible_count do
		local item = items[offset + vi]
		local highlights = format_fn(item)
		all_highlights[vi] = highlights
		local parts = {}
		for _, h in ipairs(highlights) do
			if not h.right_align then
				parts[#parts + 1] = h.text
			end
		end
		lines[vi] = table.concat(parts)
	end

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	-- Apply highlight extmarks and inline prefix via virtual text
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
	local sel_prefix = config.selection_prefix .. " "
	local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))
	local cursor_buf_row = view.cursor - offset -- 1-based buffer row

	for vi, highlights in ipairs(all_highlights) do
		local prefix_text = (vi == cursor_buf_row) and sel_prefix or pad
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, vi - 1, 0, {
			virt_text = { { prefix_text, "BeastFinderListSelectionPrefix" } },
			virt_text_pos = "inline",
		})

		local col = 0
		local right_virt = nil
		for _, h in ipairs(highlights) do
			if h.right_align then
				right_virt = { h.text, h.hl or "BeastFinderNormal" }
			elseif h.hl then
				vim.api.nvim_buf_set_extmark(view.buf, view.ns, vi - 1, col, {
					end_col = col + #h.text,
					hl_group = h.hl,
				})
				col = col + #h.text
			else
				col = col + #h.text
			end
		end
		if right_virt then
			vim.api.nvim_buf_set_extmark(view.buf, view.ns, vi - 1, 0, {
				virt_text = { right_virt },
				virt_text_pos = "right_align",
				hl_mode = "combine",
			})
		end
	end

	-- Set window cursor to the buffer row corresponding to the logical cursor
	if visible_count > 0 then
		local buf_row = math.max(1, math.min(cursor_buf_row, visible_count))
		pcall(vim.api.nvim_win_set_cursor, view.win, { buf_row, 0 })
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param view Beast.Finder.ListView
---@param items Beast.Finder.Item[]
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
function M.render(view, items, format_fn)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.items = items
	view._format_fn = format_fn
	view._win_height = vim.api.nvim_win_get_height(view.win)
	view.cursor = math.min(view.cursor, math.max(1, #items))
	view._offset = clamp_offset(view.cursor, view._offset, view._win_height, #items)
	render_visible(view)
end

---@param view Beast.Finder.ListView
---@param idx integer 1-based
function M.set_cursor(view, idx)
	-- stylua: ignore
	if not view:is_valid() or #view.items == 0 then return end
	view.cursor = math.max(1, math.min(idx, #view.items))
	local new_offset = clamp_offset(view.cursor, view._offset, view._win_height, #view.items)
	if new_offset ~= view._offset then
		view._offset = new_offset
		render_visible(view)
	else
		-- Only update prefix extmarks (cheap)
		local sel_prefix = config.selection_prefix .. " "
		local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))
		local visible_count = math.min(view._win_height, #view.items - view._offset)
		-- Repaint all prefix extmarks (simpler than tracking previous)
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
	local to = math.min(view._offset + view._win_height, #view.items)
	return from, to
end

return M
