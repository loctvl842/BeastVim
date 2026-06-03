---@class Beast.Finder.UI.Backdrop
local M = {}

---@param backdrop integer?
---@return integer? win handle of the backdrop window, or nil if disabled
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

	return win
end

---@param win integer|nil backdrop window handle
function M.close(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

return M
