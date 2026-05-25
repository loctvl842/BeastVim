-- Per-render context built from `g:statusline_winid`.
--
-- Winbar uses the same `g:statusline_winid` as statusline — Neovim sets it before
-- each `%!` evaluation. The key difference: winbar width is always per-window
-- (`nvim_win_get_width`), unlike statusline which spans the full editor with `laststatus=3`.

local M = {}

---@class Beast.Breadcrumb.Context
---@field winid integer       Target window
---@field bufnr integer       Buffer in target window
---@field is_active boolean   Is target window the focused window?
---@field width integer       Available winbar width in cells
---@field filetype string     Buffer filetype
---@field buftype string      Buffer buftype
---@field bufname string      Full buffer name (path)

---Build a fresh render context using `g:statusline_winid`.
---@return Beast.Breadcrumb.Context
function M.build()
	local cur_win = vim.api.nvim_get_current_win()
	local target_win = vim.g.statusline_winid

	-- Fallback: if g:statusline_winid is unset (e.g. direct call from :lua), use current win.
	if not target_win or target_win == 0 or not vim.api.nvim_win_is_valid(target_win) then
		target_win = cur_win
	end

	local bufnr = vim.api.nvim_win_get_buf(target_win)

	return {
		winid = target_win,
		bufnr = bufnr,
		is_active = (target_win == cur_win),
		width = vim.api.nvim_win_get_width(target_win),
		filetype = vim.bo[bufnr].filetype,
		buftype = vim.bo[bufnr].buftype,
		bufname = vim.api.nvim_buf_get_name(bufnr),
	}
end

return M
