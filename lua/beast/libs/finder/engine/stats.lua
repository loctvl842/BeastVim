-- Lightweight ring buffer of recent live_grep queries for diagnostics.
--
-- live_grep records one entry per query: pattern, whether the prefilter ran,
-- survivor count, prefilter time, total time, result count. :BeastFinderBigram
-- stats prints them so a slow/"dead" spam session can be inspected without a
-- profiler. Costs ~nothing when disabled (config.engine.debug=false).

local M = {}

local CAP = 50
local ring = {}
local enabled = false

--- Toggle recording; off by default so the hot path stays free.
---@param on boolean
function M.set(on)
	enabled = on
end

---@return boolean
function M.enabled()
	return enabled
end

--- Record one query. Fields: pattern, survivors (int|nil=full scan), prefilter_ms.
--- Returns a handle to finish() with results+total when the grep completes.
---@param pattern string
---@param survivors integer?
---@param prefilter_ms number
---@return { results: integer, total_ms: number, t0: number }?
function M.start(pattern, survivors, prefilter_ms)
	if not enabled then
		return nil
	end
	local rec = { pattern = pattern, survivors = survivors, prefilter_ms = prefilter_ms, results = 0, total_ms = 0, t0 = (vim.uv or vim.loop).hrtime() }
	ring[#ring + 1] = rec
	if #ring > CAP then
		table.remove(ring, 1)
	end
	return rec
end

--- Close out a record with result count + elapsed.
---@param rec table?
---@param results integer
function M.finish(rec, results)
	if not rec then
		return
	end
	rec.results = results
	rec.total_ms = ((vim.uv or vim.loop).hrtime() - rec.t0) / 1e6
end

--- Recent queries, newest last.
---@return table[]
function M.recent()
	return ring
end

return M
