local View = require("beast.libs.view")

---@class Beast.Finder.PreviewView : Beast.View
---@field ns integer
---@field visible boolean
local PreviewView = View:extend(function(obj, ns)
	obj.ns = ns
	obj.visible = true
end)

---@class Beast.Finder.UI.Preview
local M = {}

local MAX_PREVIEW_LINES = 500

---@param win_row integer
---@param win_col integer
---@param win_w integer
---@param win_h integer
---@return Beast.Finder.PreviewView
function M.create(win_row, win_col, win_w, win_h)
	local buf = View.buf.new("beast-finder-preview")
	local ns = vim.api.nvim_create_namespace("beast-finder-preview")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = { "┬", "─", "╮", "│", "╯", "─", "┴", "│" },
		zindex = 102,
	})

	View.win.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderPreviewTitle")
	View.win.wo(win, "wrap", false)
	View.win.wo(win, "number", true)
	View.win.wo(win, "relativenumber", false)

	return PreviewView(buf, win, ns)
end

---@param view Beast.Finder.PreviewView
---@param item Beast.Finder.Item
function M.show(view, item)
	-- stylua: ignore
	if not view:is_valid() or not view.visible then return end

	local lines = {}
	local ft = ""
	local title = ""
	if item.file then
		local ok, result = pcall(vim.fn.readfile, item.file, "", MAX_PREVIEW_LINES)
		if ok then
			for i, line in ipairs(result) do
				result[i] = line:gsub("[\r%z]", "")
			end
			lines = result
		else
			lines = { "(cannot read file)" }
		end
		ft = vim.filetype.match({ filename = item.file }) or ""
		title = vim.fn.fnamemodify(item.file, ":t")
	end

	-- Update window title with current file name
	if title ~= "" then
		pcall(vim.api.nvim_win_set_config, view.win, {
			title = " " .. title .. " ",
			title_pos = "center",
		})
	end
	vim.bo[view.buf].modifiable = true
	local ok_set = pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, lines)
	if not ok_set then
		-- Binary file — lines contain embedded newlines
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "(binary file)" })
		vim.bo[view.buf].modifiable = false
		return
	end
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = ft

	-- Jump to the item's line if provided
	if item.pos and view:is_valid() then
		local line = math.max(1, math.min(item.pos[1], #lines))
		pcall(vim.api.nvim_win_set_cursor, view.win, { line, item.pos[2] or 0 })
	else
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end
end

---@param view Beast.Finder.PreviewView
function M.clear(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, {})
	vim.bo[view.buf].modifiable = false
	pcall(vim.api.nvim_win_set_config, view.win, { title = "", title_pos = "center" })
end

return M
