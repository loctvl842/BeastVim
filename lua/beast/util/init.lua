---@class Beast.Util
---@field root beast.util.root
---@field colors beast.util.colors
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.util." .. k)
		return mod
	end,
})

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

-- High-resolution timer helper
---@return integer ns Nanoseconds
function M.hrtime()
	local uv = vim.uv or vim.loop
	if uv and uv.hrtime then
		return uv.hrtime()
	end
	-- Fallback using reltime (seconds as float)
	return math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e9)
end

return M
