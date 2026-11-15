--- Stream pipeline: re-run external command on each keystroke, results are pre-filtered.
--- Used by: live_grep, the GitHub sources.
---
--- UI-free like the match pipeline: the owner is reached through a `Beast.Finder.Host`,
--- and every callback captures its own query and state and stops once either is stale.
local uv = vim.uv or vim.loop

---@class Beast.Finder.Pipeline.Stream
local M = {}

--- Adaptive render budget (nanoseconds)
local RENDER_FAST_NS = 10e6 -- 10ms — first results appear fast
local RENDER_SLOW_NS = 30e6 -- 30ms — once viewport filled, reduce redraw cost

--- Per-query pipeline state (keyed by query reference).
---@class Beast.Finder.Pipeline.Stream.State
---@field batch Beast.Finder.Item[]
---@field render_check? uv.uv_check_t
---@field last_render_ns number
---@field fresh? boolean the previous list is still shown and the next arriving item replaces it
---@field run_id? integer identifies the latest run; callbacks of any other run are stale
---@field aborted boolean set by `abort`
---@field gc_stopped boolean
---@type table<Beast.Finder.Query, Beast.Finder.Pipeline.Stream.State>
local registry = setmetatable({}, { __mode = "k" })

---@param query Beast.Finder.Query
---@return Beast.Finder.Pipeline.Stream.State
local function get(query)
	if not registry[query] then
		registry[query] = { batch = {}, last_render_ns = 0, aborted = false, gc_stopped = false }
	end
	return registry[query]
end

--- Safe everywhere, including libuv callbacks (no API calls).
---@param s Beast.Finder.Pipeline.Stream.State
---@param run_id integer
---@return boolean
local function superseded(s, run_id)
	return s.aborted or s.run_id ~= run_id
end

--- Also asks the host, so only call it from the main loop (`vim.schedule` callbacks), never from a
--- libuv callback: the host may call API functions that forbid fast events.
---@param s Beast.Finder.Pipeline.Stream.State
---@param host Beast.Finder.Host
---@param run_id integer
---@return boolean
local function stale(s, host, run_id)
	return superseded(s, run_id) or not host.alive()
end

---@param s Beast.Finder.Pipeline.Stream.State
local function restart_gc(s)
	if s.gc_stopped then
		s.gc_stopped = false
		collectgarbage("restart")
	end
end

--- Drop the list contents (the list view rewinds itself through `host.rewind`).
---@param query Beast.Finder.Query
local function clear_list(query)
	query.items = {}
	query.matched = {}
	query.total = 0
end

--- Show the source's count label (when it has one) once a search has finished.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
local function update_count(query, host)
	local source = query.source
	if source.count then
		host.count(source.count(query.items))
	end
end

--- Commit pending items and render. Stream sources are pre-filtered — no scoring needed.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
local function flush(query, host)
	local s = get(query)
	-- stylua: ignore
	if #s.batch == 0 then return end

	-- A retain_results source keeps showing the previous list until the first new item lands.
	if s.fresh then
		s.fresh = false
		clear_list(query)
		host.rewind()
	end

	local batch = s.batch
	s.batch = {}
	for _, item in ipairs(batch) do
		query.items[#query.items + 1] = item
	end
	query.matched = query.items
	query.total = #query.items
	host.render()
end

--- Re-run the live source with the current filter pattern.
--- Kills previous subprocess, clears state, starts new subprocess with adaptive render polling.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.run(query, host)
	local source = query.source
	-- stylua: ignore
	if not source then return end

	local s = get(query)

	-- Callbacks of a cancelled run must not touch the run that replaced it.
	s.run_id = (s.run_id or 0) + 1
	local run_id = s.run_id

	-- Cancel any in-flight process
	if source.cancel then
		source.cancel()
	end

	-- Stop previous render check
	if s.render_check and s.render_check:is_active() then
		s.render_check:stop()
	end

	-- Empty query → clear results (unless the source searches on an empty prompt too)
	if query.filter.pattern == "" and not source.run_when_empty then
		clear_list(query)
		s.batch = {}
		query.loading = false
		host.busy(false)
		restart_gc(s)
		host.render()
		return
	end

	s.batch = {}
	s.fresh = source.retain_results == true
	if not s.fresh then
		clear_list(query)
		host.render()
	end

	query.loading = true
	host.count(nil)
	if source.title then
		host.title(source.title(query.filter))
	end
	host.busy(true)
	collectgarbage("stop")
	s.gc_stopped = true

	-- Adaptive poll loop — fires every event loop tick, renders when budget allows
	s.last_render_ns = uv.hrtime()
	if not s.render_check then
		s.render_check = assert(uv.new_check(), "failed to create render check")
	end
	s.render_check:start(vim.schedule_wrap(function()
		-- stylua: ignore
		if stale(s, host, run_id) then return end
		-- stylua: ignore
		if #s.batch == 0 then return end

		local now = uv.hrtime()
		local budget = #query.items > host.rows() and RENDER_SLOW_NS or RENDER_FAST_NS
		-- stylua: ignore
		if now - s.last_render_ns < budget then return end

		s.last_render_ns = now
		flush(query, host)
	end))

	source.get(query.filter, function(item)
		-- stylua: ignore
		if superseded(s, run_id) then return end
		if item == nil then
			vim.schedule(function()
				-- stylua: ignore
				if stale(s, host, run_id) then return end
				if s.render_check and s.render_check:is_active() then
					s.render_check:stop()
				end
				flush(query, host)
				if s.fresh then
					-- Nothing replaced the retained list: this search found nothing.
					s.fresh = false
					clear_list(query)
					host.rewind()
					host.render()
				end
				query.loading = false
				host.busy(false)
				update_count(query, host)
				restart_gc(s)
			end)
			return
		end
		s.batch[#s.batch + 1] = item
	end)
end

--- Start the pipeline: a live source with a default query searches right away, the others wait for typing.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.start(query, host)
	local initial = query.source.initial_query
	if initial then
		query.filter:update(initial)
		M.run(query, host)
	end
end

--- The source's data changed: run the current query again.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.reload(query, host)
	M.run(query, host)
end

--- Every result of the finished search, or nil while it is still running.
---@param query Beast.Finder.Query
---@return Beast.Finder.Item[]?
function M.matches(query)
	-- stylua: ignore
	if query.loading then return nil end
	return query.items
end

--- Abort all running work for this query.
---@param query Beast.Finder.Query
function M.abort(query)
	local s = registry[query]
	-- stylua: ignore
	if not s then return end
	s.aborted = true
	if s.render_check then
		if s.render_check:is_active() then
			s.render_check:stop()
		end
		if not s.render_check:is_closing() then
			s.render_check:close()
		end
	end
	local source = query.source
	if source and source.cancel then
		source.cancel()
	end
	-- `loading` stays as it was: a query aborted mid-search never reports a (partial) result set.
	restart_gc(s)
	registry[query] = nil
end

return M
