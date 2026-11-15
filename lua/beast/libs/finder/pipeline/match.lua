--- Match pipeline: load items once, then re-score locally on each keystroke.
--- Used by: files (async), buffers, help_tags, colorschemes (sync).
---
--- UI-free: everything it needs from its owner goes through a `Beast.Finder.Host`
--- (see host.lua); every deferred callback captures its own `query` and `s` (the
--- per-query state) and stops as soon as that state is aborted or the host says it is
--- no longer alive, so a late answer can never write into a query that replaced it.
local async = require("beast.libs.async")
local config = require("beast.libs.finder.config")
local matcher = require("beast.libs.finder.matcher")

---@class Beast.Finder.Pipeline.Match
local M = {}

--- Per-query pipeline state (keyed by query reference).
--- `loader_task` streams items from the source (set once by `start`);
--- `matcher_task` re-scores cached items (replaced on every `run`). They use
--- separate slots so a keystroke's `run` never aborts an in-flight loader.
---@class Beast.Finder.Pipeline.Match.State
---@field match_state? Beast.Finder.MatchState
---@field loader_task? Beast.Async.Task
---@field matcher_task? Beast.Async.Task
---@field aborted boolean set by `abort`; deferred callbacks check it
---@field generation integer bumped by every `run`, `reload` and `abort`; an older run's answer is dropped
---@field load_id integer identifies the latest load; callbacks and loader tails of an older one are stale
---@field gc_stopped boolean the loader stopped the garbage collector and has not restarted it yet
---@type table<Beast.Finder.Query, Beast.Finder.Pipeline.Match.State>
local registry = setmetatable({}, { __mode = "k" })

---@param query Beast.Finder.Query
---@return Beast.Finder.Pipeline.Match.State
local function get(query)
	if not registry[query] then
		registry[query] = { aborted = false, generation = 0, load_id = 0, gc_stopped = false }
	end
	return registry[query]
end

--- Also asks the host, so only call it from the main loop (`vim.schedule` callbacks), never from a
--- libuv callback or the loader coroutine (there, check `s.aborted` and `s.load_id` only): the host
--- may call API functions that forbid fast events.
---@param s Beast.Finder.Pipeline.Match.State
---@param host Beast.Finder.Host
---@return boolean
local function stale(s, host)
	return s.aborted or not host.alive()
end

---@param s Beast.Finder.Pipeline.Match.State
local function restart_gc(s)
	if s.gc_stopped then
		s.gc_stopped = false
		collectgarbage("restart")
	end
end

--- Re-score all cached items against the current pattern.
--- Aborts any previous scorer to avoid stale work consuming CPU. Never touches
--- the loader - if items are still streaming in, the loader re-runs `run` (or
--- renders the full empty-pattern list) on completion, so the final result is
--- correct even when a keystroke lands mid-load.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.run(query, host)
	local s = get(query)
	if s.matcher_task then
		s.matcher_task:abort()
	end
	s.generation = s.generation + 1
	local generation = s.generation
	query.matching = true
	s.matcher_task = matcher.run(query.items, query.filter, config.matcher, function(matched, match_state)
		-- An aborted scorer can still deliver an answer it had already queued.
		-- stylua: ignore
		if stale(s, host) or generation ~= s.generation then return end
		query.matched = matched
		-- Progressive partials carry no state; only the final answer ends the run.
		if match_state then
			s.match_state = match_state
			query.total = match_state.total
			query.matching = false
		end
		host.render()
	end, s.match_state, query.limit)
end

--- Load items from the source (sync or async), then score.
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.start(query, host)
	local source = query.source
	if not source then
		vim.notify("beast.libs.finder: query has no source", vim.log.levels.ERROR)
		return
	end

	local s = get(query)

	if not source.async then
		-- Synchronous sources (buffers, help_tags, colorschemes)
		query.items = source.get(query.filter) or {}
		M.run(query, host)
		return
	end

	-- A non-empty `items` here means the caller already fetched the full
	-- result set (finder/preflight.lua, when it found more than one
	-- result) - skip re-querying the source and drain straight into
	-- scoring instead of streaming.
	local preloaded = #query.items > 0
	local items = query.items
	local finder_done = preloaded
	query.loading = not preloaded
	if preloaded and query.filter.pattern == "" then
		query.total = #items
	end
	s.load_id = s.load_id + 1
	local load_id = s.load_id

	--- Wake the loader when it is waiting for the source.
	local function wake()
		if s.loader_task then
			s.loader_task:resume()
		end
	end

	if not preloaded then
		host.busy(true)
		collectgarbage("stop")
		s.gc_stopped = true

		-- Items arrive via cb()
		source.get(query.filter, function(item)
			-- stylua: ignore
			if s.aborted or s.load_id ~= load_id then return end
			if item == nil then
				finder_done = true
			else
				items[#items + 1] = item
			end
			wake()
		end)
	end

	-- Concurrent coroutine: collect items into TopK during streaming
	s.loader_task = async.spawn(function()
		local TopK = require("beast.libs.finder.topk")
		local yield = async.yielder(1)
		local match_idx = 0
		local capacity = query.limit
		local topk = TopK(capacity)

		while not finder_done or match_idx < #items do
			-- stylua: ignore
			if s.aborted or s.load_id ~= load_id then return end
			while match_idx < #items do
				match_idx = match_idx + 1
				local it = items[match_idx]
				it.score = 1
				it.positions = nil
				if match_idx <= capacity then
					topk:push(it)
				end
				yield()
			end

			-- With a pattern typed meanwhile, the scorer owns `matched`: items that merely arrived have not
			-- been scored and must not replace its answer (the final pass after loading scores them all).
			if match_idx > 0 and query.filter.pattern == "" then
				query.matched = topk:sorted()
				query.total = match_idx
				vim.schedule(function()
					-- stylua: ignore
					if stale(s, host) or s.load_id ~= load_id then return end
					host.render()
				end)
			end

			-- Nothing more to read for now: sleep until the source delivers or finishes.
			if not finder_done and match_idx >= #items then
				s.loader_task:suspend()
				coroutine.yield()
			end
		end

		if query.filter.pattern == "" then
			query.matched = topk:sorted()
			query.total = match_idx
		else
			-- Scores so far only cover the items that had arrived: the final pass below completes them,
			-- and a partial answer the scorer already queued must not be mistaken for it.
			query.matching = true
			s.generation = s.generation + 1
		end
		query.loading = false

		vim.schedule(function()
			-- stylua: ignore
			if stale(s, host) or s.load_id ~= load_id then return end
			host.render()
			if not preloaded then
				host.busy(false)
				restart_gc(s)
			end
			if query.filter.pattern ~= "" then
				M.run(query, host)
			end
		end)
	end)
end

--- Throw the loaded items away and load them again (the source's data changed).
---@param query Beast.Finder.Query
---@param host Beast.Finder.Host
function M.reload(query, host)
	local s = get(query)
	if s.loader_task then
		s.loader_task:abort()
		s.loader_task = nil
	end
	if s.matcher_task then
		s.matcher_task:abort()
		s.matcher_task = nil
	end
	restart_gc(s)
	-- An answer the scorer already queued must not land on the new items.
	s.generation = s.generation + 1
	query.items = {}
	query.matched = {}
	query.total = 0
	query.matching = false
	s.match_state = nil
	-- A source that was asked before may keep delivering; `start` bumps `load_id`, so its callback drops everything.
	M.start(query, host)
end

--- Every item that matches the current pattern (not only the best `limit` shown), or nil
--- while the items are still loading or being scored.
---@param query Beast.Finder.Query
---@return Beast.Finder.Item[]?
function M.matches(query)
	-- stylua: ignore
	if query.loading or query.matching then return nil end
	if query.filter.pattern == "" then
		return query.items
	end
	local s = registry[query]
	local state = s and s.match_state
	-- stylua: ignore
	if not state or state.pattern ~= query.filter.pattern then return nil end
	local out = {}
	for _, item in ipairs(query.items) do
		if (state.scores[item.idx] or 0) > 0 then
			out[#out + 1] = item
		end
	end
	return out
end

--- Abort all running tasks for this query.
---@param query Beast.Finder.Query
function M.abort(query)
	local s = registry[query]
	-- stylua: ignore
	if not s then return end
	s.aborted = true
	s.generation = s.generation + 1
	if s.loader_task then
		s.loader_task:abort()
		s.loader_task = nil
	end
	if s.matcher_task then
		s.matcher_task:abort()
		s.matcher_task = nil
	end
	-- `loading` / `matching` stay as they were: a query aborted mid-work never reports a (partial) result set.
	restart_gc(s)
	registry[query] = nil
end

return M
