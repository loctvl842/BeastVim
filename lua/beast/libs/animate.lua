local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "animate", description = "Animation primitives (lerp, easing, frame loop) for UI tweens" }

local FPS = 30
local FRAME_MS = math.floor(1000 / FPS)

-- =============================================================================
-- MATH
-- =============================================================================

---@param from number
---@param to number
---@param t number
---@return number
local function lerp(from, to, t)
	return from + (to - from) * t
end

---@param t number
---@return number
local function ease_out(t)
	return 1 - (1 - t) * (1 - t)
end

---@param t number
---@return number
local function ease_in(t)
	return t * t
end

---@param t number
---@return number
local function ease_in_out(t)
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - (-2 * t + 2) ^ 2 / 2
end

---@param t number
---@return number
local function linear(t)
	return t
end

---@param value number
---@return integer
local function round(value)
	return math.floor(value + 0.5)
end

---@type table<string, fun(t:number):number>
M.easings = {
	linear = linear,
	ease_in = ease_in,
	ease_out = ease_out,
	ease_in_out = ease_in_out,
}

-- =============================================================================
-- TYPES
-- =============================================================================

---@class Beast.Animate.State
---@field row? integer
---@field col? integer
---@field width? integer
---@field height? integer
---@field blend? integer

---@class Beast.Animate.Opts
---@field blend_delay? number
---@field ease_pos? fun(t:number):number
---@field ease_size? fun(t:number):number
---@field ease_blend? fun(t:number):number

---@class Beast.Animate.TweenOpts
---@field frame_ms? integer

-- =============================================================================
-- GENERIC TWEEN PRIMITIVE
-- =============================================================================

---Generic frame-loop tween. Calls `on_frame(t, frame, total_frames)` each tick
---with `t` in [0,1] (raw linear progress — caller applies easing per axis).
---Return `false` from `on_frame` to abort the tween (e.g. target became invalid);
---`on_done` still fires once.
---@param duration integer Total duration in ms.
---@param on_frame fun(t:number, frame:integer, total:integer):boolean?
---@param on_done? fun()
---@param opts? Beast.Animate.TweenOpts
function M.tween(duration, on_frame, on_done, opts)
	opts = opts or {}
	local frame_ms = opts.frame_ms or FRAME_MS
	local total_frames = math.max(1, math.floor(duration / frame_ms))
	local frame = 0
	local done = false

	local function finish()
		if done then
			return
		end
		done = true
		if on_done then
			on_done()
		end
	end

	local function step()
		if done then
			return
		end
		frame = frame + 1
		local t = math.min(frame / total_frames, 1)
		local cont = on_frame(t, frame, total_frames)
		if cont == false then
			finish()
			return
		end
		if frame < total_frames then
			vim.defer_fn(step, frame_ms)
		else
			finish()
		end
	end

	vim.defer_fn(step, frame_ms)
end

-- =============================================================================
-- FLOAT WINDOW ANIMATOR (thin wrapper over M.tween)
-- =============================================================================

---Animate float window config fields over time.
---Only keys present in `from`/`to` are animated.
---@param win integer
---@param from Beast.Animate.State
---@param to Beast.Animate.State
---@param duration integer
---@param on_done? fun()
---@param opts? Beast.Animate.Opts
function M.run(win, from, to, duration, on_done, opts)
	opts = opts or {}

	local blend_delay = opts.blend_delay or 0
	local ease_pos_fn = opts.ease_pos or ease_out
	local ease_size_fn = opts.ease_size or ease_in
	local ease_blend_fn = opts.ease_blend or ease_out

	local has_geometry = (from.row ~= nil and to.row ~= nil)
		or (from.col ~= nil and to.col ~= nil)
		or (from.width ~= nil and to.width ~= nil)
		or (from.height ~= nil and to.height ~= nil)

	M.tween(duration, function(t)
		if not vim.api.nvim_win_is_valid(win) then
			return false
		end

		if has_geometry then
			local ok, conf = pcall(vim.api.nvim_win_get_config, win)
			if not ok then
				return false
			end

			local next_conf = {
				relative = conf.relative,
				anchor = conf.anchor,
				row = conf.row,
				col = conf.col,
				width = conf.width,
				height = conf.height,
			}

			local pos_t = ease_pos_fn(t)
			local size_t = ease_size_fn(t)

			if from.row ~= nil and to.row ~= nil then
				next_conf.row = round(lerp(from.row, to.row, pos_t))
			end
			if from.col ~= nil and to.col ~= nil then
				next_conf.col = round(lerp(from.col, to.col, pos_t))
			end
			if from.width ~= nil and to.width ~= nil then
				next_conf.width = math.max(1, round(lerp(from.width, to.width, size_t)))
			end
			if from.height ~= nil and to.height ~= nil then
				next_conf.height = math.max(1, round(lerp(from.height, to.height, size_t)))
			end

			vim.api.nvim_win_set_config(win, next_conf)
		end

		if from.blend ~= nil and to.blend ~= nil then
			local blend_t
			if blend_delay >= 1 then
				blend_t = 0
			elseif t <= blend_delay then
				blend_t = 0
			else
				blend_t = ease_blend_fn((t - blend_delay) / (1 - blend_delay))
			end

			local blend = math.max(0, math.min(100, round(lerp(from.blend, to.blend, blend_t))))
			vim.wo[win].winblend = blend
		end
	end, on_done)
end

return M
