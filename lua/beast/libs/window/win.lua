---Bare-winid window helpers. Replaces windows.nvim's `Window` middleclass wrapper.
local config = require("beast.libs.window.config")
local api, fn = vim.api, vim.fn

local M = {}

function M.is_valid(w)
	return api.nvim_win_is_valid(w)
end

function M.is_floating(w)
	return fn.win_gettype(w) == "popup"
end

function M.set_width(w, n)
	pcall(api.nvim_win_set_width, w, n)
end

function M.set_height(w, n)
	pcall(api.nvim_win_set_height, w, n)
end

function M.get_option(w, name)
	local ok, v = pcall(api.nvim_get_option_value, name, { win = w })
	return ok and v or nil
end

function M.is_ignored(w)
	local buf = api.nvim_win_get_buf(w)
	if vim.b[buf].beast_window_disabled then
		return true
	end
	local ig = config.ignore
	return ig.buftype[vim.bo[buf].buftype] or ig.filetype[vim.bo[buf].filetype] or false
end

---Mirrors windows.nvim `wanted_width` semantics:
---  0 < w < 1  → fraction of vim.o.columns
---  1 < w < 2  → fraction of textwidth
---  else       → textwidth + w
function M.get_wanted_width(w)
	if M.get_option(w, "winfixwidth") then
		return api.nvim_win_get_width(w)
	end
	local buf = api.nvim_win_get_buf(w)
	local ww = config.autowidth.filetype[vim.bo[buf].filetype] or config.autowidth.winwidth
	if ww > 0 and ww < 1 then
		return math.floor(ww * vim.o.columns)
	end
	local tw = vim.bo[buf].textwidth
	if not tw or tw == 0 then
		tw = 80
	end
	if ww > 1 and ww < 2 then
		return math.floor(ww * tw)
	end
	return tw + ww
end

return M
