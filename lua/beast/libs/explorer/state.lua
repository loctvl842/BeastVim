---@class Beast.Explorer.Clipboard
---@field paths string[]
---@field mode "copy"|"cut"

---@class Beast.Explorer.State
---@field tree Beast.Explorer.Tree|nil
---@field view Beast.Explorer.View|nil
---@field sticky Beast.Explorer.StickyView|nil
---@field augroup integer|nil
---@field saved_win_opts table<string,any>|nil
---@field source_win integer|nil
---@field clipboard Beast.Explorer.Clipboard|nil
local M = {
	tree = nil,
	view = nil,
	sticky = nil,
	augroup = nil,
	saved_win_opts = nil,
	source_win = nil,
	clipboard = nil,
}

-- ================================
-- Methods
-- ================================

function M.is_valid()
	return M.tree ~= nil and M.view ~= nil and M.view:is_valid()
end

--- Return the node under the cursor.
--- Subtracts 1 to skip the root header line (line 1 in the buffer).
---@param opts Beast.Explorer.FlatOpts
---@return Beast.Explorer.Node?
function M.current_node(opts)
  -- stylua: ignore
  if not M.tree or not M.view or not M.view:is_valid() then return end

	local ok, pos = pcall(vim.api.nvim_win_get_cursor, M.view.win)
  -- stylua: ignore
  if pos[1] == 1 then return M.tree.root end
	local nodes = M.tree:flat(opts)

  -- stylua: ignore
  if not ok then return end

  local shift = 1 -- post[1] is shift by 1 line (due to root header)
	return nodes[pos[1] - shift] -- row 1 = header, row 2 = nodes[1]
end

function M.reset()
	M.tree = nil
	M.view = nil
	M.sticky = nil
	M.augroup = nil
end

return M
