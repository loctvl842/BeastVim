local cache = require("beast.libs.statuscolumn.cache")
local config = require("beast.libs.statuscolumn.config")
local ffi = require("beast.libs.statuscolumn.ffi")
local fold = require("beast.libs.statuscolumn.fold")
local number = require("beast.libs.statuscolumn.number")
local signs = require("beast.libs.statuscolumn.signs")

local v, g = vim.v, vim.g
local api, bo = vim.api, vim.bo

---@class Beast.Statuscolumn.State
---@field augroup? integer
---@field installed boolean

---@type Beast.Statuscolumn.State
local state = {
	augroup = nil,
	installed = false,
}

local M = {}

-- =========================================================================
-- Producer dispatch
-- =========================================================================
--
-- Each producer is called with `(win, buf, lnum, relnum, virtnum, win_state)`
-- and returns either a string (renders into the slot) or nil/"" (slot tries
-- the next producer in its priority list).

---@alias Beast.Statuscolumn.Producer fun(win: integer, buf: integer, lnum: integer, relnum: integer, virtnum: integer, win_state: Beast.Statuscolumn.WinState): string?

-- Highlight name fallback: when an extmark sign has no sign_hl_group we still
-- need *some* group so the wrapper format below is well-formed.
local FALLBACK_HL = "SignColumn"

-- Per-(text, hl) interned `%#hl#text%*` fragments. Sign vocab is small
-- (E/W/I/H glyphs × diag groups + a few git glyphs) so the cache stays tiny.
---@type table<string, string>
local sign_fmt_cache = {}

---@param text string
---@param hl string
---@return string
local function format_sign(text, hl)
	if hl == "" then
		hl = FALLBACK_HL
	end
	local key = hl .. "\0" .. text
	local cached = sign_fmt_cache[key]
	if cached ~= nil then
		return cached
	end
	cached = "%#" .. hl .. "#" .. text .. "%*"
	sign_fmt_cache[key] = cached
	return cached
end

---@param ws Beast.Statuscolumn.WinState
---@param class string
---@param lnum integer
---@return string?
local function sign_in_class(ws, class, lnum)
	local cls = ws.signs_by_lnum_by_class[class]
	if not cls then
		return nil
	end
	local s = cls[lnum]
	if not s then
		return nil
	end
	return format_sign(s.text, s.hl)
end

---@type table<string, Beast.Statuscolumn.Producer>
local producers = {
	number = function(win, _, lnum, relnum, virtnum)
		return number.format(win, lnum, relnum, virtnum)
	end,
	diagnostic = function(_, _, lnum, _, virtnum, ws)
		if virtnum ~= 0 then
			return nil
		end
		return sign_in_class(ws, "diagnostic", lnum)
	end,
	git = function(_, _, lnum, _, virtnum, ws)
		if virtnum ~= 0 or not config.git.enabled then
			return nil
		end
		return sign_in_class(ws, "git", lnum)
	end,
	fold = function(win, _, lnum, _, virtnum)
		return fold.icon(win, lnum, virtnum, config.fold.open)
	end,
}

---@type table<string, true>
local SIGN_PRODUCERS = { diagnostic = true, git = true, fold = true }

---@class Beast.Statuscolumn.NormalizedSlot
---@field producers string[]
---@field width integer
---@field has_sign boolean
---@field pad string Pre-built `(" "):rep(width)` for the empty/sign-pad case

---@type Beast.Statuscolumn.NormalizedSlot[]
local slots_cache = {}

--- Normalise `config.segments` into a flat list of `{producers, width, has_sign, pad}`
--- tables. Done once at setup / re-setup; the render hot path indexes this
--- by integer without re-parsing the user's mixed shorthand/full syntax.
local function rebuild_slots()
	slots_cache = {}
	for i, raw in ipairs(config.segments or {}) do
		local producers_list, width
		if raw.producers then
			producers_list = raw.producers
			width = raw.width or 1
		else
			producers_list = raw
			width = 1
		end
		local has_sign = false
		for _, name in ipairs(producers_list) do
			if SIGN_PRODUCERS[name] then
				has_sign = true
				break
			end
		end
		slots_cache[i] = {
			producers = producers_list,
			width = width,
			has_sign = has_sign,
			pad = (" "):rep(width),
		}
	end
end

---@param slot Beast.Statuscolumn.NormalizedSlot
local function render_slot(slot, win, buf, lnum, relnum, virtnum, ws)
	local list = slot.producers
	for i = 1, #list do
		local p = producers[list[i]]
		if p then
			local out = p(win, buf, lnum, relnum, virtnum, ws)
			if out and out ~= "" then
				-- Sign-style slots pad the right edge to keep cell width
				-- stable across lines (sign producers render exactly 1 cell).
				if slot.has_sign and slot.width > 1 then
					return out .. (" "):rep(slot.width - 1)
				end
				return out
			end
		end
	end
	-- Sign-style slots pad to `width` cells when empty so the column doesn't
	-- shift when a glyph appears on one line but not the next.
	return slot.has_sign and slot.pad or ""
end

-- =========================================================================
-- Opt-out checks
-- =========================================================================

---@type table<string, true>
local ft_ignore_set = {}
---@type table<string, true>
local bt_ignore_set = {}

local function rebuild_ignore_sets()
	ft_ignore_set = {}
	for _, ft in ipairs(config.ft_ignore or {}) do
		ft_ignore_set[ft] = true
	end
	bt_ignore_set = {}
	for _, bt in ipairs(config.bt_ignore or {}) do
		bt_ignore_set[bt] = true
	end
end

---@param buf integer
---@return boolean
local function buffer_disabled(buf)
	if vim.b[buf].beast_statuscolumn_disabled then
		return true
	end
	local b = bo[buf]
	if bt_ignore_set[b.buftype] then
		return true
	end
	if ft_ignore_set[b.filetype] then
		return true
	end
	return false
end

-- =========================================================================
-- Render (hot path)
-- =========================================================================

---@return string
local function render_inner()
	local win = g.statusline_winid
	if not win or not api.nvim_win_is_valid(win) then
		return ""
	end
	local buf = api.nvim_win_get_buf(win)
	if buffer_disabled(buf) then
		return ""
	end

	local lnum, relnum, virtnum = v.lnum, v.relnum, v.virtnum
	local tick = ffi.tick()

	local ws, invalidated = cache.bump_window(win, tick, buf)
	if invalidated then
		ws.signs_by_lnum_by_class = signs.collect(buf)
	end

	local key = lnum .. ":" .. virtnum .. ":" .. relnum
	local cached = cache.get_line(win, buf, key)
	if cached ~= nil then
		return cached
	end

	local segments = slots_cache
	local n = #segments
	if n == 0 then
		cache.set_line(win, buf, key, "")
		return ""
	end

	-- Avoid table.concat allocation for the common single-slot case.
	local out
	if n == 1 then
		out = render_slot(segments[1], win, buf, lnum, relnum, virtnum, ws)
	else
		local parts = {}
		for i = 1, n do
			parts[i] = render_slot(segments[i], win, buf, lnum, relnum, virtnum, ws)
		end
		out = table.concat(parts)
	end

	cache.set_line(win, buf, key, out)
	return out
end

---@return string
function M.render()
	local ok, out = pcall(render_inner)
	if not ok then
		return ""
	end
	return out
end

-- =========================================================================
-- Setup
-- =========================================================================

local STC_EXPR = "%!v:lua.require'beast.libs.statuscolumn'.render()"

local function ensure_autocmds()
	if state.augroup then
		return
	end
	state.augroup = api.nvim_create_augroup("BeastStatuscolumn", { clear = true })

	api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		callback = function(args)
			local win = tonumber(args.match)
			if win then
				cache.drop_win(win)
			end
		end,
	})

	api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = state.augroup,
		callback = function(args)
			cache.drop_buf(args.buf)
		end,
	})

	api.nvim_create_autocmd("OptionSet", {
		group = state.augroup,
		pattern = "fillchars",
		callback = function()
			fold.refresh_glyphs(config.fold and config.fold.icons or nil)
		end,
	})
end

---@param opts? Beast.Statuscolumn.Config
function M.setup(opts)
	config.setup(opts)
	rebuild_ignore_sets()
	rebuild_slots()
	fold.refresh_glyphs(config.fold and config.fold.icons or nil)
	ensure_autocmds()
	vim.o.statuscolumn = STC_EXPR
	state.installed = true
end

--- Inspection helpers (for tests + :checkhealth).
M._state = state
M._producers = producers

return M
