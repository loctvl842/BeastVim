--- The key hints under the picker ("<C-g> grep 38 files   <BS> back to Files"): one borderless line,
--- right-aligned with the picker, drawn over the backdrop. It is never focusable and only exists
--- while there is something to say and a screen row to say it on.
local config = require("beast.libs.finder.config")

---@class Beast.Finder.UI.Hint
local M = {}

local NS = vim.api.nvim_create_namespace("beast-finder-hint")

---@class Beast.Finder.HintView
---@field buf integer
---@field win? integer

---@return Beast.Finder.HintView
function M.create()
	local buf = vim.api.nvim_create_buf(false, true)
	-- Hiding closes the window only: the buffer is reused when the hint comes back (`close` deletes it).
	vim.bo[buf].bufhidden = "hide"
	return { buf = buf }
end

---@param view Beast.Finder.HintView
function M.hide(view)
	if view.win and vim.api.nvim_win_is_valid(view.win) then
		pcall(vim.api.nvim_win_close, view.win, true)
	end
	view.win = nil
end

--- Show `chunks` at `geo` (the layout's `hint`), or hide the line when there is nothing to show or no room.
---@param view Beast.Finder.HintView
---@param chunks? { [1]: string, [2]: string }[]
---@param geo? { row: integer, right: integer }
function M.set(view, chunks, geo)
	if not chunks or not geo or not vim.api.nvim_buf_is_valid(view.buf) then
		return M.hide(view)
	end
	local text, width = {}, 0
	for _, chunk in ipairs(chunks) do
		text[#text + 1] = chunk[1]
	end
	local line = table.concat(text)
	width = vim.fn.strdisplaywidth(line)
	-- Hints are tooltips: when they do not fit beside the picker's left edge there is nothing to show.
	if width > geo.right then
		return M.hide(view)
	end

	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { line })
	vim.api.nvim_buf_clear_namespace(view.buf, NS, 0, -1)
	local col = 0
	for _, chunk in ipairs(chunks) do
		vim.api.nvim_buf_set_extmark(view.buf, NS, 0, col, { end_col = col + #chunk[1], hl_group = chunk[2] })
		col = col + #chunk[1]
	end

	local win_config = {
		relative = "editor",
		row = geo.row,
		col = geo.right - width,
		width = width,
		height = 1,
		style = "minimal",
		focusable = false,
		zindex = 102,
	}
	if view.win and vim.api.nvim_win_is_valid(view.win) then
		vim.api.nvim_win_set_config(view.win, win_config)
	else
		view.win = vim.api.nvim_open_win(view.buf, false, win_config)
		vim.wo[view.win].winhl = "Normal:BeastFinderHint"
		vim.wo[view.win].winblend = config.backdrop
	end
end

---@param view Beast.Finder.HintView
function M.close(view)
	M.hide(view)
	if vim.api.nvim_buf_is_valid(view.buf) then
		pcall(vim.api.nvim_buf_delete, view.buf, { force = true })
	end
end

return M
