---@alias Beast.Scroll.Easing "linear"|"ease_in"|"ease_out"|"ease_in_out"

---@class Beast.Scroll.Profile
---@field step_ms integer  timer interval per animation tick
---@field total_ms integer total animation duration
---@field easing Beast.Scroll.Easing

---@class Beast.Scroll.RepeatProfile : Beast.Scroll.Profile
---@field delay_ms integer if a new scroll starts within this window, use the repeat profile

---@class Beast.Scroll.Config
---@field enabled boolean             auto-enable on setup
---@field animate Beast.Scroll.Profile
---@field animate_repeat Beast.Scroll.RepeatProfile
---@field filter fun(buf:integer):boolean  return true to animate this buffer
local defaults = {
	enabled = true,
	animate = {
		step_ms = 10,
		total_ms = 200,
		easing = "linear",
	},
	animate_repeat = {
		delay_ms = 100,
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
