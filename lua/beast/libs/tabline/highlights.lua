-- Beast.Tabline highlight refresh hook.
-- M.get() returns the BeastTl* group table. M.post_apply() reruns the style
-- resolver and pushes it to icons.lua (which needs sp/underline per state) and
-- forces a tabline redraw.
--
-- Appearance (colors, underlines, bold, separator glyphs, fill bg) is
-- intentionally hardcoded here — it's tightly coupled to the palette tokens
-- and NOT user-configurable. To tweak the look, edit the APPEARANCE builder
-- below; everything downstream reads from it.

local icons = require("beast.libs.tabline.icons")

-- =============================================================================
-- APPEARANCE — single source of truth for tabline styling.
-- =============================================================================
-- `APPEARANCE(p)` returns the palette-derived part (colors, underlines, bold).
-- Called fresh on every reload so ColorScheme changes flow through.
--
-- `DIAG_RATIOS` is the static part — severity-color blend ratios toward each
-- state's cell bg. Kept as a module-level constant so the appearance table
-- stays a single homogeneous shape (no mixed string/number leaves) and the
-- type checker doesn't have to widen `a[k][state]` to `any`.

-- Severity-color blend ratios. `diag_text` colors the buffer name; `diag_count`
-- colors the count badge. Both blend toward each state's cell background.
local DIAG_RATIOS = {
	diag_text = { selected = 1.0, visible = 0.6, normal = 0.4 },
	diag_count = { selected = 0.75, visible = 0.75 * 0.6, normal = 0.75 * 0.4 },
}

---@param p Beast.Palette
local function APPEARANCE(p)
	local active_bg = p.background
	local inactive_bg = Util.colors.lighten(p.background, 15)
	local inactive_fg = Util.colors.blend(p.text, 0.4, active_bg)
	local normal_fg = Util.colors.blend(p.text, 0.4, inactive_bg)
	local sep_alt = Util.colors.blend(p.text, 0.4, active_bg)

	return {
		-- Per-state styles: applied to text, icon underline, modified dot,
		-- close button, separator underline, diagnostic count, tabpage label.
		selected = { fg = p.text, bg = active_bg, sp = p.accent3, underline = false, bold = true },
		visible = { fg = inactive_fg, bg = active_bg, sp = sep_alt, underline = true, bold = false },
		normal = { fg = normal_fg, bg = inactive_bg, sp = sep_alt, underline = true, bold = false },

		-- Right-side gap + TruncMarker + ToggleButton (continuous bottom rule).
		fill = { bg = p.dark1, underline = true, sp = sep_alt },

		-- Glyph fg between buffer cells; underline inherited from adjacent cell.
		separator = {
			fg = p.dimmed3,
			fg_visible = sep_alt,
			fg_selected = sep_alt,
		},

		tab = {
			selected = { fg = p.text, bg = active_bg, bold = true },
			visible = { fg = inactive_fg, bg = inactive_bg, bold = true },
		},

		offset = {
			body = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
			separator = { fg = p.background, bg = p.background },
		},

		toggle_button = { fg = p.dimmed1 },

		diagnostics = {
			Error = p.accent1,
			Warn = p.accent2,
			Info = p.accent5,
			Hint = p.accent5,
		},
	}
end

---@param base table  Resolved state style { fg, bg, sp, underline, bold? }
---@param overrides? table  Extra fields (e.g., custom fg for severity, bold for diagnostics)
local function with(base, overrides)
	local hl = vim.tbl_extend("force", {}, base)
	if overrides then
		for k, v in pairs(overrides) do
			hl[k] = v
		end
	end
	return hl
end

-- Resolve everything needed for both M.get() (group table) and M.post_apply()
-- (icons.set_state_styles). Called once per reload from each entry point.
local function compute()
	local a = APPEARANCE(Palette.get())
	local sel, vis, nor, fill = a.selected, a.visible, a.normal, a.fill

	-- Severity color, blended toward each state's cell bg.
	---@param kind '"diag_text"'|'"diag_count"'
	---@param severity_color string
	---@param state '"selected"'|'"visible"'|'"normal"'
	local function blend_sev(kind, severity_color, state)
		if kind == "diag_text" and state == "selected" then
			return severity_color -- selected uses raw severity color
		end
		local ratio = DIAG_RATIOS[kind][state]
		local bg = (state == "normal") and nor.bg or sel.bg
		return Util.colors.blend(severity_color, ratio, bg)
	end

	local groups = {
		BufferSelected = with(sel),
		BufferVisible = with(vis),
		Buffer = with(nor),

		ModifiedSelected = with(sel),
		ModifiedVisible = with(vis, { fg = sel.fg }),
		Modified = with(nor, { fg = sel.fg }),

		CloseButton = with(sel),

		Separator = with(nor, { fg = a.separator.fg }),
		SeparatorVisible = with(vis, { fg = a.separator.fg_visible }),
		SeparatorSelected = with(sel, { fg = a.separator.fg_selected }),

		TabSelected = a.tab.selected,
		TabVisible = a.tab.visible,

		Offset = a.offset.body,
		OffsetSeparator = a.offset.separator,

		TruncMarker = { fg = a.separator.fg, bg = sel.bg, underline = fill.underline, sp = fill.sp },
		Fill = { bg = fill.bg, underline = fill.underline, sp = fill.sp },
		ToggleButton = { fg = a.toggle_button.fg, bg = fill.bg, underline = fill.underline, sp = fill.sp },
	}

	for sev_name, sev_color in pairs(a.diagnostics) do
		groups["BufferSelected" .. sev_name] = with(sel, { fg = blend_sev("diag_text", sev_color, "selected") })
		groups["BufferVisible" .. sev_name] = with(vis, { fg = blend_sev("diag_text", sev_color, "visible") })
		groups["Buffer" .. sev_name] = with(nor, { fg = blend_sev("diag_text", sev_color, "normal") })

		groups["Diag" .. sev_name .. "Selected"] = with(sel, { fg = blend_sev("diag_count", sev_color, "selected"), bold = true })
		groups["Diag" .. sev_name .. "Visible"] = with(vis, { fg = blend_sev("diag_count", sev_color, "visible"), bold = true })
		groups["Diag" .. sev_name] = with(nor, { fg = blend_sev("diag_count", sev_color, "normal"), bold = true })
	end

	return groups, sel, vis, nor
end

local M = {}

-- Memoized result of compute() so M.get() and M.post_apply() share one pass.
local cache

local function refresh()
	cache = { compute() }
	return cache
end

function M.get()
	local c = refresh()
	return Util.colors.build("BeastTl", c[1])
end

function M.post_apply()
	local c = cache or refresh()
	local sel, vis, nor = c[2], c[3], c[4]
	icons.clear_cache()
	icons.set_state_styles({ selected = sel, visible = vis, normal = nor })
	vim.cmd("redrawtabline")
	cache = nil
end

return M
