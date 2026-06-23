---@class Beast.Finder.UI.Backdrop
local M = {}

---@class Beast.Finder.BackdropView : Beast.View.Instance
local BackdropView = View:extend()

---@param backdrop integer?
function M.create(backdrop)
	local buf = View.buf.new("beast-finder-backdrop")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = vim.o.columns,
		height = vim.o.lines,
		row = 0,
		col = 0,
		style = "minimal",
		focusable = false,
		zindex = 100, -- 'input', 'preview', 'list' windows are 101+
	})

	View.win.wo(win, "winhl", "Normal:BeastFinderBackdrop")
	View.win.wo(win, "winblend", backdrop or 60)

	return BackdropView(buf, win)
end

return M
