--- Binary min-heap with bounded capacity for top-K results.
---
--- Items with the highest score bubble to the top of the sorted output.
--- Internally this is a *min*-heap so the weakest item is at index 1 —
--- when the heap is full, a new item only enters if it beats the current
--- minimum, evicting the weakest in O(log K).
---
---@class Beast.Finder.TopK
---@field _data Beast.Finder.Item[]
---@field _size integer
---@field _capacity integer
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@param capacity integer maximum number of items to retain
---@return Beast.Finder.TopK
function M:new(capacity)
	return setmetatable({
		_data = {},
		_size = 0,
		_capacity = capacity,
	}, self)
end

-- -------------------------------------------------------------------------
-- Heap internals
-- -------------------------------------------------------------------------

---@private
function M:_swap(i, j)
	self._data[i], self._data[j] = self._data[j], self._data[i]
end

---@private
function M:_sift_up(i)
	local parent = math.floor(i / 2)
	while i > 1 and self._data[i].score < self._data[parent].score do
		self:_swap(i, parent)
		i = parent
		parent = math.floor(i / 2)
	end
end

---@private
function M:_sift_down(i)
	while true do
		local smallest = i
		local left = 2 * i
		local right = 2 * i + 1
		if left <= self._size and self._data[left].score < self._data[smallest].score then
			smallest = left
		end
		if right <= self._size and self._data[right].score < self._data[smallest].score then
			smallest = right
		end
		if smallest == i then
			break
		end
		self:_swap(i, smallest)
		i = smallest
	end
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

--- Push an item into the heap.
--- If under capacity, always inserts. If at capacity, only inserts when
--- the item beats the current minimum (evicts the minimum).
---@param item Beast.Finder.Item
---@return boolean inserted true if the item was added
function M:push(item)
	if self._size < self._capacity then
		self._size = self._size + 1
		self._data[self._size] = item
		self:_sift_up(self._size)
		return true
	end
	-- At capacity — only insert when item is strictly better than the weakest (root)
	if self._data[1].score < item.score then
		self._data[1] = item
		self:_sift_down(1)
		return true
	end
	return false
end

--- Return items sorted in descending score order (best first).
---@return Beast.Finder.Item[]
function M:sorted()
	local out = {}
	for i = 1, self._size do
		out[i] = self._data[i]
	end
	table.sort(out, function(a, b)
		return a.score > b.score
	end)
	return out
end

--- Get item at 1-based index from the internal (unsorted) heap.
--- Use `sorted()` for display-order access.
---@param idx integer
---@return Beast.Finder.Item|nil
function M:get(idx)
	return self._data[idx]
end

--- Number of items currently in the heap.
---@return integer
function M:count()
	return self._size
end

--- Remove all items.
function M:clear()
	self._data = {}
	self._size = 0
end

return M
