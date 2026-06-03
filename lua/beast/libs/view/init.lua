---@class Beast.View
---@field buf integer
---@field win integer
local M = {}
M.__index = M

-- Namespace metatable: lets callers do `Beast.View.buf` / `Beast.View.win` to
-- get the submodules lazily. Attached to M itself, NOT to its instance __index
-- chain, so `instance.buf` returns nil (not the submodule) when unset.
setmetatable(M, {
	__call = function(t, ...)
		return t:new(...)
	end,
	__index = function(_, k)
		local ok, mod = pcall(require, "beast.libs.view." .. k)
		if ok then
			return mod
		end
	end,
})

---@param buf integer
---@param win integer
---@return Beast.View
function M:new(buf, win)
	-- Store `false` rather than `nil` for missing buf/win so subsequent reads
	-- of `instance.buf`/`.win` do NOT cascade through the namespace metatable
	-- to the buf/win submodules (which would return tables instead of falsy).
	return setmetatable({ buf = buf or false, win = win or false }, { __index = M })
end

---@return boolean
function M:is_valid()
	local buf = rawget(self, "buf")
	local win = rawget(self, "win")
	if not buf or not win then
		return false
	end
	return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)
end

function M:close()
	local win = rawget(self, "win")
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	-- Use `false` (not `nil`) so subsequent reads of `instance.buf`/`.win` do
	-- NOT cascade through the namespace metatable to the buf/win submodules.
	self.buf = false
	self.win = false
end

---@return table
function M:extend(init)
	local parent = self

	local cls = setmetatable({}, {
		__index = parent,
		__call = function(t, ...)
			return t:new(...)
		end,
	})
	cls.__index = cls

	function cls:new(buf, win, ...)
		local obj = setmetatable({
			buf = buf or false,
			win = win or false,
		}, { __index = cls })

		if init then
			init(obj, ...)
		end

		return obj
	end

	return cls
end

return M
