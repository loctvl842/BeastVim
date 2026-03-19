---@class Beast.Util
---@class Beast.Util.View
local M = {}

function M.wo(win, k, v)
	if vim.api.nvim_set_option_value then
		-- 0.9+ recommended
		vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
	else -- pre-0.9, still works
		vim.wo[win][k] = v
	end
end

return M
