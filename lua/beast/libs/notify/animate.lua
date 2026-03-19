local M = {}

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

---@param value number
---@return integer
local function round(value)
	return math.floor(value + 0.5)
end

-- =============================================================================
-- TYPES
-- =============================================================================

---@class Animate.State
---@field row? integer
---@field col? integer
---@field width? integer
---@field height? integer
---@field blend? integer

---@class Animate.Opts
---@field blend_delay? number
---@field ease_pos? fun(t:number):number
---@field ease_size? fun(t:number):number
---@field ease_blend? fun(t:number):number

-- =============================================================================
-- MODULE
-- =============================================================================

---Animate float window config fields over time.
---Only keys present in `from`/`to` are animated.
---@param win integer
---@param from Animate.State
---@param to Animate.State
---@param duration integer
---@param on_done? fun()
---@param opts? Animate.Opts
function M.run(win, from, to, duration, on_done, opts)
	opts = opts or {}

	local blend_delay = opts.blend_delay or 0
	local ease_pos = opts.ease_pos or ease_out
	local ease_size = opts.ease_size or ease_in
	local ease_blend = opts.ease_blend or ease_in

	local total_frames = math.max(1, math.floor(duration / FRAME_MS))
	local frame = 0

	local function step()
		if not vim.api.nvim_win_is_valid(win) then
			if on_done then
				on_done()
			end
			return
		end

		frame = frame + 1
		local t = math.min(frame / total_frames, 1)

		local ok, conf = pcall(vim.api.nvim_win_get_config, win)
		if not ok then
			if on_done then
				on_done()
			end
			return
		end

		local next_conf = {
			relative = conf.relative,
			row = conf.row,
			col = conf.col,
			width = conf.width,
			height = conf.height,
		}

		if from.row ~= nil and to.row ~= nil then
			next_conf.row = round(lerp(from.row, to.row, ease_pos(t)))
		end

		if from.col ~= nil and to.col ~= nil then
			next_conf.col = round(lerp(from.col, to.col, ease_pos(t)))
		end

		if from.width ~= nil and to.width ~= nil then
			next_conf.width = math.max(1, round(lerp(from.width, to.width, ease_size(t))))
		end

		if from.height ~= nil and to.height ~= nil then
			next_conf.height = math.max(1, round(lerp(from.height, to.height, ease_size(t))))
		end

		vim.api.nvim_win_set_config(win, next_conf)

		if from.blend ~= nil and to.blend ~= nil then
			local blend_t
			if blend_delay >= 1 then
				blend_t = 0
			elseif t <= blend_delay then
				blend_t = 0
			else
				blend_t = ease_blend((t - blend_delay) / (1 - blend_delay))
			end

			local blend = math.max(0, math.min(100, round(lerp(from.blend, to.blend, blend_t))))
			vim.wo[win].winblend = blend
		end

		if frame < total_frames then
			vim.defer_fn(step, FRAME_MS)
		elseif on_done then
			on_done()
		end
	end

	vim.defer_fn(step, FRAME_MS)
end

return M
