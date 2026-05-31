-- Beast.Tabline highlight refresh hook.
-- Re-executed on every ColorScheme change via M.highlight_modules.

local config = require("beast.libs.tabline.config")
local icons = require("beast.libs.tabline.icons")
local p = Palette.get()

icons.clear_cache()

-- Palette-derived defaults
local active_bg = p.background
local inactive_bg = Util.colors.lighten(p.background, 15)
local inactive_fg = Util.colors.blend(p.text, 0.6, active_bg)
local normal_fg = Util.colors.blend(p.text, 0.4, inactive_bg)
local fill_bg_default = p.dark1
local sep_fg_default = p.dimmed3
local sep_alt_default = Util.colors.blend(p.text, 0.4, active_bg) -- inactive_border

-- Resolve per-state style: user override > palette default
local a = config.appearance

---@param style table       The user-configured state style (selected/visible/normal)
---@param defaults table    Palette-derived fallbacks { fg, bg, sp }
---@return table            Resolved style usable in nvim_set_hl
local function resolve(style, defaults)
	local fg = style.fg or defaults.fg
	return {
		fg = fg,
		bg = style.bg or defaults.bg,
		sp = style.sp or fg or defaults.sp or fg,
		underline = style.underline,
		bold = style.bold or nil,
	}
end

local sel = resolve(a.selected, { fg = p.accent3, bg = active_bg, sp = p.accent3 })
local vis = resolve(a.visible, { fg = inactive_fg, bg = active_bg, sp = sep_alt_default })
local nor = resolve(a.normal, { fg = normal_fg, bg = inactive_bg, sp = sep_alt_default })

-- Fill / right gap. ToggleButton and TruncMarker also follow the fill rule.
local fill = {
	bg = a.fill.bg or fill_bg_default,
	underline = a.fill.underline,
	sp = a.fill.sp or sep_alt_default,
}

-- Separator glyph colors (state-aware fg, sp inherits from the adjacent cell)
local sep_fg = a.separator.fg or sep_fg_default
local sep_fg_vis = a.separator.fg_visible or sep_alt_default
local sep_fg_sel = a.separator.fg_selected or sep_alt_default

-- Expose resolved styles for icons.lua so it can mirror underline/sp per state
icons.set_state_styles({ selected = sel, visible = vis, normal = nor })

-- Helpers to build state-variant groups with one source of truth
---@param base table  Resolved state style
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

-- Diagnostic severity foregrounds (blended by state for visible/normal)
local function diag_text(severity_color, state)
	if state == "selected" then
		return severity_color
	elseif state == "visible" then
		return Util.colors.blend(severity_color, 0.6, active_bg)
	else
		return Util.colors.blend(severity_color, 0.4, inactive_bg)
	end
end

local function diag_count(severity_color, state)
	if state == "selected" then
		return Util.colors.blend(severity_color, 0.75, active_bg)
	elseif state == "visible" then
		return Util.colors.blend(severity_color, 0.75 * 0.6, active_bg)
	else
		return Util.colors.blend(severity_color, 0.75 * 0.4, inactive_bg)
	end
end

local sev = {
	Error = p.accent1,
	Warn = p.accent2,
	Info = p.accent5,
	Hint = p.accent5,
}

local groups = {
	-- Plain buffer cell (no diagnostics)
	BufferSelected = with(sel),
	BufferVisible = with(vis),
	Buffer = with(nor),

	-- Modified dot — follows selected accent across all states
	ModifiedSelected = with(sel),
	ModifiedVisible = with(vis, { fg = sel.fg }),
	Modified = with(nor, { fg = sel.fg }),

	-- Close button (only rendered on selected cell)
	CloseButton = with(sel),

	-- Separator between buffer cells. sp inherits from the adjacent cell state.
	Separator = with(nor, { fg = sep_fg }),
	SeparatorVisible = with(vis, { fg = sep_fg_vis }),
	SeparatorSelected = with(sel, { fg = sep_fg_sel }),

	-- Tabpages
	TabSelected = { fg = sel.fg, bg = sel.bg, bold = sel.bold or nil },
	TabVisible = { fg = inactive_fg, bg = inactive_bg, bold = true },

	-- Offset (sidebar title) — kept as-is, not part of the cell row
	Offset = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
	OffsetSeparator = { fg = p.background, bg = p.background },

	-- Truncation markers + fill + toggle (the bottom rule across the right gap)
	TruncMarker = { fg = sep_fg_default, bg = active_bg, underline = fill.underline, sp = fill.sp },
	Fill = { bg = fill.bg, underline = fill.underline, sp = fill.sp },
	ToggleButton = { fg = p.dimmed1, bg = fill.bg, underline = fill.underline, sp = fill.sp },
}

-- Generate diagnostic variants (Buffer*<Sev> + Diag<Sev>*)
for sev_name, sev_color in pairs(sev) do
	groups["BufferSelected" .. sev_name] = with(sel, { fg = diag_text(sev_color, "selected") })
	groups["BufferVisible" .. sev_name] = with(vis, { fg = diag_text(sev_color, "visible") })
	groups["Buffer" .. sev_name] = with(nor, { fg = diag_text(sev_color, "normal") })

	groups["Diag" .. sev_name .. "Selected"] = with(sel, { fg = diag_count(sev_color, "selected"), bold = true })
	groups["Diag" .. sev_name .. "Visible"] = with(vis, { fg = diag_count(sev_color, "visible"), bold = true })
	groups["Diag" .. sev_name] = with(nor, { fg = diag_count(sev_color, "normal"), bold = true })
end

Util.colors.set_hl("BeastTl", groups)

vim.cmd("redrawtabline")
