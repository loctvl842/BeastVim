---@class Beast.Input.History
---@field entries string[]
---@field pos integer   -- 0 = "current" (draft), 1..n = historical entries
---@field draft string
---@field filter? fun(value: string): boolean
local History = {}
History.__index = History

---@param opts? { filter?: fun(value: string): boolean }
---@return Beast.Input.History
function History:new(opts)
	opts = opts or {}
	return setmetatable({
		entries = {},
		pos = 0,
		draft = "",
		filter = opts.filter,
	}, self)
end

---@param value string
function History:record(value)
	if self.filter and not self.filter(value) then
		return
	end
	-- skip duplicate of the most recent entry
	if self.entries[#self.entries] == value then
		return
	end
	table.insert(self.entries, value)
	self.pos = 0
	self.draft = ""
end

---@return boolean
function History:is_current()
	return self.pos == 0
end

---Navigate backward. Saves current text as draft when leaving pos=0.
---@param current_text string  text currently in the input buffer
---@return string
function History:prev(current_text)
	if self.pos == 0 then
		self.draft = current_text or ""
	end
	if self.pos < #self.entries then
		self.pos = self.pos + 1
	end
	if self.pos == 0 then
		return self.draft
	end
	return self.entries[#self.entries - self.pos + 1]
end

---Navigate forward. Returns draft text when reaching pos=0.
---@return string
function History:next()
	if self.pos > 0 then
		self.pos = self.pos - 1
	end
	if self.pos == 0 then
		return self.draft
	end
	return self.entries[#self.entries - self.pos + 1]
end

local M = {}
M.History = History
return M
