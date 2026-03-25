---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")

local M = {}

local HIDDEN_CURSOR = "a:block-BeastExplorerCursor"

---@type string?
local saved_guicursor = nil

local cursor_hidden = false

local function get_explorer_win()
	return state.view and state.view.win or nil
end

local function is_explorer_win(win)
	local explorer_win = get_explorer_win()
	return explorer_win and vim.api.nvim_win_is_valid(explorer_win) and win == explorer_win
end

local function hide_cursor()
	if cursor_hidden then
		return
	end
	if saved_guicursor == nil then
		saved_guicursor = vim.o.guicursor
	end
	vim.o.guicursor = HIDDEN_CURSOR
	cursor_hidden = true
end

local function restore_cursor()
	if not cursor_hidden then
		return
	end
	if saved_guicursor ~= nil then
		vim.o.guicursor = saved_guicursor
		saved_guicursor = nil
	end
	cursor_hidden = false
end

local function refresh_cursor()
	local current_win = vim.api.nvim_get_current_win()
	if is_explorer_win(current_win) then
		hide_cursor()
	else
		restore_cursor()
	end
end
--- Mount cursor-hiding autocmds for the explorer window.
--- Safe to call multiple times.
function M.mount()
	if state.augroup then
		return
	end

	if not state.view or not state.view.buf or not state.view.win then
		return
	end

	vim.api.nvim_set_hl(0, "BeastExplorerCursor", {
		blend = 100,
		nocombine = true,
	})

	state.augroup = vim.api.nvim_create_augroup("BeastExplorerUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = state.augroup,
		callback = function()
			refresh_cursor()
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		group = state.augroup,
		callback = function()
			vim.schedule(function()
				if vim.api.nvim_get_current_win() then
					refresh_cursor()
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineEnter", {
		group = state.augroup,
		callback = function()
			restore_cursor()
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = state.augroup,
		callback = function()
			refresh_cursor()
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		pattern = tostring(state.view.win),
		once = true,
		callback = function()
			restore_cursor()
			state.augroup = nil
		end,
	})

	refresh_cursor()
end

return M
