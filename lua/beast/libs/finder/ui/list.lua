local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.ListView : Beast.View
---@field ns integer
---@field items Beast.Finder.Item[]
---@field cursor integer 1-based index into items
local ListView = View:extend(function(obj, ns)
	obj.ns = ns
	obj.items = {}
	obj.cursor = 1
end)

local M = {}

---@param win_row integer top row of the picker layout (below input)
---@param win_col integer left col of the picker layout
---@param win_w integer width available for list
---@param win_h integer height available for list
---@return Beast.Finder.ListView
function M.create(win_row, win_col, win_w, win_h)
	local buf = Util.create_scratch_buf("beastvim-finder-list")
	local ns = vim.api.nvim_create_namespace("beastvim-finder-list")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = { "", "", "", "│", "┘", "─", "╰", "│" },
		zindex = config.zindex,
	})

	Util.wo(win, "cursorline", true)
	Util.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,CursorLine:BeastFinderSelected")

	return ListView(buf, win, ns)
end

---@class Beast.Finder.Highlight
---@field text string
---@field hl string?

---@param view Beast.Finder.ListView
---@param items Beast.Finder.Item[]
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
function M.render(view, items, format_fn)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.items = items
	view.cursor = math.min(view.cursor, math.max(1, #items))

	local sel_prefix = config.selection_prefix
	local pad = string.rep(" ", #sel_prefix)

	local lines = {}
	for i, item in ipairs(items) do
		local highlights = format_fn(item)
		local parts = {}
		parts[1] = (i == view.cursor) and sel_prefix or pad
		for _, h in ipairs(highlights) do
			parts[#parts + 1] = h.text
		end
		lines[#lines + 1] = table.concat(parts)
	end

	vim.api.nvim_buf_set_option(view.buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(view.buf, "modifiable", false)

	-- Apply highlight extmarks
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	for row, item in ipairs(items) do
		local col = #sel_prefix -- offset by prefix width
		local highlights = format_fn(item)
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

	-- Update selection prefix for old and new cursor lines
	local sel_prefix = config.selection_prefix
	local pad = string.rep(" ", #sel_prefix)
	vim.api.nvim_buf_set_option(view.buf, "modifiable", true)
	if prev_cursor ~= view.cursor and prev_cursor >= 1 and prev_cursor <= #view.items then
		local old_line = vim.api.nvim_buf_get_lines(view.buf, prev_cursor - 1, prev_cursor, false)[1] or ""
		vim.api.nvim_buf_set_lines(view.buf, prev_cursor - 1, prev_cursor, false, { pad .. old_line:sub(#sel_prefix + 1) })
	end
	local new_line = vim.api.nvim_buf_get_lines(view.buf, view.cursor - 1, view.cursor, false)[1] or ""
	vim.api.nvim_buf_set_lines(view.buf, view.cursor - 1, view.cursor, false, { sel_prefix .. new_line:sub(#sel_prefix + 1) })
	vim.api.nvim_buf_set_option(view.buf, "modifiable", false)
end

---@param view Beast.Finder.ListView
---@param delta integer positive = down, negative = up
function M.move(view, delta)
	M.set_cursor(view, view.cursor + delta)
end

---@param view Beast.Finder.ListView
---@return Beast.Finder.Item|nil
function M.selected(view)
	return view.items[view.cursor]
end

return M
