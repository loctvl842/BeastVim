--- Stream pipeline: re-run external command on each keystroke, results are pre-filtered.
--- Used by: live_grep.
local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

local uv = vim.uv or vim.loop

local M = {}

--- Adaptive render budget (nanoseconds)
local RENDER_FAST_NS = 10e6 -- 10ms — first results appear fast
local RENDER_SLOW_NS = 30e6 -- 30ms — once viewport filled, reduce redraw cost

--- Per-query pipeline state (keyed by query reference).
---@type table<Beast.Finder.Query, { batch: Beast.Finder.Item[], render_check: uv.uv_check_t?, last_render_ns: number }>
local state = setmetatable({}, { __mode = "k" })

---@param query Beast.Finder.Query
local function get(query)
	if not state[query] then
		state[query] = { batch = {}, last_render_ns = 0 }
	end
	return state[query]
end

--- Commit pending items and render. Stream sources are pre-filtered — no scoring needed.
---@param query Beast.Finder.Query
function M.flush(query)
	local s = get(query)
	-- stylua: ignore
	if #s.batch == 0 then return end

	local batch = s.batch
	s.batch = {}
	for _, item in ipairs(batch) do
		query.items[#query.items + 1] = item
	end
	query.matched = query.items
	render.render(query)
end

--- Re-run the live source with the current filter pattern.
--- Kills previous subprocess, clears state, starts new subprocess with adaptive render polling.
---@param query Beast.Finder.Query
function M.reload(query)
	local source = query.source
	-- stylua: ignore
	if not source then return end

	local s = get(query)

	-- Cancel any in-flight process
	if source.cancel then
		source.cancel()
	end

	-- Stop previous render check
	if s.render_check and s.render_check:is_active() then
		s.render_check:stop()
	end

	-- Empty query → clear results
	if query.filter.pattern == "" then
		query.items = {}
		query.matched = {}
		s.batch = {}
		render.render(query)
		return
	end

	query.items = {}
	query.matched = {}
	s.batch = {}
	render.render(query)

	ui.input.start_spinner(query.input_view)
	collectgarbage("stop")

	-- Adaptive poll loop — fires every event loop tick, renders when budget allows
	s.last_render_ns = uv.hrtime()
	if not s.render_check then
		s.render_check = assert(uv.new_check(), "failed to create render check")
	end
	s.render_check:start(vim.schedule_wrap(function()
		-- stylua: ignore
		if not query.list_view:is_valid() then return end
		-- stylua: ignore
		if #s.batch == 0 then return end

		local now = uv.hrtime()
		local win_h = query.list_view._win_height or 50
		local budget = #query.items > win_h and RENDER_SLOW_NS or RENDER_FAST_NS
		-- stylua: ignore
		if now - s.last_render_ns < budget then return end

		s.last_render_ns = now
		M.flush(query)
	end))

	source.get(query.filter, function(item)
		if item == nil then
			vim.schedule(function()
				if s.render_check and s.render_check:is_active() then
					s.render_check:stop()
				end
				M.flush(query)
				ui.input.stop_spinner(query.input_view)
				collectgarbage("restart")
			end)
			return
		end
		s.batch[#s.batch + 1] = item
	end)
end

--- Abort all running work for this query.
---@param query Beast.Finder.Query
function M.abort(query)
	local s = state[query]
	-- stylua: ignore
	if not s then return end
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
	collectgarbage("restart")
	state[query] = nil
end

return M
