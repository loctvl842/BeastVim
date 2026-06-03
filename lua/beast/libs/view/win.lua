---@class Beast.View.Win
local M = {}

--- Set a window-local option safely across Neovim versions.
---@param win integer
---@param k string
---@param v any
function M.wo(win, k, v)
	if vim.api.nvim_set_option_value then
		-- 0.9+ recommended
		vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
	else -- pre-0.9, still works
		vim.wo[win][k] = v
	end
end

--- Find the most recent normal (non-beast-UI) window.
--- Tries the alternate window first, then the current window, then all
--- non-floating windows in the current tabpage.
---@return integer? win  A valid window id, or nil if none found
function M.find_normal()
	local function is_normal(win)
		if not vim.api.nvim_win_is_valid(win) then
			return false
		end
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative ~= "" then
			return false
		end
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.bo[buf].filetype or ""
		return not ft:find("^beast%-")
	end

	-- 1. Alternate window (winnr("#")) — the window you were in before
	local alt = vim.fn.win_getid(vim.fn.winnr("#"))
	if alt ~= 0 and is_normal(alt) then
		return alt
	end

	-- 2. Current window
	local cur = vim.api.nvim_get_current_win()
	if is_normal(cur) then
		return cur
	end

	-- 3. Scan all windows in current tabpage
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if is_normal(win) then
			return win
		end
	end

	return nil
end

return M
