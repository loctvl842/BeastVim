---Public surface for the window lib: setup, maximize/equalize, enable/disable/toggle,
---user commands. Phase 3 — autowidth (Phase 4) and animation (Phase 5) wire in here later.

local config = require("beast.libs.window.config")
local layout = require("beast.libs.window.layout")
local resize = require("beast.libs.window.resize")
local state = require("beast.libs.window.state")
local win = require("beast.libs.window.win")
local api = vim.api

local M = {}

-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

---Snapshot the current width/height of each leaf returned by `data` so we can
---restore later. We snapshot from `nvim_win_get_*` directly (not from `data`),
---because `data` describes the TARGET sizes, not the originals.
---@param data Beast.Window.WinResizeData[]
---@param axis 'width'|'height'
---@return Beast.Window.WinResizeData[]
local function snapshot(data, axis)
	local snap = {}
	for i, d in ipairs(data) do
		if axis == "width" then
			snap[i] = { winid = d.winid, width = win.get_width(d.winid) }
		else
			snap[i] = { winid = d.winid, height = win.get_height(d.winid) }
		end
	end
	return snap
end

---Filter snapshot to entries whose windows are still valid.
---@param snap Beast.Window.WinResizeData[]
---@return Beast.Window.WinResizeData[]
local function alive(snap)
	local out = {}
	for _, d in ipairs(snap) do
		if win.is_valid(d.winid) then
			out[#out + 1] = d
		end
	end
	return out
end

---Apply resize data. Dispatches to `animate.run` when animation is enabled,
---otherwise falls back to immediate `resize.apply`.
---@param data Beast.Window.WinResizeData[]
local function apply(data)
	if vim.tbl_isempty(data) then
		return
	end
	if config.animation.enable then
		require("beast.libs.window.animate").run(data)
	else
		resize.apply(data)
	end
end

---@return boolean
local function should_skip()
	if vim.g.beast_window_disabled then
		return true
	end
	local curwin = api.nvim_get_current_win()
	if win.is_floating(curwin) then
		return true
	end
	return false
end

-- =============================================================================
-- MAXIMIZE — GUARD AUTOCMD
-- =============================================================================

---Clear the maximize-guard autocmd group (if installed).
local function clear_maximize_guard()
	if state.augroup_maximize then
		pcall(api.nvim_clear_autocmds, { group = state.augroup_maximize })
	end
end

---Install the guard autocmd that auto-restores when focus leaves the maximized window.
local function install_maximize_guard()
	state.augroup_maximize = api.nvim_create_augroup("beast.window.maximize", { clear = true })

	api.nvim_create_autocmd("WinEnter", {
		group = state.augroup_maximize,
		callback = function()
			local cur = api.nvim_get_current_win()
			if win.is_floating(cur) then
				return
			end
			clear_maximize_guard()

			local snap = state.get_maximized()
			local data
			if snap then
				local wd = alive(snap.width or {})
				local hd = alive(snap.height or {})
				data = resize.merge(wd, hd)
				state.clear_maximized()
			else
				data = layout.equalize_wins(true, true)
			end
			apply(data)
		end,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = state.augroup_maximize,
		callback = function(ctx)
			local id = tonumber(ctx.match)
			if id and not win.is_floating(id) then
				state.clear_maximized()
				clear_maximize_guard()
			end
		end,
	})

	api.nvim_create_autocmd("TabClosed", {
		group = state.augroup_maximize,
		callback = function()
			state.gc_tabs()
		end,
	})
end

-- =============================================================================
-- MAXIMIZE / EQUALIZE — PUBLIC API
-- =============================================================================

---Toggle full-screen maximize for the current window.
function M.maximize()
	if should_skip() then
		return
	end
	local curwin = api.nvim_get_current_win()

	local snap = state.get_maximized()
	if snap then
		-- RESTORE
		local wd = alive(snap.width or {})
		local hd = alive(snap.height or {})
		state.clear_maximized()
		clear_maximize_guard()
		apply(resize.merge(wd, hd))
		return
	end

	-- MAXIMIZE
	local wd, hd = layout.maximize_win(curwin, true, true)
	if vim.tbl_isempty(wd) and vim.tbl_isempty(hd) then
		return
	end
	state.set_maximized({
		width = snapshot(wd, "width"),
		height = snapshot(hd, "height"),
	})
	install_maximize_guard()
	apply(resize.merge(wd, hd))
end

---Maximize current window along the vertical axis only (rows).
function M.maximize_vertically()
	if should_skip() then
		return
	end
	local curwin = api.nvim_get_current_win()
	local snap = state.get_maximized()
	if snap and snap.height then
		local hd = alive(snap.height)
		snap.height = nil
		if not snap.width then
			state.clear_maximized()
		end
		apply(hd)
		return
	end
	local _, hd = layout.maximize_win(curwin, false, true)
	if vim.tbl_isempty(hd) then
		return
	end
	snap = snap or {}
	snap.height = snapshot(hd, "height")
	state.set_maximized(snap)
	install_maximize_guard()
	apply(hd)
end

---Maximize current window along the horizontal axis only (columns).
function M.maximize_horizontally()
	if should_skip() then
		return
	end
	local curwin = api.nvim_get_current_win()
	local snap = state.get_maximized()
	if snap and snap.width then
		local wd = alive(snap.width)
		snap.width = nil
		if not snap.height then
			state.clear_maximized()
		end
		apply(wd)
		return
	end
	local wd = layout.maximize_win(curwin, true, false)
	if vim.tbl_isempty(wd) then
		return
	end
	snap = snap or {}
	snap.width = snapshot(wd, "width")
	state.set_maximized(snap)
	install_maximize_guard()
	apply(wd)
end

---Equalize all windows (CTRL-W =).
function M.equalize()
	if should_skip() then
		return
	end
	state.clear_maximized()
	clear_maximize_guard()
	local data = layout.equalize_wins(true, true)
	apply(data)
end

-- =============================================================================
-- AUTOWIDTH TOGGLES (Phase 4 wires the autocmds)
-- =============================================================================

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

-- =============================================================================
-- SETUP + USER COMMANDS
-- =============================================================================

local commands_registered = false
local function register_commands()
	if commands_registered then
		return
	end
	commands_registered = true
	local cmd = api.nvim_create_user_command
	cmd("BeastWindowMaximize", M.maximize, { bang = true, desc = "Toggle maximize current window" })
	cmd("BeastWindowMaximizeVertically", M.maximize_vertically, { bang = true })
	cmd("BeastWindowMaximizeHorizontally", M.maximize_horizontally, { bang = true })
	cmd("BeastWindowEqualize", M.equalize, { bang = true, desc = "Equalize window sizes" })
	cmd("BeastWindowEnableAutowidth", M.enable, { bang = true })
	cmd("BeastWindowDisableAutowidth", M.disable, { bang = true })
	cmd("BeastWindowToggleAutowidth", M.toggle, { bang = true })
end

---@param opts? Beast.Window.Config
function M.setup(opts)
	config.setup(opts)
	register_commands()
	if config.autowidth.enable then
		require("beast.libs.window.autocmds").register()
	end
end

return M
