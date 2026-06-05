---Autowidth autocmd wiring. Ported from windows.nvim/autowidth.lua.
---
---The choreography:
---  * BufWinEnter / WinEnter / VimResized → set resizing_request=true, call setup_layout().
---  * setup_layout() guards on the flag (single-flight) and dispatches to layout.autowidth.
---  * WinNew → mark new_window for one cycle so the first BufWinEnter on a new
---    split treats it as "create" (height equalize) instead of "resize current".
---  * Disabled when the focused window is floating, ignored, or the command-line.
---
---Animation hand-off lives in `apply_resize` (Phase 5 swaps resize.apply for
---animate.run when config.animation.enable is true).

local api = vim.api
local config = require("beast.libs.window.config")
local layout = require("beast.libs.window.layout")
local resize = require("beast.libs.window.resize")
local state = require("beast.libs.window.state")
local win = require("beast.libs.window.win")

local M = {}

---@type integer|nil  Current win at last invocation; nil until first WinEnter.
local curwin = nil
---@type integer|nil  Buffer in curwin at last invocation.
local curbufnr = nil
---@type boolean  Flag from WinNew → consumed by the next BufWinEnter.
local new_window = false

---Apply data with whatever transport is active. Phase 5 will swap to animate.run.
---@param data Beast.Window.WinResizeData[]
local function apply_resize(data)
	if vim.tbl_isempty(data) then
		return
	end
	resize.apply(data)
end

---@return boolean
local function should_run()
	if vim.g.beast_window_disabled then
		return false
	end
	if not config.autowidth.enable then
		return false
	end
	return true
end

local function setup_layout()
	if not curwin or not state.resizing_request then
		return
	end
	state.resizing_request = false

	local data = layout.autowidth(curwin)
	if vim.tbl_isempty(data) then
		-- If a new window was just created, equalize heights once so the new split
		-- shares vertical space with its siblings (matches windows.nvim behavior).
		if new_window then
			data = layout.equalize_wins(false, true)
		end
	elseif new_window then
		data = resize.merge(data, layout.equalize_wins(false, true))
	end

	new_window = false

	-- If the maximize-guard cleared our cache because of focus change, we don't
	-- want autowidth fighting the restore on the same tick — defer one event loop.
	apply_resize(data)
end

---Register all autocmds. Idempotent (cleared+re-registered).
function M.register()
	if state.augroup_autowidth then
		api.nvim_clear_autocmds({ group = state.augroup_autowidth })
	end
	state.augroup_autowidth = api.nvim_create_augroup("beast.window.autowidth", { clear = true })
	local aug = state.augroup_autowidth

	api.nvim_create_autocmd("BufWinEnter", {
		group = aug,
		callback = function(ctx)
			if not should_run() then
				return
			end
			local w = api.nvim_get_current_win()
			if win.is_floating(w) or win.get_type(w) == "command" then
				return
			end
			if new_window and win.is_ignored(w) then
				return
			end
			state.cursor_virtcol[curwin or 0] = nil
			state.resizing_request = true
			curbufnr = ctx.buf
			setup_layout()
		end,
	})

	api.nvim_create_autocmd("VimResized", {
		group = aug,
		callback = function()
			if not should_run() then
				return
			end
			state.resizing_request = true
			setup_layout()
		end,
	})

	api.nvim_create_autocmd("WinEnter", {
		group = aug,
		callback = function(ctx)
			if not should_run() then
				return
			end
			local w = api.nvim_get_current_win()
			if win.is_floating(w) or win.is_ignored(w) or (w == curwin and ctx.buf == curbufnr) then
				return
			end
			curwin = w
			state.resizing_request = true
			-- Defer to let BufWinEnter fire first when a new buffer is opening.
			vim.defer_fn(setup_layout, 10)
		end,
	})

	api.nvim_create_autocmd("WinNew", {
		group = aug,
		callback = function()
			new_window = true
		end,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = aug,
		callback = function(ctx)
			local id = tonumber(ctx.match)
			if id then
				state.cursor_virtcol[id] = nil
			end
		end,
	})
end

---Stop autowidth (clear autocmds; leave maximize-guard untouched).
function M.unregister()
	if state.augroup_autowidth then
		pcall(api.nvim_clear_autocmds, { group = state.augroup_autowidth })
	end
end

return M
