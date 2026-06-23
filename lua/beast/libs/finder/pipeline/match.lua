--- Match pipeline: load items once, then re-score locally on each keystroke.
--- Used by: files (async), buffers, help_tags, colorschemes (sync).
local async = require("beast.libs.async")
local config = require("beast.libs.finder.config")
local matcher = require("beast.libs.finder.matcher")
local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

---@class Beast.Finder.Pipeline.Match
local M = {}

--- Per-query pipeline state (keyed by query reference).
--- `loader_task` streams items from the source (set once by `load`);
--- `matcher_task` re-scores cached items (replaced on every `run`). They use
--- separate slots so a keystroke's `run` never aborts an in-flight loader.
---@type table<Beast.Finder.Query, { match_state: Beast.Finder.MatchState?, loader_task: Beast.Async.Task?, matcher_task: Beast.Async.Task? }>
local registry = setmetatable({}, { __mode = "k" })

---@param query Beast.Finder.Query
local function get(query)
	if not registry[query] then
		registry[query] = {}
	end
	return registry[query]
end

--- Re-score all cached items against the current pattern.
--- Aborts any previous scorer to avoid stale work consuming CPU. Never touches
--- the loader — if items are still streaming in, the loader re-runs `run` (or
--- renders the full empty-pattern list) on completion, so the final result is
--- correct even when a keystroke lands mid-load.
---@param state Beast.Finder.State
function M.run(state)
	local s = get(state.query)
	if s.matcher_task then
		s.matcher_task:abort()
	end
	s.matcher_task = matcher.run(state.query.items, state.query.filter, config.matcher, function(matched, match_state)
		state.query.matched = matched
		if match_state then
			s.match_state = match_state
		end
		render.render(state)
	end, s.match_state)
end

--- Load items from the source (sync or async), then score.
---@param state Beast.Finder.State
function M.load(state)
	local source = state.query.source
	if not source then
		vim.notify("beast.libs.finder: query has no source", vim.log.levels.ERROR)
		return
	end

	local s = get(state.query)

	if source.async then
		state.query.items = {}
		ui.input.start_spinner(state.view.input)
		collectgarbage("stop")

		local finder_done = false
		local items = state.query.items

		-- Items arrive via cb()
		source.get(state.query.filter, function(item)
			if item == nil then
				finder_done = true
				return
			end
			items[#items + 1] = item
			if s.loader_task then
				s.loader_task:resume()
			end
		end)

		-- Concurrent coroutine: collect items into TopK during streaming
		s.loader_task = async.spawn(function()
			local TopK = require("beast.libs.finder.topk")
			local yield = async.yielder(1)
			local match_idx = 0
			local capacity = 1000
			local topk = TopK(capacity)

			while not finder_done or match_idx < #items do
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

				if match_idx > 0 then
					state.query.matched = topk:sorted()
					vim.schedule(function()
						render.render(state)
					end)
				end

				if not finder_done and match_idx >= #items then
					coroutine.yield()
				end
			end

			state.query.matched = topk:sorted()
			vim.schedule(function()
				render.render(state)
				ui.input.stop_spinner(state.view.input)
				collectgarbage("restart")
			end)

			if state.query.filter.pattern ~= "" then
				vim.schedule(function()
					M.run(state)
				end)
			end
		end)
	else
		-- Synchronous sources (buffers, help_tags, colorschemes)
		local result = source.get(state.query.filter)
		state.query.items = result or {}
		M.run(state)
	end
end

--- Abort all running tasks for this query.
---@param query Beast.Finder.Query
function M.abort(query)
	local s = registry[query]
	-- stylua: ignore
	if not s then return end
	if s.loader_task then
		s.loader_task:abort()
		s.loader_task = nil
	end
	if s.matcher_task then
		s.matcher_task:abort()
		s.matcher_task = nil
	end
	registry[query] = nil
end

return M
