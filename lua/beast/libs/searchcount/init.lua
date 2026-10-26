-- Search match counter: "current/total" for the active search, shown at the end
-- of the cursor line and in the statusline.
--
-- State lives in Neovim (v:hlsearch, @/, cursor); `get()` only reads it, so
-- every consumer is always consistent with what the search highlight shows.

local api = vim.api

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "searchcount", description = "Search match counter (end of line + statusline)" }

local NS = api.nvim_create_namespace("BeastSearchCount")
local MAX = 999
local TIMEOUT_MS = 100
local ESC = "\27"

---@class Beast.SearchCount.Result
---@field current integer
---@field total integer
---@field text string

-- One memo entry per window: the float and the statusline both ask once per
-- redraw, and `searchcount()` rescans the buffer.
---@type table<integer, { key: string, value: Beast.SearchCount.Result|false }>
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

---Count for the match under the cursor of `winid`, or nil when no count should
---be shown (no active highlight, cursor not on a match, no matches).
---@param winid? integer
---@return Beast.SearchCount.Result?
function M.get(winid)
	winid = (winid == nil or winid == 0) and api.nvim_get_current_win() or winid
	-- stylua: ignore
	if vim.v.hlsearch ~= 1 or not api.nvim_win_is_valid(winid) then return nil end

	local buf = api.nvim_win_get_buf(winid)
	local cursor = api.nvim_win_get_cursor(winid)
	local pat = vim.fn.getreg("/")
	local key = table.concat({ buf, vim.b[buf].changedtick, pat, cursor[1], cursor[2] }, ":")

	local hit = memo[winid]
	if hit and hit.key == key then
		return hit.value or nil
	end

	local sc, on_match
	api.nvim_win_call(winid, function()
		sc = vim.fn.searchcount({ maxcount = MAX, timeout = TIMEOUT_MS })
		on_match = sc.exact_match == 1
		-- Past `maxcount` matches, searchcount() no longer reports exact_match.
		if not on_match and sc.incomplete == 2 and sc.current > MAX then
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
	memo[winid] = { key = key, value = value }
	return value or nil
end

-- Row (0-indexed) to label for the redraw in progress; set by `on_win`, read by `on_line`.
local label_row ---@type integer?
local label_text ---@type string?

---@param win integer
---@param buf integer
local function on_win(_, win, buf)
	label_row = nil
	-- stylua: ignore
	if win ~= api.nvim_get_current_win() or vim.bo[buf].buftype ~= "" then return false end
	local result = M.get(win)
	-- stylua: ignore
	if not result then return false end
	label_row = api.nvim_win_get_cursor(win)[1] - 1
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

function M.setup()
	require("beast").apply_highlights("beast.libs.searchcount.highlights")
	api.nvim_set_decoration_provider(NS, { on_win = on_win, on_line = on_line })

	local group = api.nvim_create_augroup("BeastSearchCount", { clear = true })

	api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(ev)
			memo[tonumber(ev.match) or -1] = nil
		end,
	})

	-- `:noh` and <Esc> clear the highlight without moving the cursor, so the
	-- statusline would keep showing a stale count.
	api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			vim.schedule(vim.cmd.redrawstatus)
		end,
	})
	vim.on_key(function(key)
		if key == ESC then
			vim.schedule(vim.cmd.redrawstatus)
		end
	end, api.nvim_create_namespace("BeastSearchCountOnKey"))
end

return M
