local uv = vim.uv or vim.loop

local BUDGET_MS = 10
local YIELD_EVERY = 100

local _active = {} ---@type thread[]
local _executor = assert(uv.new_check(), "beast.libs.async: failed to create check handle")

local function step()
	local start = uv.hrtime()
	local i = #_active
	while i >= 1 do
		if (uv.hrtime() - start) / 1e6 > BUDGET_MS then
			break
		end
		local co = _active[i]
		table.remove(_active, i)
		if coroutine.status(co) ~= "dead" then
			local ok, err = coroutine.resume(co)
			if not ok then
				vim.schedule(function()
					error("beast.libs.async: " .. tostring(err))
				end)
			elseif coroutine.status(co) ~= "dead" then
				table.insert(_active, co)
			end
		end
		i = i - 1
	end
	if #_active == 0 then
		_executor:stop()
	end
end

local M = {}

---@param fn fun()
function M.spawn(fn)
	local co = coroutine.create(fn)
	table.insert(_active, co)
	if not _executor:is_active() then
		_executor:start(step)
	end
end

---@param ms number milliseconds between yields
---@return fun() yielder call inside a coroutine loop
function M.yielder(ms)
	local budget_ns = ms * 1e6
	local count = 0
	local t = uv.hrtime()
	return function()
		count = count + 1
		if count % YIELD_EVERY == 0 and uv.hrtime() - t > budget_ns then
			coroutine.yield()
			t = uv.hrtime()
		end
	end
end

return M
