-- Search match counter: "current/total" for the active search, shown at the end
-- of the cursor line and in the statusline.
--
-- Neovim owns the count: `refresh()` calls searchcount() and caches the result
-- per window. Consumers (`get`) read the cache, so a statusline render never
-- scans the buffer. setup() debounces the recompute on cursor, text, window,
-- and buffer changes, then redraws. Holding j/k therefore costs a timer reset
-- per move, not a full buffer scan.

local api = vim.api

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "searchcount", description = "Search match counter (end of line + statusline)" }

local NS = api.nvim_create_namespace("BeastSearchCount")
local MAX = 999
local TIMEOUT_MS = 100
local DEBOUNCE_MS = 100
local ESC = "\27"

---@class Beast.SearchCount.Result
---@field current integer
---@field total integer
---@field text string

---Last computed count per window, plus the buffer, pattern, and cursor it was
---computed for. `get` returns it only while the buffer and pattern still
---match; the debounced refresh keeps it current.
---@class Beast.SearchCount.Entry
---@field value Beast.SearchCount.Result|false
---@field buf integer
---@field pat string
---@field line integer
---@field col integer

---@type table<integer, Beast.SearchCount.Entry>
local memo = {}

---@param n integer
---@return string
local function cap(n)
	return n > MAX and (MAX .. "+") or tostring(n)
end

---@param current integer
---@param total integer
---@return string
function M.format(current, total)
	return cap(current) .. "/" .. cap(total)
end

---The cached count still describes this window's buffer and search?
---@param winid integer
---@param entry Beast.SearchCount.Entry
---@return boolean
local function still_valid(winid, entry)
	return entry.buf == api.nvim_win_get_buf(winid) and entry.pat == vim.fn.getreg("/")
end

---Recompute the count for `winid` and cache it. Driven by the debounced
---autocmds in setup(); also callable directly when a fresh value is needed.
---Does not scan when no search is highlighted.
---@param winid? integer
---@return Beast.SearchCount.Result?
function M.refresh(winid)
	winid = (winid == nil or winid == 0) and api.nvim_get_current_win() or winid
  -- stylua: ignore
  if not api.nvim_win_is_valid(winid) then return nil end
	if vim.v.hlsearch ~= 1 then
		memo[winid] = nil
		return nil
	end

	local buf = api.nvim_win_get_buf(winid)
	local cursor = api.nvim_win_get_cursor(winid)
	local pat = vim.fn.getreg("/")

	local sc, on_match
	api.nvim_win_call(winid, function()
		sc = vim.fn.searchcount({ maxcount = MAX, timeout = TIMEOUT_MS, recompute = 1 })
		if type(sc) ~= "table" then
			sc = {}
		end
		on_match = sc.exact_match == 1
		-- Past `maxcount` matches, searchcount() no longer reports exact_match.
		if not on_match and sc.incomplete == 2 and (sc.current or 0) > MAX then
			local pos = vim.fn.searchpos(pat, "cnW", cursor[1])
			on_match = pos[1] == cursor[1] and pos[2] == cursor[2] + 1
		end
	end)

	---@type Beast.SearchCount.Result|false
	local value = false
	if sc.total and sc.total > 0 and on_match then
		-- `incomplete` (timeout or maxcount hit) means the real total is larger.
		local total = sc.incomplete ~= 0 and MAX + 1 or sc.total
		value = { current = sc.current, total = total, text = M.format(sc.current, total) }
	end
	memo[winid] = { value = value, buf = buf, pat = pat, line = cursor[1], col = cursor[2] }
	return value or nil
end

---Cached count for `winid`, or nil. Never scans the buffer; refresh() does.
---@param winid? integer
---@return Beast.SearchCount.Result?
function M.get(winid)
	winid = (winid == nil or winid == 0) and api.nvim_get_current_win() or winid
  -- stylua: ignore
  if vim.v.hlsearch ~= 1 or not api.nvim_win_is_valid(winid) then return nil end
	local entry = memo[winid]
  -- stylua: ignore
  if not entry or not still_valid(winid, entry) then return nil end
	return entry.value or nil
end

-- Row (0-indexed) to label for the redraw in progress; set by `on_win`, read by `on_line`.
local label_row ---@type integer?
local label_text ---@type string?

---@param win integer
---@param buf integer
local function on_win(_, win, buf)
	label_row = nil
  -- stylua: ignore
  if win ~= api.nvim_get_current_win() or vim.bo[buf].buftype ~= "" or vim.v.hlsearch ~= 1 then return false end
	local entry = memo[win]
  -- stylua: ignore
  if not entry or not still_valid(win, entry) then return false end
	-- Label only the line the count was computed for. While the debounce is
	-- pending the cursor may already be elsewhere, and drawing the old count
	-- there would be wrong.
	local cursor = api.nvim_win_get_cursor(win)
  -- stylua: ignore
  if entry.line ~= cursor[1] or entry.col ~= cursor[2] then return false end
	local result = entry.value
  -- stylua: ignore
  if not result then return false end
	label_row = cursor[1] - 1
	label_text = result.text
end

---@param buf integer
---@param row integer
local function on_line(_, _, buf, row)
	-- stylua: ignore
	if row ~= label_row then return end
	api.nvim_buf_set_extmark(buf, NS, row, 0, {
		virt_text = { { "  " }, { " " .. label_text .. " ", "BeastSearchCountFloat" } },
		virt_text_pos = "eol",
		ephemeral = true,
	})
end

---@type uv.uv_timer_t|nil
local refresh_timer

---Restart the debounce. Called on every cursor, text, and window change; the
---recompute runs once the user pauses for DEBOUNCE_MS.
local function schedule_refresh()
	local uv = vim.uv or vim.loop
	if not refresh_timer then
		refresh_timer = assert(uv.new_timer())
	end
	refresh_timer:stop()
	refresh_timer:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			M.refresh(api.nvim_get_current_win())
			vim.cmd.redrawstatus()
		end)
	)
end

---Redraw now, for changes that `get` hides immediately such as `:noh`.
local function redraw_now()
	vim.schedule(function()
		vim.cmd.redrawstatus()
	end)
end

function M.setup()
	require("beast").apply_highlights("beast.libs.searchcount.highlights")
	api.nvim_set_decoration_provider(NS, { on_win = on_win, on_line = on_line })

	local group = api.nvim_create_augroup("BeastSearchCount", { clear = true })

	api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "WinEnter", "BufEnter" }, {
		group = group,
		callback = schedule_refresh,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(ev)
			memo[tonumber(ev.match) or -1] = nil
		end,
	})

	-- A command can change or clear the search without moving the cursor.
	api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			schedule_refresh()
			redraw_now()
		end,
	})

	vim.on_key(function(key)
		if key == ESC then
			schedule_refresh()
			redraw_now()
		end
	end, api.nvim_create_namespace("BeastSearchCountOnKey"))

	-- Seed the cache so the pill can render before the first movement. The
	-- statusline component reads package.loaded, so it may have rendered
	-- before this lib loaded; one redraw makes the pill appear now.
	M.refresh(api.nvim_get_current_win())
	vim.schedule(function()
		vim.cmd.redrawstatus()
	end)
end

return M
