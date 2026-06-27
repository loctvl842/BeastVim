local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

local M = {}

-- ---------------------------------------------------------------------------
-- Cursor hiding (same pattern as explorer)
-- ---------------------------------------------------------------------------
local HIDDEN_CURSOR = "a:block-BeastFinderListCursor"
local saved_guicursor = nil
local cursor_hidden = false

local function hide_cursor()
	-- stylua: ignore
	if cursor_hidden then return end
	if saved_guicursor == nil then
		saved_guicursor = vim.o.guicursor
	end
	vim.o.guicursor = HIDDEN_CURSOR
	cursor_hidden = true
end

local function restore_cursor()
	-- stylua: ignore
	if not cursor_hidden then return end
	if saved_guicursor ~= nil then
		vim.o.guicursor = saved_guicursor
		saved_guicursor = nil
	end
	cursor_hidden = false
end

---@param state Beast.Finder.State
function M.mount(state)
	-- Autocmds augroup for picker lifetime
	state.augroup = vim.api.nvim_create_augroup("BeastFinderPicker", { clear = true })
	-- Hide cursor when entering the list buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.augroup,
		buffer = state.view.list.buf,
		callback = hide_cursor,
	})
	-- Restore cursor when leaving the list buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		group = state.augroup,
		buffer = state.view.list.buf,
		callback = restore_cursor,
	})

	-- Sync view.cursor when user moves cursor natively in the list window
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = state.augroup,
		buffer = state.view.list.buf,
		callback = function()
			-- stylua: ignore
			if not state.view.list:is_valid() then return end
			local buf_row = vim.api.nvim_win_get_cursor(state.view.list.win)[1]
			-- Translate buffer row to item index (accounts for group header rows)
			local item_idx = ui.list.item_at_row(state.view.list, buf_row)
			if item_idx and item_idx ~= state.view.list.cursor then
				ui.list.set_cursor(state.view.list, item_idx)
				vim.cmd("redraw")
				render.schedule_preview(state)
			end
		end,
	})

	-- Relayout on terminal resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,
		callback = function()
			state:relayout()
		end,
	})

	-- Close when focus moves to a window outside the finder
	vim.api.nvim_create_autocmd("WinEnter", {
		group = state.augroup,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			local finder_wins = {
				state.view.input.win,
				state.view.list.win,
			}
			if state.view.preview then
				finder_wins[#finder_wins + 1] = state.view.preview.win
			end
			for _, w in ipairs(finder_wins) do
				if current == w then
					return
				end
			end
			state:reset()
		end,
	})
end

return M
