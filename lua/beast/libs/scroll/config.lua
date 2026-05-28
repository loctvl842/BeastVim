---@alias Beast.Scroll.Easing "linear"|"ease_in"|"ease_out"|"ease_in_out"

--- Scroll animation configuration.
---
--- TWO PROFILES — WHY?
--- A held key (or mashed <C-d>) fires scroll events faster than one animation
--- can finish. With a single profile, animations queue up and the viewport
--- lags behind your input. The fix: use a short profile for repeats.
---
---   • `animate`        — discrete jumps (gg, G, single <C-d>, /search).
---                        Optimized for LOOK: smooth, deliberate motion.
---   • `animate_repeat` — burst input (held key, repeated <C-d>).
---                        Optimized for FEEL: keeps up with input rate.
---
--- A scroll is treated as a repeat when it starts within `delay_ms` of the
--- previous one ending.
---
--- FIELDS PER PROFILE
---   • `total_ms` — total animation duration. Bigger = more visible glide.
---       Slowest sane: 1500   Sweet spot: 200   Fastest: ~30 (≈ instant)
---   • `step_ms`  — tick interval (ms). Smaller = smoother but more CPU.
---       Don't go below 5 — finer steps don't look smoother, just burn CPU.
---       Typical: 10 (100fps). Chunky: 40 (25fps).
---   • `easing`   — curve shape. Only perceptible when `total_ms` ≥ 150.
---       "linear" | "ease_in" | "ease_out" | "ease_in_out"
---       `ease_out` (decelerating) reads as the smoothest for one-shot jumps.
---
--- RULES OF THUMB
---   • Want pretty single jumps         → bump `animate.total_ms` (400–800),
---                                        switch to `ease_out`.
---   • Want responsive held <C-d>       → keep `animate_repeat.total_ms` low
---                                        (30–80), `delay_ms` 100–300.
---   • `total_ms ≤ step_ms × 2`         → effectively no animation.
---   • Setting both profiles equal      → lag returns on key bursts.
---
--- PRESETS
---   🐢 Cinematic:
---     animate        = { step_ms = 16, total_ms = 800, easing = "ease_out" }
---     animate_repeat = { delay_ms = 300, step_ms = 16, total_ms = 400, easing = "ease_out" }
---   🏍 Balanced (close to snacks defaults):
---     animate        = { step_ms = 10, total_ms = 200, easing = "linear" }
---     animate_repeat = { delay_ms = 100, step_ms = 5,  total_ms = 50,  easing = "linear" }
---   🚀 Snappy:
---     animate        = { step_ms = 8, total_ms = 80, easing = "linear" }
---     animate_repeat = { delay_ms = 80, step_ms = 5, total_ms = 30, easing = "linear" }
---
---@class Beast.Scroll.Profile
---@field step_ms integer   tick interval; ≥ 5 recommended
---@field total_ms integer  total animation duration; 30 ≈ instant, 1500 = cinematic
---@field easing Beast.Scroll.Easing

---@class Beast.Scroll.RepeatProfile : Beast.Scroll.Profile
---@field delay_ms integer  window (ms) for "is this a repeat?" detection

---@class Beast.Scroll.Config
---@field enabled boolean
---@field animate Beast.Scroll.Profile
---@field animate_repeat Beast.Scroll.RepeatProfile
---@field filter fun(buf:integer):boolean
local defaults = {
	enabled = true,
	animate = {
		step_ms = 8,
		total_ms = 80,
		easing = "linear",
	},
	animate_repeat = {
		delay_ms = 300,
		step_ms = 5,
		total_ms = 50,
		easing = "linear",
	},
	filter = function(buf)
		return vim.bo[buf].buftype ~= "terminal"
	end,
}

---@type Beast.Scroll.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Scroll.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.scroll.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
