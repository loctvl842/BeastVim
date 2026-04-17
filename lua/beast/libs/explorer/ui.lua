---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local View = require("beast.libs.view")
local render = require("beast.libs.explorer.render")

-- =============================================================================
-- VIEW
-- =============================================================================

---@class Beast.Explorer.View : Beast.View
---@field ns integer
---@field cwd string
local ExplorerView = View:extend(function(obj, ns, cwd)
	obj.ns = ns
	obj.cwd = cwd
end)

--- Set the buffer name to a short version of cwd
---@param cwd? string
function ExplorerView:set_title(cwd)
	if not self:is_valid() then
		return
	end

	cwd = cwd or self.cwd

	local short = vim.fn.fnamemodify(cwd, ":~")
	pcall(vim.api.nvim_buf_set_name, self.buf, "Explorer: " .. short)
end

-- =============================================================================
-- UTILS
-- =============================================================================

---@param filetype string
---@return integer
local function create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

-- =============================================================================
-- MODULE
-- =============================================================================

local M = {}

--- Open a vertical split and return a new Beast.Explorer.View.
--- The split is placed on the side specified by config.cfg.side.
---@param cwd string  absolute path to root directory
---@return Beast.Explorer.View
function M.create(cwd)
	local ns = vim.api.nvim_create_namespace("beastvim_explorer")
	local buf = create_scratch_buf("beast-explorer")

	-- Snapshot the real editing window's options before splitting, so we can
	-- restore them on any new window created later (vsplit from explorer).
	local src = vim.api.nvim_get_current_win()
	state.saved_win_opts = {
		number = vim.wo[src].number,
		relativenumber = vim.wo[src].relativenumber,
		signcolumn = vim.wo[src].signcolumn,
		foldcolumn = vim.wo[src].foldcolumn,
		cursorline = vim.wo[src].cursorline,
		wrap = vim.wo[src].wrap,
		statusline = vim.wo[src].statusline,
	}

	local side = config.side == "right" and "botright" or (config.side == "left" and "topleft" or error("invalid side"))
	vim.cmd(side .. " " .. config.width .. "vsplit")

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Window-local options
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winfixwidth = true
	vim.wo[win].statusline = "Explorer"
	vim.wo[win].listchars = "tab:  ,nbsp:+"

	return ExplorerView(buf, win, ns, cwd)
end

--- Write `nodes` into `view`'s buffer and apply highlight decorations.
--- Line 1 is always the root header; nodes occupy lines 2..N.
--- Safe to call even when the window has been closed externally.
--- Calls `on_done()` after the render (after the async git fetch when enabled).
---@param on_done? fun()
function M.render(on_done)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end
  -- stylua: ignore
  if not state.tree then return end

	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	local lines, hls = render.build(nodes)
	render.write(lines, hls)

  -- stylua: ignore
	if on_done then on_done() end
end

--- Move the cursor to the row that matches `path` in `nodes`.
--- Adds 1 to account for the root header occupying line 1.
---@param path  string
function M.focus_path(path)
  -- stylua: ignore
	if not state.view or not state.view:is_valid() then return end

	state.tree:open(path)
	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	for i, node in ipairs(nodes) do
		if node.path == path then
			pcall(vim.api.nvim_win_set_cursor, state.view.win, { i + 1, 0 }) -- +1 for header
			return
		end
	end
	error("Path not found in explorer: " .. path)
end

function M.close()
	if state.view and state.view:is_valid() then
		state.view:close()
	end
end

return M
