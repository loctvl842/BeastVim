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

---@param filetype string
---@return integer
function M.create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

return M
