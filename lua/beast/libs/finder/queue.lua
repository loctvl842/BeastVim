---@class Beast.Finder.Queue
---@field _data any[]
---@field _first number
---@field _last number
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@return Beast.Finder.Queue
function M:new()
	return setmetatable({
		_data = {},
		_first = 0,
		_last = -1,
	}, self)
end

---@param value any
function M:push(value)
	self._last = self._last + 1
	self._data[self._last] = value
end

---@return any?
function M:pop()
	-- stylua: ignore
	if self._first > self._last then return nil end
	local value = self._data[self._first]
	self._data[self._first] = nil
	self._first = self._first + 1
	return value
end

---@return boolean
function M:empty()
	return self._first > self._last
end

---@return number
function M:size()
	return self._last - self._first + 1
end

function M:clear()
	self._data = {}
	self._first = 0
	self._last = -1
end

return M
