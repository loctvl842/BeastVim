-- Trailing-edge debounce wrapping `vim.uv.new_timer`.
--
-- Each call resets the delay; `fn` runs once after `ms` ms of quiet, on the
-- main loop (via `vim.schedule_wrap`), with the most recent arguments.
--
-- Usage:
--   local d = Util.debounce(200, function(text) on_change(text) end)
--   d("hi")     -- schedule
--   d:cancel()  -- abandon pending fire, keep timer alive for reuse
--   d:close()   -- stop + close timer (call from teardown)
--
-- The returned object is callable (via __call) and also exposes :call(...)
-- explicitly for clarity at call sites that prefer it.

local uv = vim.uv or vim.loop

---@class Beast.Util.Debouncer
---@operator call(...): nil
---@field call fun(self: Beast.Util.Debouncer, ...): nil
---@field cancel fun(self: Beast.Util.Debouncer): nil
---@field close fun(self: Beast.Util.Debouncer): nil

---@param ms integer
---@param fn function
---@return Beast.Util.Debouncer
local function debounce(ms, fn)
	local timer
	local args

	local self = {}

	function self:call(...)
		args = { n = select("#", ...), ... }
		if not timer then
			timer = assert(uv.new_timer(), "failed to create timer")
		end
		timer:stop()
		timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				if args then
					fn(unpack(args, 1, args.n))
				end
			end)
		)
	end

	function self:cancel()
		if timer then
			timer:stop()
		end
		args = nil
	end

	function self:close()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		timer = nil
		args = nil
	end

	return setmetatable(self, {
		__call = function(s, ...)
			s:call(...)
		end,
	})
end

return debounce
