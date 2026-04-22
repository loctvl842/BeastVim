---@class Beast.Toast.State
---@field views Beast.Toast.View[]   index 1 = topmost (oldest), #views = bottommost (newest)
---@field queue Beast.Toast.Record[]
---@field next_id integer
---@field draining boolean
local State = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

State.__index = State

---@return Beast.Toast.State
function State:new()
	return setmetatable({
		views = {},
		queue = {},
		next_id = 1,
		draining = false,
	}, self)
end

---@param id integer
---@return integer|nil idx
---@return Beast.Toast.View|nil view
function State:find(id)
	for i, v in ipairs(self.views) do
		if v.record.id == id then
			return i, v
		end
	end
end

return State
