local View = require("beast.libs.view")

---@class Beast.Finder.FzfView : Beast.View
---@field ns integer
---@field job_id integer|nil
local FzfView = View:extend(function(obj, ns)
	obj.ns = ns
	obj.job_id = nil
end)

---@class Beast.Finder.UI.FzfWin
local M = {}

--- Create a floating terminal window for fzf.
---@param row integer
---@param col integer
---@param width integer
---@param height integer
---@param title? string
---@return Beast.Finder.FzfView
function M.create(row, col, width, height, title)
	-- Create a plain unlisted buffer for the terminal.
	-- Do NOT use scratch=true — it sets buftype=nofile which conflicts with termopen.
	local buf = vim.api.nvim_create_buf(false, false)

	local ns = vim.api.nvim_create_namespace("beast-finder-fzf")

	local display_title = title and (" " .. title .. " ") or nil

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = { "╭", "─", "┬", "│", "╯", "─", "╰", "│" },
		title = display_title,
		title_pos = "left",
		zindex = 101,
	})

	View.win.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderInputTitle")

	return FzfView(buf, win, ns)
end

return M
