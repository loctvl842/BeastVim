--- Match pipeline: load items once, then re-score locally on each keystroke.
--- Used by: files (async), buffers, help_tags, colorschemes (sync).
local async = require("beast.libs.async")
local config = require("beast.libs.finder.config")
local matcher = require("beast.libs.finder.matcher")
local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

local M = {}

--- Per-query pipeline state (keyed by query reference).
---@type table<Beast.Finder.Query, { match_state: Beast.Finder.MatchState?, finder_task: Beast.Async.Task?, matcher_task: Beast.Async.Task? }>
local state = setmetatable({}, { __mode = "k" })

---@param query Beast.Finder.Query
local function get(query)
	if not state[query] then
		state[query] = {}
	end
	return state[query]
end

--- Re-score all cached items against the current pattern.
--- Aborts any previous scorer to avoid stale work consuming CPU.
---@param query Beast.Finder.Query
function M.rescore(query)
	local s = get(query)
	if s.matcher_task then
		s.matcher_task:abort()
	end
	s.matcher_task = matcher.run(query.items, query.filter, config.matcher, function(matched, match_state)
		query.matched = matched
		if match_state then
			s.match_state = match_state
		end
		render.render(query)
	end, s.match_state)
end

--- Load items from the source (sync or async), then score.
---@param query Beast.Finder.Query
function M.load(query)
	local source = query.source
	if not source then
		vim.notify("beast.libs.finder: query has no source", vim.log.levels.ERROR)
		return
	end

	local s = get(query)

	if source.async then
		query.items = {}
		ui.input.start_spinner(query.input_view)
		collectgarbage("stop")

		local finder_done = false
		local items = query.items

		-- Items arrive via cb()
		source.get(query.filter, function(item)
			if item == nil then
				finder_done = true
				return
			end
			items[#items + 1] = item
			if s.matcher_task then
				s.matcher_task:resume()
			end
		end)

		-- Concurrent coroutine: collect items into TopK during streaming
		s.matcher_task = async.spawn(function()
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
					query.matched = topk:sorted()
					vim.schedule(function()
						render.render(query)
					end)
				end

				if not finder_done and match_idx >= #items then
					coroutine.yield()
				end
			end

			query.matched = topk:sorted()
			vim.schedule(function()
				render.render(query)
				ui.input.stop_spinner(query.input_view)
				collectgarbage("restart")
			end)

			if query.filter.pattern ~= "" then
				vim.schedule(function()
					M.rescore(query)
				end)
			end
		end)
	else
		-- Synchronous sources (buffers, help_tags, colorschemes)
		local result = source.get(query.filter)
		query.items = result or {}
		M.rescore(query)
	end
end

--- Abort all running tasks for this query.
---@param query Beast.Finder.Query
function M.abort(query)
	local s = state[query]
	-- stylua: ignore
	if not s then return end
	if s.finder_task then
		s.finder_task:abort()
		s.finder_task = nil
	end
	if s.matcher_task then
		s.matcher_task:abort()
		s.matcher_task = nil
	end
	state[query] = nil
end

return M
