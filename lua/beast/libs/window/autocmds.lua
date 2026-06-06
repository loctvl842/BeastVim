---Autowidth autocmd wiring. Ported from windows.nvim/autowidth.lua.
local api = vim.api
local config = require("beast.libs.window.config")
local layout = require("beast.libs.window.layout")
local win = require("beast.libs.window.win")

local M = {}

---@type integer|nil
local augroup
local curwin, curbufnr
local new_window, resizing = false, false

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

local function should_run()
	return not vim.g.beast_window_disabled and config.autowidth.enable
end

local function setup_layout()
	if not curwin or not resizing then
		return
	end
	resizing = false
	local data = layout.autowidth(curwin)
	if vim.tbl_isempty(data) then
		if new_window then
			data = layout.equalize_wins()
		end
	elseif new_window then
		data = layout.merge(data, layout.equalize_wins())
	end
	new_window = false
	apply(data)
end

function M.register()
	if augroup then
		api.nvim_clear_autocmds({ group = augroup })
	end
	augroup = api.nvim_create_augroup("beast.window.autowidth", { clear = true })

	api.nvim_create_autocmd("BufWinEnter", {
		group = augroup,
		callback = function(ctx)
			if not should_run() then
				return
			end
			local w = api.nvim_get_current_win()
			if win.is_floating(w) then
				return
			end
			if new_window and win.is_ignored(w) then
				return
			end
			resizing = true
			curbufnr = ctx.buf
			setup_layout()
		end,
	})

	api.nvim_create_autocmd("VimResized", {
		group = augroup,
		callback = function()
			if not should_run() then
				return
			end
			resizing = true
			setup_layout()
		end,
	})

	api.nvim_create_autocmd("WinEnter", {
		group = augroup,
		callback = function(ctx)
			if not should_run() then
				return
			end
			local w = api.nvim_get_current_win()
			if win.is_floating(w) or win.is_ignored(w) or (w == curwin and ctx.buf == curbufnr) then
				return
			end
			curwin = w
			resizing = true
			-- Let BufWinEnter win the race when opening a new buffer.
			vim.defer_fn(setup_layout, 10)
		end,
	})

	api.nvim_create_autocmd("WinNew", {
		group = augroup,
		callback = function()
			new_window = true
		end,
	})

	api.nvim_create_autocmd({ "WinClosed", "TabLeave" }, {
		group = augroup,
		callback = function()
			require("beast.libs.window.animate").finish()
		end,
	})
end

function M.unregister()
	if augroup then
		pcall(api.nvim_clear_autocmds, { group = augroup })
	end
end

return M
