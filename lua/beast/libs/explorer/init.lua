local Tree = require("beast.libs.explorer.tree")
local autocmds = require("beast.libs.explorer.autocmds")
local config = require("beast.libs.explorer.config")
local git = require("beast.libs.explorer.git")
local keymaps = require("beast.libs.explorer.keymaps")
local state = require("beast.libs.explorer.state")
local sticky = require("beast.libs.explorer.sticky")
local ui = require("beast.libs.explorer.ui")
local watch = require("beast.libs.explorer.watch")

local M = setmetatable({}, {
	__call = function(self, cwd)
		return self.toggle(cwd)
	end,
})

---@param dir? string
local function ensure_explorer(dir)
	dir = dir and vim.fn.fnamemodify(dir, ":p"):gsub("/$", "") or Util.root()
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
	state.source_win = Util.find_normal_win()
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
	-- Force full git refresh on open so badges always appear.
	-- Without this, a stale cache from a previous close→reopen cycle
	-- would skip apply/propagate and leave new tree nodes badge-less.
	git.invalidate_cache()
	git.refresh(function()
		ui.flush()
		sticky.refresh()
	end)
end

function M.close()
	git.stop()
	watch.stop_all()
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

	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or Util.root()
	M.open(cwd)
end

function M.setup(opts)
	require("beast.libs.explorer.highlights")
	config.setup(opts)
end

return M
