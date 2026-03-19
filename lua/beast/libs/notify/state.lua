---@class Beast.Notify.State
---@field views Beast.Notify.View[]  index 1 = topmost (oldest), #views = bottommost (newest)
---@field next_id integer
local State = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

State.__index = State

---@return Beast.Notify.State
function State:new()
	return setmetatable({
		views = {},
		next_id = 1,
	}, self)
end

---@param id integer
---@return integer|nil idx
---@return Beast.Notify.View|nil view
function State:find(id)
	for i, v in ipairs(self.views) do
		if v.record.id == id then
			return i, v
		end
	end
end

return State
