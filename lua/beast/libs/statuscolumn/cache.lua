-- Two-level cache for the statuscolumn render path.
--
-- Layer 1 — per (win, tick): the precomputed render context for the window.
--   per_win[win] = {
--     tick                   = integer, -- last display_tick we saw
--     buf                    = integer, -- buffer at last refresh
--     signs_by_lnum_by_class = table,   -- populated in Phase 2 by signs.lua
--   }
--
-- Layer 2 — per rendered line: an interned result string.
--   line_cache[win][buf][key] = string
--   key = lnum .. ":" .. virtnum .. ":" .. relnum
--
-- Invalidation rules:
--   * `bump_window(win, tick, buf)` — called once per render before a line
--     dispatch. If the tick advanced, the per-win sign map is cleared and the
--     line cache for that window is dropped. Returns true when invalidated.
--   * `drop_win(win)` — called from WinClosed.
--   * `drop_buf(buf)` — called when a buffer is wiped; walks every window's
--     line_cache (cheap, windows are few) and removes the buf entry.

local M = {}

---@class Beast.Statuscolumn.WinState
---@field tick integer
---@field buf integer
---@field signs_by_lnum_by_class table

---@type table<integer, Beast.Statuscolumn.WinState>
local per_win = {}

---@type table<integer, table<integer, table<string, string>>>
local line_cache = {}

---@param win integer
---@param tick integer
---@param buf integer
---@return Beast.Statuscolumn.WinState state
---@return boolean invalidated
function M.bump_window(win, tick, buf)
	local entry = per_win[win]
	if entry and entry.tick == tick and entry.buf == buf then
		return entry, false
	end

	entry = { tick = tick, buf = buf, signs_by_lnum_by_class = {} }
	per_win[win] = entry
	line_cache[win] = { [buf] = {} }
	return entry, true
end

---@param win integer
---@param buf integer
---@param key string
---@return string?
function M.get_line(win, buf, key)
	local wc = line_cache[win]
	if not wc then
		return nil
	end
	local bc = wc[buf]
	if not bc then
		return nil
	end
	return bc[key]
end

---@param win integer
---@param buf integer
---@param key string
---@param value string
function M.set_line(win, buf, key, value)
	-- bump_window always pre-creates line_cache[win][buf]={}, so the inner
	-- tables are guaranteed to exist on the normal render path.
	line_cache[win][buf][key] = value
end

---@param win integer
function M.drop_win(win)
	per_win[win] = nil
	line_cache[win] = nil
end

--- Drop ONLY the per-line interned strings for `win`. Per-window state
--- (tick / sign map) is preserved so callers can force a line-level
--- re-render without re-walking extmarks.
---@param win integer
function M.drop_lines(win)
	local ws = per_win[win]
	if ws then
		line_cache[win] = { [ws.buf] = {} }
	else
		line_cache[win] = nil
	end
end

---@param buf integer
function M.drop_buf(buf)
	for win, wc in pairs(line_cache) do
		wc[buf] = nil
		local ws = per_win[win]
		if ws and ws.buf == buf then
			ws.tick = -1
		end
	end
end

--- Inspection helper for `:checkhealth` and tests.
function M.peek()
	local wins, lines = 0, 0
	for _ in pairs(per_win) do
		wins = wins + 1
	end
	for _, wc in pairs(line_cache) do
		for _, bc in pairs(wc) do
			for _ in pairs(bc) do
				lines = lines + 1
			end
		end
	end
	return { windows = wins, lines = lines }
end

return M
