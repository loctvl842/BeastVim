local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

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

-- Determine if window is floating
local function is_floating(win)
	local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
	return ok and cfg and (cfg.relative or "") ~= ""
end

-- Collect modified, listed buffers
local function get_modified_buffers()
	local mods = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified then
			local name = vim.api.nvim_buf_get_name(buf)
			mods[name ~= "" and name or ("[No Name]#" .. tostring(buf))] = { buf = buf, modified = true }
		end
	end
	return mods
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

	state.augroup = vim.api.nvim_create_augroup("BeastExplorerUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = state.augroup,
		callback = function()
			refresh_cursor()
		end,
	})

	-- Sync explorer cursor to the active file whenever a non-explorer buffer is entered.
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.augroup,
		callback = function()
			-- stylua: ignore
			if not (state.view and state.view:is_valid() and state.tree) then return end
			local win = vim.api.nvim_get_current_win()
			-- stylua: ignore
			if win == state.view.win then return end
			local path = vim.api.nvim_buf_get_name(0)
			-- stylua: ignore
			if path == "" or vim.fn.filereadable(path) ~= 1 then return end

			-- Gate: only react when the buffer path lives inside the explorer root
			local root = state.tree.root.path
			if not (path == root or path:sub(1, #root + 1) == (root .. "/")) then
				return
			end

			-- Skip if the explorer already focuses this exact path
			local cur = state.current_node({ show_hidden = config.show_hidden })
			if cur and cur.path == path then
				return
			end

			-- Move focus; only re-render if the tree actually changed (e.g., expansion)
			local before = state.tree.version
			local ok = pcall(ui.focus_path, path)
			if not ok then
				return
			end
			if state.tree.version ~= before then
				ui.render()
			end
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

	-- Close Neovim when explorer is the last remaining non-floating window.
	-- If any buffer is modified, reveal it instead of quitting.
	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		callback = function(args)
			vim.schedule(function()
				-- stylua: ignore
				if not (state.view and state.view:is_valid()) then return end

				local closing_win = tonumber(args.match)
				local wins = vim.api.nvim_tabpage_list_wins(0)
				local others = {}
				for _, w in ipairs(wins) do
					if w ~= closing_win and not is_floating(w) then
						others[#others + 1] = w
					end
				end

				if #others ~= 1 then
					return
				end

				local remaining = others[1]
				if not vim.api.nvim_win_is_valid(remaining) then
					return
				end
				local buf = vim.api.nvim_win_get_buf(remaining)
				if vim.bo[buf].filetype ~= "beast-explorer" then
					return
				end

				-- If any modified buffers exist, open one instead of quitting
				local mod = get_modified_buffers()
				for filename, info in pairs(mod) do
					if info.modified then
						local buf_name = filename
						local message = "Cannot close because one of the files is modified. Please save or discard changes."
						if vim.startswith(filename, "[No Name]#") then
							buf_name = string.sub(filename, 11)
							message = "Cannot close because an unnamed buffer is modified. Please save or discard this file."
						end
						vim.notify(message, vim.log.levels.WARN)
						local split_cmd = (config.side == "left") and "rightbelow vertical split" or "topleft vertical split"
						pcall(function(...)
							vim.cmd(...)
						end, split_cmd)
						pcall(vim.api.nvim_win_set_width, 0, config.width or 40)
						pcall(function(...)
							vim.cmd(...)
						end, "b " .. buf_name)
						return
					end
				end

				-- Allow VimLeavePre to run by scheduling the quit
				vim.cmd("q!")
			end)
		end,
	})

	vim.api.nvim_create_autocmd("WinScrolled", {
		group = state.augroup,
		callback = function()
			-- stylua: ignore
			if not (state.view and state.view:is_valid()) then return end
			local exp_win = tostring(state.view.win)
			-- stylua: ignore
			if not (vim.v.event and vim.v.event[exp_win]) then return end

			local wininfo = vim.fn.getwininfo(state.view.win)
			local topline = (wininfo[1] or {}).topline or 1
			local skip_rerender = (topline == 1 and not state.anchored) or (topline > 1 and state.anchored)
      -- stylua: ignore
      if skip_rerender then return end
			ui.render()
		end,
	})

	refresh_cursor()
end

return M
