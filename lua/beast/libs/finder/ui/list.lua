local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.ListView : Beast.View
---@field ns integer
---@field prefix_ns integer namespace for selection prefix extmarks
---@field items Beast.Finder.Item[]
---@field cursor integer 1-based index into items
---@field selected table<integer, boolean> set of selected item indices
local ListView = View:extend(function(obj, ns)
	obj.ns = ns
	obj.prefix_ns = vim.api.nvim_create_namespace("")
	obj.items = {}
	obj.cursor = 1
	obj.selected = {}
end)

local M = {}

---@param win_row integer top row of the picker layout (below input)
---@param win_col integer left col of the picker layout
---@param win_w integer width available for list
---@param win_h integer height available for list
---@param border? table border chars
---@return Beast.Finder.ListView
function M.create(win_row, win_col, win_w, win_h, border)
	local buf = Buffer.new("beastvim-finder-list")
	local ns = vim.api.nvim_create_namespace("beastvim-finder-list")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = border or { "", "", "", "│", "┘", "─", "╰", "│" },
		zindex = config.zindex,
	})

	Util.wo(win, "cursorline", true)
	Util.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,CursorLine:BeastFinderListCursorLine")

	return ListView(buf, win, ns)
end

---@param view Beast.Finder.ListView
---@param items Beast.Finder.Item[]
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
function M.render(view, items, format_fn)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.items = items
	view.cursor = math.min(view.cursor, math.max(1, #items))

	local lines = {}
	local all_highlights = {}
	for i, item in ipairs(items) do
		local highlights = format_fn(item)
		all_highlights[i] = highlights
		local parts = {}
		for _, h in ipairs(highlights) do
			parts[#parts + 1] = h.text
		end
		lines[#lines + 1] = table.concat(parts)
	end

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	-- Apply highlight extmarks and inline prefix via virtual text
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
	local sel_prefix = config.selection_prefix .. " "
	local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))

	for row, highlights in ipairs(all_highlights) do
		-- Inline virtual text prefix (selected vs padding)
		local prefix_text = (row == view.cursor) and sel_prefix or pad
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, row - 1, 0, {
			virt_text = { { prefix_text, "BeastFinderListSelectionPrefix" } },
			virt_text_pos = "inline",
		})

		local col = 0
		for _, h in ipairs(highlights) do
			if h.hl then
				vim.api.nvim_buf_set_extmark(view.buf, view.ns, row - 1, col, {
					end_col = col + #h.text,
					hl_group = h.hl,
				})
			end
			col = col + #h.text
		end
	end

	M.set_cursor(view, view.cursor)
end

---@param view Beast.Finder.ListView
---@param idx integer 1-based
function M.set_cursor(view, idx)
	-- stylua: ignore
	if not view:is_valid() or #view.items == 0 then return end
	local prev_cursor = view.cursor
	view.cursor = math.max(1, math.min(idx, #view.items))
	vim.api.nvim_win_set_cursor(view.win, { view.cursor, 0 })

	-- Update inline virtual text prefix for old and new cursor rows
	if prev_cursor ~= view.cursor then
		local sel_prefix = config.selection_prefix .. " "
		local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))

		-- Replace prefix on old cursor line
		if prev_cursor >= 1 and prev_cursor <= #view.items then
			vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, prev_cursor - 1, prev_cursor)
			vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, prev_cursor - 1, 0, {
				virt_text = { { pad, "BeastFinderListSelectionPrefix" } },
				virt_text_pos = "inline",
			})
		end

		-- Replace prefix on new cursor line
		vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, view.cursor - 1, view.cursor)
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, view.cursor - 1, 0, {
			virt_text = { { sel_prefix, "BeastFinderListSelectionPrefix" } },
			virt_text_pos = "inline",
		})
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

---@param view Beast.Finder.ListView
function M.toggle_selection(view)
	-- stylua: ignore
	if not view:is_valid() or #view.items == 0 then return end
	local idx = view.items[view.cursor] and view.items[view.cursor].idx
	if not idx then
		return
	end
	if view.selected[idx] then
		view.selected[idx] = nil
	else
		view.selected[idx] = true
	end
end

---@param view Beast.Finder.ListView
---@return Beast.Finder.Item[] selected items, or current item if none selected
function M.get_selected(view)
	if not next(view.selected) then
		local item = view.items[view.cursor]
		return item and { item } or {}
	end
	local result = {}
	for _, item in ipairs(view.items) do
		if view.selected[item.idx] then
			result[#result + 1] = item
		end
	end
	return result
end

---@param view Beast.Finder.ListView
---@return Beast.Finder.Item|nil
function M.selected(view)
	return view.items[view.cursor]
end

return M
