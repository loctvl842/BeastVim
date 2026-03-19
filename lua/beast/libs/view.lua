---@class Beast.View
---@field buf integer
---@field win integer
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@param buf integer
---@param win integer
---@return Beast.View
function M:new(buf, win)
	return setmetatable({ buf = buf, win = win }, self)
end

---@return boolean
function M:is_valid()
	return self.buf ~= nil
		and self.win ~= nil
		and vim.api.nvim_buf_is_valid(self.buf)
		and vim.api.nvim_win_is_valid(self.win)
end

function M:close()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end
	self.buf = nil
	self.win = nil
end

---@return table
function M:extend(init)
	local cls = setmetatable({}, {
		__index = self,
		__call = function(t, ...)
			return t:new(...)
		end,
	})
	cls.__index = cls

	if init then
		function cls:new(buf, win, ...)
			---@type Beast.View
			local obj = M:new(buf, win)
			init(obj, ...)
			return obj
		end
	end

	return cls
end

return M
