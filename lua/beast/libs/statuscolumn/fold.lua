-- Fold producer.
--
-- Uses the FFI `fold_info(win, lnum)` to decide whether the current line:
--   * starts a closed fold        → render `foldclose` glyph
--   * starts an open fold         → render `foldopen` glyph (only when
--                                   `config.fold.open` is true)
--   * is inside / outside a fold  → blank
--
-- Glyphs come from `&fillchars` (`foldopen` / `foldclose`) and are cached
-- at setup time. The hl group is always `BeastStcFold` (link → FoldColumn
-- by default; users can re-link post-setup).

local ffi = require("beast.libs.statuscolumn.ffi")

local M = {}

local HL = "BeastStcFold"

---@class Beast.Statuscolumn.FoldGlyphs
---@field open string
---@field close string

---@type Beast.Statuscolumn.FoldGlyphs
local glyphs = { open = "", close = "" }

---@type table<string, string>
local fmt_cache = {}

local function format(text)
	local cached = fmt_cache[text]
	if cached ~= nil then
		return cached
	end
	cached = "%#" .. HL .. "#" .. text .. "%*"
	fmt_cache[text] = cached
	return cached
end

--- Refresh glyphs from `&fillchars` (`foldopen` / `foldclose`).
--- Falls back to Unicode arrows so the column always renders something
--- when a fold is closed — even on minimal `--clean` configs.
--- Called at setup and on `OptionSet fillchars`.
---@param overrides? Beast.Statuscolumn.FoldGlyphs
function M.refresh_glyphs(overrides)
	local fc = vim.opt.fillchars:get()
	-- Unicode triangles render in any terminal that handles UTF-8; used only
	-- when neither config.fold.icons nor &fillchars provide a glyph.
	local fallback_open = "\u{25BC}" -- ▼
	local fallback_close = "\u{25B6}" -- ▶
	glyphs.open = (overrides and overrides.open ~= "" and overrides.open) or fc.foldopen or fallback_open
	glyphs.close = (overrides and overrides.close ~= "" and overrides.close) or fc.foldclose or fallback_close
	fmt_cache = {}
end

--- Returns the fold-segment string for one line, or nil when there's no fold
--- glyph to show.
---@param win integer
---@param lnum integer
---@param virtnum integer
---@param show_open boolean
---@return string?
function M.icon(win, lnum, virtnum, show_open)
	if virtnum ~= 0 then
		return nil
	end
	local info = ffi.fold_info(win, lnum)
	if not info or info.level == 0 then
		return nil
	end
	if info.lines > 0 then
		if glyphs.close == "" then
			return nil
		end
		return format(glyphs.close)
	end
	if show_open and info.start == lnum then
		if glyphs.open == "" then
			return nil
		end
		return format(glyphs.open)
	end
	return nil
end

return M
