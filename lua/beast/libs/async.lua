local uv = vim.uv or vim.loop

local BUDGET_MS = 10
local YIELD_EVERY = 100

local _active = {} ---@type thread[]
local _suspended = {} ---@type table<thread, boolean>
local _on_done = {} ---@type table<thread, fun()[]>
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
		if _suspended[co] then
			i = i - 1
		elseif coroutine.status(co) ~= "dead" then
			local ok, err = coroutine.resume(co)
			if not ok then
				vim.schedule(function()
					error("beast.libs.async: " .. tostring(err))
				end)
			elseif coroutine.status(co) ~= "dead" then
				table.insert(_active, co)
			else
				local cbs = _on_done[co]
				if cbs then
					_on_done[co] = nil
					for _, cb in ipairs(cbs) do
						cb()
					end
				end
			end
		else
			local cbs = _on_done[co]
			if cbs then
				_on_done[co] = nil
				for _, cb in ipairs(cbs) do
					cb()
				end
			end
		end
		i = i - 1
	end
	if #_active == 0 then
		_executor:stop()
	end
end

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "async", description = "Cooperative async scheduler over libuv (coroutines, time-budgeted execution)" }

---@class Beast.Async.Task
---@field _co thread
local Task = {}
Task.__index = Task

--- Spawn a coroutine and return a Task handle.
---@param fn fun()
---@return Beast.Async.Task
function M.spawn(fn)
	local co = coroutine.create(fn)
	table.insert(_active, co)
	if not _executor:is_active() then
		_executor:start(step)
	end
	return setmetatable({ _co = co }, Task)
end

--- Suspend this task. It will not be stepped until resume() is called.
function Task:suspend()
	_suspended[self._co] = true
end

--- Resume a suspended task.
function Task:resume()
	if not _suspended[self._co] then
		return
	end
	_suspended[self._co] = nil
	-- Re-add to active if still alive
	if coroutine.status(self._co) ~= "dead" then
		table.insert(_active, self._co)
		if not _executor:is_active() then
			_executor:start(step)
		end
	end
end

--- Check if the task's coroutine is still running.
---@return boolean
function Task:running()
	return coroutine.status(self._co) ~= "dead"
end

--- Register a callback to fire when this task completes.
---@param cb fun()
function Task:on_done(cb)
	if coroutine.status(self._co) == "dead" then
		cb()
		return
	end
	if not _on_done[self._co] then
		_on_done[self._co] = {}
	end
	table.insert(_on_done[self._co], cb)
end

--- Abort this task by removing it from active/suspended sets.
function Task:abort()
	_suspended[self._co] = nil
	for i, co in ipairs(_active) do
		if co == self._co then
			table.remove(_active, i)
			break
		end
	end
	_on_done[self._co] = nil
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
