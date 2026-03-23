---@class Beast.Explorer.State
---@field tree Beast.Explorer.Tree|nil
---@field view Beast.Explorer.View|nil
---@field augroup integer|nil
local M = {
	tree = nil,
	view = nil,
	augroup = nil,
}

-- ================================
-- Methods
-- ================================

function M.is_valid()
	return M.tree ~= nil and M.view ~= nil and M.view:is_valid()
end

function M.reset()
	M.tree = nil
	M.view = nil
	M.augroup = nil
end

return M
