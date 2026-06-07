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

---@alias Beast.Statuscolumn.Producer fun(win: integer, buf: integer, lnum: integer, relnum: integer, virtnum: integer, win_state: Beast.Statuscolumn.WinState, width: integer): string?

-- Highlight name fallback: when an extmark sign has no sign_hl_group we still
-- need *some* group so the wrapper format below is well-formed.
local FALLBACK_HL = "SignColumn"

-- Per-(text, hl, width) interned `%#hl#text%*` fragments. Sign vocab is small
-- (E/W/I/H glyphs × diag groups + a few git glyphs) so the cache stays tiny.
---@type table<string, string>
local sign_fmt_cache = {}

---@param text string
---@param width integer
---@return string
local function fit_to_width(text, width)
	local dw = vim.fn.strdisplaywidth(text)
	if dw == width then
		return text
	end
	if dw < width then
		return text .. (" "):rep(width - dw)
	end
	-- Neovim normalises 1-cell sign_text to 2 cells by appending a space.
	-- Strip trailing whitespace first; only truncate codepoints if that's
	-- still too wide.
	local stripped = text:gsub("%s+$", "")
	dw = vim.fn.strdisplaywidth(stripped)
	if dw <= width then
		return stripped .. (" "):rep(width - dw)
	end
	local out, ow = "", 0
	for c in stripped:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local cw = vim.fn.strdisplaywidth(c)
		if ow + cw > width then
			break
		end
		out, ow = out .. c, ow + cw
	end
	return out .. (" "):rep(width - ow)
end

---@param text string
---@param hl string
---@param width integer
---@return string
local function format_sign(text, hl, width)
	if hl == "" then
		hl = FALLBACK_HL
	end
	local fitted = fit_to_width(text, width)
	local key = hl .. "\0" .. fitted
	local cached = sign_fmt_cache[key]
	if cached ~= nil then
		return cached
	end
	cached = "%#" .. hl .. "#" .. fitted .. "%*"
	sign_fmt_cache[key] = cached
	return cached
end

---@param ws Beast.Statuscolumn.WinState
---@param class string
---@param lnum integer
---@param width integer
---@return string?
local function sign_in_class(ws, class, lnum, width)
	local cls = ws.signs_by_lnum_by_class[class]
	if not cls then
		return nil
	end
	local s = cls[lnum]
	if not s then
		return nil
	end
	return format_sign(s.text, s.hl, width)
end

---@type table<string, Beast.Statuscolumn.Producer>
local producers = {
	number = function(win, _, lnum, relnum, virtnum)
		return number.format(win, lnum, relnum, virtnum)
	end,
	diagnostic = function(_, _, lnum, _, virtnum, ws, width)
		if virtnum ~= 0 then
			return nil
		end
		return sign_in_class(ws, "diagnostic", lnum, width)
	end,
	git = function(_, _, lnum, _, virtnum, ws, width)
		if virtnum ~= 0 or not config.git.enabled then
			return nil
		end
		return sign_in_class(ws, "git", lnum, width)
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
			local out = p(win, buf, lnum, relnum, virtnum, ws, slot.width)
			if out and out ~= "" then
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
	require("beast").apply_highlights("beast.libs.statuscolumn.highlights")
	rebuild_ignore_sets()
	rebuild_slots()
	fold.refresh_glyphs(config.fold and config.fold.icons or nil)
	ensure_autocmds()
	-- Set the global default so new windows inherit the renderer.
	-- `vim.go` writes the GLOBAL value only — `vim.o` would also stamp the
	-- current window's local value, which is the wrong scope when setup
	-- runs while a `style = "minimal"` float (e.g. the packer install UI)
	-- is current: that float already has a window-local `statuscolumn = ""`
	-- override, and we'd risk reading/writing through it.
	vim.go.statuscolumn = STC_EXPR
	-- Apply to all existing non-floating windows. Their window-local was
	-- captured (as "") when they were created before setup ran, so they
	-- won't pick up the new global until we re-stamp. Skip floats: most
	-- are intentionally minimal (packer UI, finder preview, etc.).
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative == "" then
			vim.api.nvim_set_option_value("statuscolumn", STC_EXPR, { win = win })
		end
	end
	state.installed = true
end

--- Inspection helpers (for tests + :checkhealth).
M._state = state
M._producers = producers

return M
