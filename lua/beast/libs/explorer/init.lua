local Tree = require("beast.libs.explorer.tree")
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")
local keymaps = require("beast.libs.explorer.keymaps")
local autocmds = require("beast.libs.explorer.autocmds")
local sticky = require("beast.libs.explorer.sticky")

local M = setmetatable({}, {
	__call = function(self, cwd)
		return self.toggle(cwd)
	end,
})

---@param dir? string
local function ensure_explorer(dir)
	dir = dir and vim.fn.fnamemodify(dir, ":p"):gsub("/$", "") or vim.fn.getcwd()
	if not state.tree or state.tree.root.path ~= dir then
		state.tree = Tree(dir)
	end
	if not state.view or not state.view:is_valid() then
		state.view = ui.create()
		keymaps.mount()
		autocmds.mount()
		sticky.mount()
	end
end

--- Calls `on_done()` after the render (after the async git fetch when enabled).
---@param dir? string
function M.open(dir)
	-- This is to go back to the previous window after selecting a file
	state.source_win = vim.fn.win_getid(vim.fn.winnr())
	if state.view and state.view:is_valid() and state.tree.root.path == dir then
		pcall(vim.api.nvim_set_current_win, state.view.win)
		return
	end
	local file = vim.api.nvim_buf_get_name(0)
	local has_file = file ~= "" and vim.fn.filereadable(file) == 1
	ensure_explorer(dir)
	if has_file then
		local root_path = state.tree.root.path
		local file_norm = vim.fn.fnamemodify(file, ":p"):gsub("/$", "")
		local file_dir = vim.fn.fnamemodify(file_norm, ":h")
		-- Re-root the tree when the current file lives outside the tree root
		if file_norm ~= root_path and file_norm:sub(1, #root_path + 1) ~= root_path .. "/" then
			if vim.fn.isdirectory(file_dir) == 1 then
				ensure_explorer(file_dir)
			else
				has_file = false
			end
		end
		state.tree:open(file)
	end

  -- stylua: ignore
  local on_done = has_file and function() ui.focus_path(file) end or nil
	ui.render(on_done)
end

function M.close()
	sticky.close()
	ui.close()
	local prev = vim.fn.win_getid(vim.fn.winnr("#"))
	pcall(vim.api.nvim_set_current_win, prev)
end

---@param cwd? string  used only when there is no current file on first open
function M.toggle(cwd)
	if state.view and state.view:is_valid() then
		M.close()
		return
	end

	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or vim.fn.getcwd()
	M.open(cwd)
end

function M.setup(opts)
	require("beast.libs.explorer.highlights")
	config.setup(opts)
	M.replace_netrw()
end

--- Disable netrw and open this explorer whenever a directory buffer is entered.
--- Handles `nvim .`, `nvim /some/dir`, and `:e /some/dir`.
--- Creates an empty companion window so the explorer keeps its configured width.
function M.replace_netrw()
	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1
	pcall(vim.api.nvim_del_augroup_by_name, "FileExplorer")

	local group = vim.api.nvim_create_augroup("BeastExplorerReplace", { clear = true })

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(ev)
			-- stylua: ignore
			if ev.file == "" or vim.fn.isdirectory(ev.file) ~= 1 then return end
			local dir = vim.fn.fnamemodify(ev.file, ":p"):gsub("/$", "")
			-- Replace the directory buffer with an empty scratch buffer in this window,
			-- so the window stays open as the companion editing area.
			local empty = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_win_set_buf(0, empty)
			pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
			vim.schedule(function()
				M.open(dir)
			end)
		end,
	})
end

return M
