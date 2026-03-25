---@class Beast.Explorer.State
---@field tree Beast.Explorer.Tree|nil
---@field view Beast.Explorer.View|nil
---@field augroup integer|nil
---@field saved_win_opts table<string,any>|nil
---@field source_win integer|nil
local M = {
	tree = nil,
	view = nil,
	augroup = nil,
	saved_win_opts = nil,
	source_win = nil,
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

	local nodes = M.tree:flat(opts)
	local ok, pos = pcall(vim.api.nvim_win_get_cursor, M.view.win)

  -- stylua: ignore
  if not ok then return end

	return nodes[pos[1] - 1] -- row 1 = header, row 2 = nodes[1]
end

function M.reset()
	M.tree = nil
	M.view = nil
	M.augroup = nil
end

return M
