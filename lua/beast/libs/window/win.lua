---Bare-winid window helpers — replaces windows.nvim's middleclass `Window` wrapper.
---All functions accept a winid integer and are safe against invalid windows (return defaults).
local config = require("beast.libs.window.config")
local api = vim.api
local fn = vim.fn

local M = {}

---@param winid integer
---@return integer
function M.get_width(winid)
	return api.nvim_win_get_width(winid)
end

---@param winid integer
---@return integer
function M.get_height(winid)
	return api.nvim_win_get_height(winid)
end

---@param winid integer
---@param width integer
function M.set_width(winid, width)
	pcall(api.nvim_win_set_width, winid, width)
end

---@param winid integer
---@param height integer
function M.set_height(winid, height)
	pcall(api.nvim_win_set_height, winid, height)
end

---@param winid integer
---@return boolean
function M.is_valid(winid)
	return api.nvim_win_is_valid(winid)
end

---@param winid integer
---@param name string
---@return any
function M.get_option(winid, name)
	local ok, value = pcall(api.nvim_get_option_value, name, { win = winid })
	if ok then
		return value
	end
	return nil
end

---@param winid integer
---@return 'autocmd'|'command'|'loclist'|'popup'|'preview'|'quickfix'|'unknown'|''
function M.get_type(winid)
	return fn.win_gettype(winid)
end

---@param winid integer
---@return boolean
function M.is_floating(winid)
	return M.get_type(winid) == "popup"
end

---Returns true if the window should be excluded from auto-resize/maximize logic.
---@param winid integer
---@return boolean
function M.is_ignored(winid)
	if vim.b[api.nvim_win_get_buf(winid)].beast_window_disabled then
		return true
	end
	local buf = api.nvim_win_get_buf(winid)
	local bt = vim.bo[buf].buftype
	local ft = vim.bo[buf].filetype
	if config.ignore.buftype[bt] or config.ignore.filetype[ft] then
		return true
	end
	return false
end

---Gutter width (signs, fold, numbers).
---@param winid integer
---@return integer
function M.get_text_offset(winid)
	local info = fn.getwininfo(winid)
	if info and info[1] then
		return info[1].textoff or 0
	end
	return 0
end

---Wanted width for this window's buffer, based on textwidth + cfg.autowidth.winwidth
---(with per-filetype overrides). Mirrors windows.nvim semantics:
---  * 0 < w < 1  → floor(w * vim.o.columns)
---  * 1 < w < 2  → floor(w * textwidth)
---  * else        → textwidth + w
---If `winfixwidth` is set, returns current width unchanged.
---@param winid integer
---@return integer
function M.get_wanted_width(winid)
	if M.get_option(winid, "winfixwidth") then
		return M.get_width(winid)
	end

	local buf = api.nvim_win_get_buf(winid)
	local ft = vim.bo[buf].filetype
	local w = config.autowidth.filetype[ft] or config.autowidth.winwidth

	if 0 < w and w < 1 then
		return math.floor(w * vim.o.columns)
	end

	local tw = vim.bo[buf].textwidth
	if not tw or tw == 0 then
		tw = 80
	end

	if 1 < w and w < 2 then
		return math.floor(w * tw)
	end
	return tw + w
end

return M
