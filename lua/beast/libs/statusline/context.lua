-- When Neovim evaluates `%!` (statusline expression), which window/buffer should we read data
-- from? The "current" window in Lua isn't necessarily the window the statusline is being drawn for.
--
-- `g:statusline_winid` — Neovim sets this global variable to the target window before each %! evaluation. If you have two
-- splits, Neovim evaluates your statusline function twice — once per split — and g:statusline_winid tells you which one
-- you're rendering for.
--
-- `is_active` — We compare `target_win == cur_win`. If they match, we're drawing the focused window's statusline. Components
-- can dim themselves on inactive windows.
--
-- `bufnr` — Derived from `target_win` via `nvim_win_get_buf`. All buffer-local reads (`vim.bo[bufnr].filetype`, etc.) use this —
-- never `vim.bo[0]`, which would always read the active buffer.
--
-- The `laststatus=3` width fix — This was the bug that made components disappear on explorer. With `laststatus=3` (global
-- statusline), there's one bar spanning the full editor. But `nvim_win_get_width(target_win)` returns the window's width — so
-- when explorer (30 chars wide) was focused, truncation thought it only had 30 chars and dropped components. Fix: use
-- `vim.o.columns` for the real statusline width.
--
-- The fallback — If `g:statusline_winid` is nil/invalid (e.g., calling render manually from `:lua`), we fall back to
-- `nvim_get_current_win()`.

local M = {}

---Per-render context built from `g:statusline_winid`.
---@class Beast.Statusline.Context
---@field winid integer       Target window
---@field bufnr integer       Buffer in target window
---@field is_active boolean   Is target window the focused window?
---@field mode string         Current mode (raw `nvim_get_mode().mode`)
---@field width integer       Available statusline width in cells
---@field filetype string     Buffer filetype
---@field buftype string      Buffer buftype

---Build a fresh render context using `g:statusline_winid` for window/buffer disambiguation.
---
---Why we never read `0`/current window here: when Neovim evaluates `%!` for an inactive
---split, the calling context is the active window — but the statusline being drawn is for
---the inactive window. `g:statusline_winid` is the *target* window. Always use it.
---@return Beast.Statusline.Context
function M.build()
	local cur_win = vim.api.nvim_get_current_win()
	local target_win = vim.g.statusline_winid

	-- Fallback: if g:statusline_winid is unset (e.g. direct call from :lua), use current win.
	if not target_win or target_win == 0 or not vim.api.nvim_win_is_valid(target_win) then
		target_win = cur_win
	end

	local bufnr = vim.api.nvim_win_get_buf(target_win)

	-- With laststatus=3 (global statusline), the bar spans the full editor width,
	-- not the width of the individual window being evaluated. Use vim.o.columns
	-- so truncation has the real available space.
	local width
	if vim.o.laststatus == 3 then
		width = vim.o.columns
	else
		width = vim.api.nvim_win_get_width(target_win)
	end

	return {
		winid = target_win,
		bufnr = bufnr,
		is_active = (target_win == cur_win),
		mode = vim.api.nvim_get_mode().mode,
		width = width,
		filetype = vim.bo[bufnr].filetype,
		buftype = vim.bo[bufnr].buftype,
	}
end

return M
