local config = require("beast.libs.finder.config")

local M = {}

---@param zindex integer zindex of the picker windows (backdrop goes below)
---@return integer? win handle of the backdrop window, or nil if disabled
function M.create(zindex)
	-- stylua: ignore
	if not config.backdrop then return nil end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = vim.o.columns,
		height = vim.o.lines,
		row = 0,
		col = 0,
		style = "minimal",
		focusable = false,
		zindex = zindex - 1,
	})

	Util.wo(win, "winhl", "Normal:BeastFinderBackdrop")
	Util.wo(win, "winblend", 60)

	return win
end

---@param win integer|nil backdrop window handle
function M.close(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

return M
