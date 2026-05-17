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

---@param query Beast.Finder.Query
function M.mount(query)
	-- Autocmds augroup for picker lifetime
	query._augroup = vim.api.nvim_create_augroup("BeastFinderPicker", { clear = true })
	-- Hide cursor when entering the list buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = query._augroup,
		buffer = query.list_view.buf,
		callback = hide_cursor,
	})
	-- Restore cursor when leaving the list buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		group = query._augroup,
		buffer = query.list_view.buf,
		callback = restore_cursor,
	})

	-- Sync view.cursor when user moves cursor natively in the list window
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = query._augroup,
		buffer = query.list_view.buf,
		callback = function()
			-- stylua: ignore
			if not query.list_view:is_valid() then return end
			local buf_row = vim.api.nvim_win_get_cursor(query.list_view.win)[1]
			-- Translate buffer row to item index (virtual rendering offset)
			local item_idx = query.list_view._offset + buf_row
			if item_idx ~= query.list_view.cursor then
				ui.list.set_cursor(query.list_view, item_idx)
				vim.cmd("redraw")
				query:schedule_preview()
			end
		end,
	})

	-- Relayout on terminal resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = query._augroup,
		callback = function()
			query:relayout()
		end,
	})

	-- Close when focus moves to a window outside the finder
	vim.api.nvim_create_autocmd("WinEnter", {
		group = query._augroup,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			local finder_wins = {
				query.input_view.win,
				query.list_view.win,
			}
			if query.preview_view then
				finder_wins[#finder_wins + 1] = query.preview_view.win
			end
			for _, w in ipairs(finder_wins) do
				if current == w then
					return
				end
			end
			query:close()
		end,
	})
end

return M
