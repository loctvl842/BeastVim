local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.PreviewView : Beast.View
---@field ns integer
---@field visible boolean
local PreviewView = View:extend(function(obj, ns)
	obj.ns = ns
	obj.visible = true
end)

local M = {}

local MAX_PREVIEW_LINES = 500

---@param win_row integer
---@param win_col integer
---@param win_w integer
---@param win_h integer
---@return Beast.Finder.PreviewView
function M.create(win_row, win_col, win_w, win_h)
	local buf = Buffer.new("beastvim-finder-preview")
	local ns = vim.api.nvim_create_namespace("beastvim-finder-preview")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = { "┬", "─", "╮", "│", "╯", "─", "┴", "│" },
		zindex = config.zindex,
	})

	Util.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder")
	Util.wo(win, "wrap", false)
	Util.wo(win, "number", true)
	Util.wo(win, "relativenumber", false)

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
			lines = result
		else
			lines = { "(cannot read file)" }
		end
		ft = vim.filetype.match({ filename = item.file }) or ""
		title = vim.fn.fnamemodify(item.file, ":t")
	elseif item.buf and vim.api.nvim_buf_is_valid(item.buf) then
		lines = vim.api.nvim_buf_get_lines(item.buf, 0, MAX_PREVIEW_LINES, false)
		ft = vim.bo[item.buf].filetype or ""
		title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.buf), ":t")
		if title == "" then
			title = "[No Name]"
		end
	end

	-- Update window title with current file name
	if title ~= "" then
		pcall(vim.api.nvim_win_set_config, view.win, {
			title = " " .. title .. " ",
			title_pos = "center",
		})
	end

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
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
function M.toggle(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.visible = not view.visible
	local ok, conf = pcall(vim.api.nvim_win_get_config, view.win)
	if not ok then
		return
	end
	conf.hide = not view.visible
	pcall(vim.api.nvim_win_set_config, view.win, conf)
end

return M
