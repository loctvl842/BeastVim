-- Sticky treesitter context — public API + autocmd lifecycle.
--
-- A floating overlay pinned to the top of the current window that shows the
-- enclosing treesitter scopes (function, class, conditional, loop, …) of the
-- node under the cursor once their header has scrolled out of view. This mirrors
-- the explorer's sticky ancestor headers, but for code instead of directories.
--
-- Cursor mode only (context is derived from the cursor's node); no separator.

local api = vim.api

local config = require("beast.libs.treesitter.config")
local query_loader = require("beast.libs.treesitter.context.query")
local render = require("beast.libs.treesitter.context.render")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "treesitter.context", description = "Sticky treesitter context header" }

M.enabled = false

local augroup

-- Events that should refresh highlights (not just text) of the open float.
local FORCE_HL_EVENTS = { DiagnosticChanged = true, LspRequest = true }

-- ===========================================================================
-- THROTTLE
-- ===========================================================================

--- Run `fn` at most twice per 150ms per id. A trailing call within the window
--- reschedules once more, so the float keeps up with fast scrolling without
--- recomputing on every single event.
---@generic F: fun(id: integer, ...): any
---@param fn F
---@return F
local function throttle_by_id(fn)
	local timers = {} ---@type table<integer, uv.uv_timer_t>
	local scheduled = {} ---@type table<integer, true?>
	local waiting = {} ---@type table<integer, true?>

	local function run(id, ...)
		local args = { ... }
		if not scheduled[id] then
			scheduled[id] = true
			vim.schedule(function()
				timers[id] = timers[id] or assert(vim.uv.new_timer())
				timers[id]:start(150, 0, function()
					scheduled[id] = nil
					if waiting[id] then
						waiting[id] = nil
						run(id)
					elseif timers[id] and not timers[id]:is_closing() then
						timers[id]:stop()
						timers[id]:close()
						timers[id] = nil
					end
				end)
				fn(id, unpack(args))
			end)
		elseif timers[id] and timers[id]:get_due_in() > 0 then
			waiting[id] = true
		end
	end

	return run
end

-- ===========================================================================
-- ELIGIBILITY
-- ===========================================================================

---@param bufnr integer
---@return string?
local function get_lang(bufnr)
	local ft = vim.bo[bufnr].filetype
	if ft == "" then
		return nil
	end
	local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
	return ok and lang or ft
end

--- Whether a context overlay may be shown for `winid`.
---@param winid integer
---@return boolean
local function can_show(winid)
	if not api.nvim_win_is_valid(winid) then
		return false
	end

	-- Skip floating windows (including our own overlay) and special buffers.
	if api.nvim_win_get_config(winid).relative ~= "" then
		return false
	end

	local bufnr = api.nvim_win_get_buf(winid)
	if vim.bo[bufnr].buftype ~= "" then
		return false
	end
	if vim.wo[winid].previewwindow then
		return false
	end

	local ft = vim.bo[bufnr].filetype
	if ft == "" or ft:find("^beast%-") then
		return false
	end

	local min_height = config.context.min_window_height or 0
	if min_height > 0 and api.nvim_win_get_height(winid) < min_height then
		return false
	end

	local lang = get_lang(bufnr)
	if not lang or not query_loader.has(lang) then
		return false
	end

	return true
end

-- ===========================================================================
-- UPDATE
-- ===========================================================================

local update_win = throttle_by_id(function(winid, force_hl)
	if not api.nvim_win_is_valid(winid) or vim.fn.getcmdtype() ~= "" then
		render.close(winid)
		return
	end

	if not can_show(winid) then
		render.close(winid)
		return
	end

	local ranges, lines = require("beast.libs.treesitter.context.context").get(winid)
	if not ranges or #ranges == 0 then
		render.close(winid)
		return
	end

	render.open(winid, ranges, assert(lines), force_hl)
end)

--- Recompute the context overlay(s).
--- - multiwindow: update every eligible window in the current tabpage so each
---   split keeps its own overlay regardless of focus, and close overlays for
---   windows that are gone or no longer eligible.
--- - single window: only the current window carries an overlay.
---@param event? string
local function update(event)
	local force = event and FORCE_HL_EVENTS[event] or nil

	if not config.context.multiwindow then
		local cur = api.nvim_get_current_win()
		update_win(cur, force)
		render.close_except({ [cur] = true })
		return
	end

	local keep = {} ---@type table<integer, true>
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if can_show(win) then
			keep[win] = true
			update_win(win, force)
		end
	end
	render.close_except(keep)
end

-- ===========================================================================
-- PUBLIC API
-- ===========================================================================

--- Re-render context overlays. Used as the callback fired after a context query
--- file is downloaded, so overlays appear as soon as the language is supported.
function M.refresh()
	if M.enabled then
		update()
	end
end

function M.enable()
	-- stylua: ignore
	if M.enabled then return end
	M.enabled = true

	augroup = api.nvim_create_augroup("BeastTreesitterContext", { clear = true })

	local function au(event, callback, opts)
		opts = opts or {}
		opts.group = augroup
		opts.callback = callback
		api.nvim_create_autocmd(event, opts)
	end

	au({ "WinScrolled", "CursorMoved", "BufEnter", "WinEnter", "VimResized", "WinResized" }, function(args)
		update(args.event)
	end)

	au("OptionSet", function(args)
		if args.match == "number" or args.match == "relativenumber" then
			update(args.event)
		end
	end)

	au(
		"DiagnosticChanged",
		vim.schedule_wrap(function(args)
			update(args.event)
		end)
	)

	-- A closing window's overlay must be torn down; the next update() also GCs
	-- any stale overlays. In single-window mode, focus changes additionally
	-- close the overlay of the window being left.
	au("WinClosed", function(args)
		local win = tonumber(args.match)
		if win then
			render.close(win)
		end
	end)

	au({ "BufLeave", "WinLeave" }, function()
		if not config.context.multiwindow then
			render.close(api.nvim_get_current_win())
		end
	end)

	update()
end

function M.disable()
	-- stylua: ignore
	if not M.enabled then return end
	M.enabled = false

	if augroup then
		api.nvim_del_augroup_by_id(augroup)
		augroup = nil
	end

	render.close_all()
end

function M.toggle()
	if M.enabled then
		M.disable()
	else
		M.enable()
	end
end

return M
