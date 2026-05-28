---@class Beast.Scroll.State
---@field win integer
---@field buf integer
---@field changedtick integer            buf tick when current animation started
---@field view vim.fn.winsaveview.ret    latest observed view (post-scroll target)
---@field current vim.fn.winsaveview.ret view the animation currently sits at
---@field target vim.fn.winsaveview.ret  view the animation is heading toward
---@field last_ns integer                vim.uv.hrtime of last animation start
---@field timer? uv.uv_timer_t           active animation timer, nil if idle
---@field _wo table<string, any>         backup of window options modified during animation
local State = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

State.__index = State

---@param win integer
---@return Beast.Scroll.State|nil
function State.get(win, states, filter)
	if not vim.api.nvim_win_is_valid(win) then
		states[win] = nil
		return nil
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not (filter and filter(buf)) then
		if states[win] then
			states[win]:stop()
			states[win] = nil
		end
		return nil
	end

	local view = vim.api.nvim_win_call(win, vim.fn.winsaveview) ---@type vim.fn.winsaveview.ret

	local ret = states[win]
	if not (ret and ret:valid(buf)) then
		if ret then
			ret:stop()
		end
		ret = State:new(win, buf, view)
		states[win] = ret
	end
	ret.view = view
	return ret
end

---@param win integer
---@param buf integer
---@param view vim.fn.winsaveview.ret
---@return Beast.Scroll.State
function State:new(win, buf, view)
	return setmetatable({
		win = win,
		buf = buf,
		changedtick = vim.api.nvim_buf_get_changedtick(buf),
		view = vim.deepcopy(view),
		current = vim.deepcopy(view),
		target = vim.deepcopy(view),
		last_ns = 0,
		timer = nil,
		_wo = {},
	}, self)
end

---@param buf integer
---@return boolean
function State:valid(buf)
	return vim.api.nvim_win_is_valid(self.win)
		and vim.api.nvim_buf_is_valid(self.buf)
		and self.buf == buf
		and vim.api.nvim_win_get_buf(self.win) == self.buf
		and vim.api.nvim_buf_get_changedtick(self.buf) == self.changedtick
end

--- Snapshot + apply window options, or restore them when called with no args.
---@param opts? table<string, any>
function State:wo(opts)
	if opts then
		for k, v in pairs(opts) do
			if self._wo[k] == nil then
				self._wo[k] = vim.wo[self.win][k]
			end
			vim.wo[self.win][k] = v
		end
		return
	end
	if vim.api.nvim_win_is_valid(self.win) then
		for k, v in pairs(self._wo) do
			vim.wo[self.win][k] = v
		end
	end
	self._wo = {}
end

--- Refresh `current` from the live window view (called each tick + on CursorMoved).
function State:update_current()
	if vim.api.nvim_win_is_valid(self.win) then
		self.current = vim.api.nvim_win_call(self.win, vim.fn.winsaveview)
	end
end

--- Stop any running animation and restore window options.
function State:stop()
	if self.timer then
		self.timer:stop()
		if not self.timer:is_closing() then
			self.timer:close()
		end
		self.timer = nil
	end
	self:wo()
end

return State
