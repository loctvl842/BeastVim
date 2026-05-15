local View = require("beast.libs.view")
local config = require("beast.libs.explorer.config")
local render = require("beast.libs.explorer.render")
local state = require("beast.libs.explorer.state")
local sticky = require("beast.libs.explorer.sticky")

-- =============================================================================
-- VIEW
-- =============================================================================

---@class Beast.Explorer.View : Beast.View
---@field ns integer
local ExplorerView = View:extend(function(obj, ns)
	obj.ns = ns
end)

-- =============================================================================
-- MODULE
-- =============================================================================

local M = {}

--- Open a vertical split and return a new Beast.Explorer.View.
--- The split is placed on the side specified by config.cfg.side.
---@return Beast.Explorer.View
function M.create()
	local ns = vim.api.nvim_create_namespace("beastvim_explorer")

	-- Reuse the persisted buffer if still valid; otherwise create fresh.
	local has_buf = state.view ~= nil and state.view.buf ~= nil and vim.api.nvim_buf_is_valid(state.view.buf)
	local buf
	if has_buf then
		buf = state.view.buf
	else
		buf = Buffer.new("beast-explorer")
		vim.bo[buf].bufhidden = "hide" -- keep alive across window close
	end

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
	vim.wo[win].listchars = "tab:  ,nbsp:+"
	-- scrolloff is owned by sticky.refresh() — it tracks the float height so
	-- the cursor never lands in rows hidden under the sticky overlay.
	Util.wo(
		win,
		"winhighlight",
		"Normal:BeastExplorerNormal,EndOfBuffer:BeastExplorerEndOfBuffer,CursorLine:BeastExplorerCursorLine,WinSeparator:BeastExplorerWinSeparator,WinBar:BeastExplorerWinBar,WinBarNC:BeastExplorerWinBar"
	)

	return ExplorerView(buf, win, ns)
end

--- Flatten the tree, build lines+highlights, write to the buffer.
---@return Beast.Explorer.Node[]
function M.flush()
	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	local lines, hls = render.build(nodes)
	render.write(lines, hls)
	return nodes
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

	local root_short = vim.fn.fnamemodify(state.tree.root.path, ":~")
	pcall(vim.api.nvim_buf_set_name, state.view.buf, "Explorer: " .. root_short)

	M.flush()

	sticky.refresh()

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

	local nodes = M.flush()

	for i, node in ipairs(nodes) do
		if node.path == path then
			local line = i + 1 -- +1 for header
			pcall(vim.api.nvim_win_set_cursor, state.view.win, { line, 0 })
			vim.api.nvim_win_call(state.view.win, function()
				vim.cmd("normal! zz")
			end)
			return
		end
	end
end

--- Close only the window; the buffer is kept alive for fast reopen.
function M.close()
	if state.view and state.view.win and vim.api.nvim_win_is_valid(state.view.win) then
		vim.api.nvim_win_close(state.view.win, true)
		state.view.win = nil
	end
end

return M
