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

---@param session Beast.Finder.Session
function M.mount(session)
	-- Autocmds augroup for picker lifetime (one per session: a picker opened while another one closes must not share it)
	session.augroup = vim.api.nvim_create_augroup("BeastFinderPicker" .. session.id, { clear = true })
	-- Hide cursor when entering the list buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = session.augroup,
		buffer = session.view.list.buf,
		callback = hide_cursor,
	})
	-- Restore cursor when leaving the list buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		group = session.augroup,
		buffer = session.view.list.buf,
		callback = restore_cursor,
	})

	-- Sync view.cursor when user moves cursor natively in the list window
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = session.augroup,
		buffer = session.view.list.buf,
		callback = function()
			-- stylua: ignore
			if not session.view.list:is_valid() then return end
			local buf_row = vim.api.nvim_win_get_cursor(session.view.list.win)[1]
			-- Translate buffer row to item index (accounts for group header rows)
			local item_idx = ui.list.item_at_row(session.view.list, buf_row)
			if item_idx and item_idx ~= session.view.list.cursor then
				ui.list.set_cursor(session.view.list, item_idx)
				vim.cmd("redraw")
				render.schedule_preview(session)
			end
		end,
	})

	-- Relayout on terminal resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = session.augroup,
		callback = function()
			session:relayout()
		end,
	})

	-- Load the source again when one of the events it listens to (`source.reload_on`) fires:
	-- by default the shared visibility session (hidden/gitignored) changing, whether toggled from
	-- Explorer, the tabline buttons or the global keymaps. Match-pipeline sources (files,
	-- buffers, ...) reload from source; the stream pipeline (live_grep) re-runs against the
	-- current pattern. The events are those of the level shown at open; a level pushed later with other `reload_on` events must register its own (not needed until a key pushes levels).
	for _, event in ipairs(session.level.query.source.reload_on) do
		vim.api.nvim_create_autocmd("User", {
			group = session.augroup,
			pattern = event,
			callback = function()
				session.level:reload()
			end,
		})
	end

	-- Close when focus moves to a window outside the finder
	vim.api.nvim_create_autocmd("WinEnter", {
		group = session.augroup,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			local finder_wins = {
				session.view.input.win,
				session.view.list.win,
			}
			if session.view.preview then
				finder_wins[#finder_wins + 1] = session.view.preview.win
			end
			for _, w in ipairs(finder_wins) do
				if current == w then
					return
				end
			end
			session:close()
		end,
	})
end

return M
