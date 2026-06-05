---Split-window resize animator built on `animate.tween`.
---
---Public surface:
---   animate.run(data, on_done)
---     Tweens widths/heights from current values to those in `data` over
---     config.animation.duration ms. Single-flight per-tab: if a new run() is
---     issued mid-animation, the current animation is treated as the new
---     initial state and the tween is restarted toward the new target
---     (avoids the visible "jump-back" that aborting would produce).
---
---@class Beast.Window.AnimationHandle
---@field running boolean
---@field cancel fun()

local animate_core = require("beast.libs.animate")
local config = require("beast.libs.window.config")
local state = require("beast.libs.window.state")
local win = require("beast.libs.window.win")

local M = {}

local function round(n)
	return math.floor(n + 0.5)
end

---@param easing string|fun(t:number):number
---@return fun(t:number):number
local function resolve_easing(easing)
	if type(easing) == "function" then
		return easing
	end
	return animate_core.easings[easing] or animate_core.easings.ease_in_out
end

---Capture initial size + delta per entry. Skips entries whose window has died.
---@param data Beast.Window.WinResizeData[]
---@return table[]
local function capture(data)
	local out = {}
	for _, d in ipairs(data) do
		if win.is_valid(d.winid) then
			local entry = { winid = d.winid }
			if d.width then
				entry.w0 = win.get_width(d.winid)
				entry.dw = d.width - entry.w0
			end
			if d.height then
				entry.h0 = win.get_height(d.winid)
				entry.dh = d.height - entry.h0
			end
			out[#out + 1] = entry
		end
	end
	return out
end

---@param data Beast.Window.WinResizeData[]
---@param on_done? fun()
function M.run(data, on_done)
	if vim.tbl_isempty(data) then
		if on_done then
			on_done()
		end
		return
	end

	-- Single-flight: cancel any in-flight animation. The old tween's next
	-- callback returns false (running=false) so it stops without snapping to its
	-- own target. We then start a new tween whose initials are CURRENT widths,
	-- producing a smooth re-direction toward the new goal.
	if state.animation and state.animation.running then
		state.animation.running = false
		state.animation = nil
	end

	local handle = {
		running = true,
		entries = capture(data),
		on_done = on_done,
	}
	state.animation = handle

	local ease = resolve_easing(config.animation.easing)
	local duration = config.animation.duration or 150

	animate_core.tween(duration, function(t)
		if not handle.running then
			return false
		end
		local eased = ease(t)
		for _, e in ipairs(handle.entries) do
			if win.is_valid(e.winid) then
				if e.dw then
					win.set_width(e.winid, e.w0 + round(eased * e.dw))
				end
				if e.dh then
					win.set_height(e.winid, e.h0 + round(eased * e.dh))
				end
			end
		end
	end, function()
		-- Snap to final values (avoids 1-cell rounding leftovers).
		for _, e in ipairs(handle.entries) do
			if win.is_valid(e.winid) then
				if e.dw then
					win.set_width(e.winid, e.w0 + e.dw)
				end
				if e.dh then
					win.set_height(e.winid, e.h0 + e.dh)
				end
			end
		end
		handle.running = false
		if state.animation == handle then
			state.animation = nil
		end
		if handle.on_done then
			handle.on_done()
		end
	end)
end

---Force-finish any running animation (e.g. on TabLeave / WinClosed of the leader window).
function M.finish()
	if state.animation then
		state.animation.running = false
		state.animation = nil
	end
end

return M
