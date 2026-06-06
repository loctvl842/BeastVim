---Public surface for the window lib.
local config = require("beast.libs.window.config")
local layout = require("beast.libs.window.layout")
local win = require("beast.libs.window.win")
local api = vim.api

local M = {}

---Per-tab maximize snapshot, keyed by tabpage handle.
---@type table<integer, Beast.Window.WinResizeData[]>
local maximized = {}
---@type integer|nil
local guard_aug

local function apply(data)
	if vim.tbl_isempty(data) then
		return
	end
	if config.animation.enable then
		require("beast.libs.window.animate").run(data)
	else
		layout.apply(data)
	end
end

local function alive(snap)
	local out = {}
	for _, d in ipairs(snap) do
		if win.is_valid(d.winid) then
			out[#out + 1] = d
		end
	end
	return out
end

local function snapshot(data)
	local out = {}
	for i, d in ipairs(data) do
		out[i] = {
			winid = d.winid,
			width = api.nvim_win_get_width(d.winid),
			height = api.nvim_win_get_height(d.winid),
		}
	end
	return out
end

local function clear_guard()
	if guard_aug then
		pcall(api.nvim_clear_autocmds, { group = guard_aug })
	end
end

local function install_guard()
	guard_aug = api.nvim_create_augroup("beast.window.maximize", { clear = true })

	api.nvim_create_autocmd("WinEnter", {
		group = guard_aug,
		callback = function()
			if win.is_floating(api.nvim_get_current_win()) then
				return
			end
			clear_guard()
			local tab = api.nvim_get_current_tabpage()
			local snap = maximized[tab]
			maximized[tab] = nil
			apply(snap and alive(snap) or layout.equalize_wins())
		end,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = guard_aug,
		callback = function(ctx)
			local id = tonumber(ctx.match)
			if id and not win.is_floating(id) then
				maximized[api.nvim_get_current_tabpage()] = nil
				clear_guard()
			end
		end,
	})
end

local function should_skip()
	return vim.g.beast_window_disabled or win.is_floating(api.nvim_get_current_win())
end

---Toggle full-screen maximize for the current window.
function M.maximize()
	if should_skip() then
		return
	end
	local tab = api.nvim_get_current_tabpage()
	local snap = maximized[tab]
	if snap then
		maximized[tab] = nil
		clear_guard()
		apply(alive(snap))
		return
	end
	local wd, hd = layout.maximize_win(api.nvim_get_current_win())
	local data = layout.merge(wd, hd)
	if vim.tbl_isempty(data) then
		return
	end
	maximized[tab] = snapshot(data)
	install_guard()
	apply(data)
end

---Equalize all windows (CTRL-W =).
function M.equalize()
	if should_skip() then
		return
	end
	maximized[api.nvim_get_current_tabpage()] = nil
	clear_guard()
	apply(layout.equalize_wins())
end

function M.enable()
	require("beast.libs.window.autocmds").register()
	config.autowidth.enable = true
end

function M.disable()
	require("beast.libs.window.autocmds").unregister()
	config.autowidth.enable = false
end

function M.toggle()
	if config.autowidth.enable then
		M.disable()
	else
		M.enable()
	end
end

---@param opts? Beast.Window.Config
function M.setup(opts)
	config.setup(opts)
	local cmd = api.nvim_create_user_command
	cmd("BeastWindowMaximize", M.maximize, { desc = "Toggle maximize current window" })
	cmd("BeastWindowEqualize", M.equalize, { desc = "Equalize window sizes" })
	cmd("BeastWindowToggleAutowidth", M.toggle, { desc = "Toggle autowidth" })
	if config.autowidth.enable then
		require("beast.libs.window.autocmds").register()
	end
end

return M
