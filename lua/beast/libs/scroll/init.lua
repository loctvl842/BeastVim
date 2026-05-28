local State = require("beast.libs.scroll.state")
local config = require("beast.libs.scroll.config")

local uv = vim.uv or vim.loop

local SCROLL_DOWN = vim.api.nvim_replace_termcodes("<C-e>", true, true, true)
local SCROLL_UP = vim.api.nvim_replace_termcodes("<C-y>", true, true, true)

---@type table<integer, Beast.Scroll.State>
local states = {}
local enabled = false
local mouse_scrolling = false
local augroup ---@type integer|nil
local on_key_ns ---@type integer|nil

---@type table<Beast.Scroll.Easing, fun(t:number):number>
local EASINGS = {
	linear = function(t)
		return t
	end,
	ease_in = function(t)
		return t * t
	end,
	ease_out = function(t)
		return 1 - (1 - t) * (1 - t)
	end,
	ease_in_out = function(t)
		if t < 0.5 then
			return 2 * t * t
		end
		return 1 - (-2 * t + 2) ^ 2 / 2
	end,
}

local M = {}

---@param win integer
---@param current vim.fn.winsaveview.ret
---@param target vim.fn.winsaveview.ret
---@return integer
local function scroll_lines(win, current, target)
	local from, to = current, target
	if to.topline < from.topline then
		from, to = to, from
	end
	if from.topline == to.topline then
		return math.abs(from.topfill - to.topfill)
	end
	local start_row, end_row, offset = from.topline - 1, to.topline - 1, 0
	if from.topfill > 0 then
		start_row = start_row + 1
		offset = from.topfill + 1
	end
	if to.topfill > 0 then
		offset = offset - to.topfill
	end
	if vim.api.nvim_win_text_height then
		local h = vim.api.nvim_win_text_height(win, { start_row = start_row, end_row = end_row })
		return math.max(0, h.all + offset - 1)
	end
	return end_row - start_row + offset
end

---@param buf integer
---@return boolean
local function buf_disabled(buf)
	return vim.g.beast_scroll_disabled == true or vim.b[buf].beast_scroll_disabled == true
end

---@param win integer
local function reset_win(win)
	local state = states[win]
	if state then
		state:stop()
		states[win] = nil
	end
end

---@param buf integer
local function reset_buf(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		reset_win(win)
	end
end

--- Decide whether to start a new animation toward state.view.
---@param win integer
function M.check(win)
	if not enabled or vim.o.paste then
		return
	end
	if vim.fn.reg_executing() ~= "" or vim.fn.reg_recording() ~= "" then
		return
	end

	local state = State.get(win, states, config.filter)
	if not state then
		return
	end
	if buf_disabled(state.buf) then
		return
	end

	-- only animate the focused window when scrollbind is on
	if vim.wo[state.win].scrollbind and vim.api.nvim_get_current_win() ~= state.win then
		state:stop()
		state.current = vim.deepcopy(state.view)
		return
	end

	-- mouse-wheel: let the terminal handle smoothness
	if mouse_scrolling then
		mouse_scrolling = false
		state:stop()
		state.current = vim.deepcopy(state.view)
		return
	end

	-- tiny deltas: skip to avoid jitter
	if math.abs(state.view.topline - state.current.topline) <= 1 then
		state.current = vim.deepcopy(state.view)
		return
	end

	state.target = vim.deepcopy(state.view)
	state:stop()
	state:wo({ scrolloff = 0, virtualedit = "all" })

	local now = uv.hrtime()
	local since_last_ms = (now - state.last_ns) / 1e6
	local is_repeat = state.last_ns ~= 0 and since_last_ms <= config.animate_repeat.delay_ms
	state.last_ns = now

	local profile = is_repeat and config.animate_repeat or config.animate
	local easing = EASINGS[profile.easing] or EASINGS.linear

	-- snap back to `current` so the user sees the animation play out from there
	vim.api.nvim_win_call(state.win, function()
		vim.fn.winrestview(state.current)
	end)

	local scrolls = scroll_lines(state.win, state.current, state.target)
	if scrolls == 0 then
		vim.api.nvim_win_call(state.win, function()
			vim.fn.winrestview(state.target)
		end)
		state:stop()
		return
	end

	local down = state.target.topline > state.current.topline
		or (state.target.topline == state.current.topline and state.target.topfill < state.current.topfill)
	local key = down and SCROLL_DOWN or SCROLL_UP

	local ctx = {
		state = state,
		start_ns = now,
		total_ms = math.max(1, profile.total_ms),
		scrolls = scrolls,
		key = key,
		easing = easing,
		scrolled = 0,
	}
	local step_ms = math.max(1, profile.step_ms)

	state.timer = assert(uv.new_timer())
	state.timer:start(step_ms, step_ms, vim.schedule_wrap(function() M._tick(ctx) end))
end

--- One animation tick. Extracted from M.check so the timer body stays small.
---@private
function M._tick(ctx)
	local state = ctx.state
	if not state:valid(state.buf) or states[state.win] ~= state then
		state:stop()
		return
	end

	local elapsed_ms = (uv.hrtime() - ctx.start_ns) / 1e6
	local t = math.min(1, elapsed_ms / ctx.total_ms)
	local target_scrolled = math.floor(ctx.scrolls * ctx.easing(t))
	local delta = target_scrolled - ctx.scrolled
	if delta > 0 then
		ctx.scrolled = target_scrolled
		vim.api.nvim_win_call(state.win, function()
			vim.cmd(("keepjumps normal! %d%s"):format(delta, ctx.key))
		end)
	end

	state:update_current()

	if t >= 1 then
		vim.api.nvim_win_call(state.win, function()
			vim.fn.winrestview(state.target)
		end)
		state:update_current()
		state:stop()
	end
end

local function ensure_autocmds()
	if augroup then
		return
	end
	augroup = vim.api.nvim_create_augroup("BeastScroll", { clear = true })

	vim.api.nvim_create_autocmd("WinScrolled", {
		group = augroup,
		callback = function()
			for win, changes in pairs(vim.v.event) do
				win = tonumber(win)
				if win and type(changes) == "table" and changes.topline and changes.topline ~= 0 then
					M.check(win)
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = augroup,
		callback = vim.schedule_wrap(function(ev)
			for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
				if states[win] then
					states[win]:update_current()
				end
			end
		end),
	})

	vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "TextChangedI" }, {
		group = augroup,
		callback = function(ev)
			reset_buf(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(ev)
			reset_win(tonumber(ev.match) or -1)
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = augroup,
		callback = function(ev)
			if (ev.file == "/" or ev.file == "?") and vim.o.incsearch then
				reset_buf(vim.api.nvim_get_current_buf())
			end
		end,
	})
end

local function ensure_on_key()
	if on_key_ns then
		return
	end
	on_key_ns = vim.api.nvim_create_namespace("BeastScrollOnKey")
	local WHEEL_DOWN = vim.api.nvim_replace_termcodes("<ScrollWheelDown>", true, true, true)
	local WHEEL_UP = vim.api.nvim_replace_termcodes("<ScrollWheelUp>", true, true, true)
	vim.on_key(function(key)
		if key == WHEEL_DOWN or key == WHEEL_UP then
			mouse_scrolling = true
		end
	end, on_key_ns)
end

function M.enable()
	if enabled then
		return
	end
	enabled = true
	states = {}
	ensure_autocmds()
	ensure_on_key()
end

function M.disable()
	if not enabled then
		return
	end
	enabled = false
	for _, state in pairs(states) do
		state:stop()
	end
	states = {}
	if augroup then
		vim.api.nvim_del_augroup_by_id(augroup)
		augroup = nil
	end
	if on_key_ns then
		vim.on_key(nil, on_key_ns)
		on_key_ns = nil
	end
end

function M.toggle()
	if enabled then
		M.disable()
	else
		M.enable()
	end
end

---@return boolean
function M.is_enabled()
	return enabled
end

---@param opts? Beast.Scroll.Config
function M.setup(opts)
	config.setup(opts)
	if config.enabled then
		M.enable()
	end
end

return M
