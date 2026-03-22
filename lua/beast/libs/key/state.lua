---@class Beast.Key.UI.State
local M = {
	main = nil, ---@type Beast.Key.UI.MainView?
	action = nil, ---@type Beast.Key.UI.ActionView?
	augroup = -1,
	closed = false,
	lines = nil, ---@type Beast.Key.API.Line[]?
}

-- ================================
-- Methods
-- ================================

function M.is_valid()
	return not M.closed and M.main and M.main:is_valid() and M.action and M.action:is_valid()
end

function M.reset()
	M.main = nil
	M.action = nil
	M.augroup = -1
	M.closed = false
	M.lines = nil
end

return M
