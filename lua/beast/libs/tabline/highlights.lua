-- Beast.Tabline highlight refresh hook.
-- M.get() returns the BeastTl* group table. M.post_apply() reruns the style
-- resolver and pushes it to icons.lua (which needs sp/underline per state) and
-- forces a tabline redraw.

local config = require("beast.libs.tabline.config")
local icons = require("beast.libs.tabline.icons")

---@param style table       The user-configured state style (selected/visible/normal)
---@param defaults table    Palette-derived fallbacks { fg, bg, sp }
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

-- Resolve everything needed for both M.get() (group table) and M.post_apply()
-- (icons.set_state_styles). Called once per reload from each entry point.
local function compute()
	local p = Palette.get()
	local a = config.appearance

	local active_bg = p.background
	local inactive_bg = Util.colors.lighten(p.background, 15)
	local inactive_fg = Util.colors.blend(p.text, 0.6, active_bg)
	local normal_fg = Util.colors.blend(p.text, 0.4, inactive_bg)
	local fill_bg_default = p.dark1
	local sep_fg_default = p.dimmed3
	local sep_alt_default = Util.colors.blend(p.text, 0.4, active_bg)

	local sel = resolve(a.selected, { fg = p.accent3, bg = active_bg, sp = p.accent3 })
	local vis = resolve(a.visible, { fg = inactive_fg, bg = active_bg, sp = sep_alt_default })
	local nor = resolve(a.normal, { fg = normal_fg, bg = inactive_bg, sp = sep_alt_default })

	local fill = {
		bg = a.fill.bg or fill_bg_default,
		underline = a.fill.underline,
		sp = a.fill.sp or sep_alt_default,
	}

	local sep_fg = a.separator.fg or sep_fg_default
	local sep_fg_vis = a.separator.fg_visible or sep_alt_default
	local sep_fg_sel = a.separator.fg_selected or sep_alt_default

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
		BufferSelected = with(sel),
		BufferVisible = with(vis),
		Buffer = with(nor),

		ModifiedSelected = with(sel),
		ModifiedVisible = with(vis, { fg = sel.fg }),
		Modified = with(nor, { fg = sel.fg }),

		CloseButton = with(sel),

		Separator = with(nor, { fg = sep_fg }),
		SeparatorVisible = with(vis, { fg = sep_fg_vis }),
		SeparatorSelected = with(sel, { fg = sep_fg_sel }),

		TabSelected = { fg = sel.fg, bg = sel.bg, bold = sel.bold or nil },
		TabVisible = { fg = inactive_fg, bg = inactive_bg, bold = true },

		Offset = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
		OffsetSeparator = { fg = p.background, bg = p.background },

		TruncMarker = { fg = sep_fg_default, bg = active_bg, underline = fill.underline, sp = fill.sp },
		Fill = { bg = fill.bg, underline = fill.underline, sp = fill.sp },
		ToggleButton = { fg = p.dimmed1, bg = fill.bg, underline = fill.underline, sp = fill.sp },
	}

	for sev_name, sev_color in pairs(sev) do
		groups["BufferSelected" .. sev_name] = with(sel, { fg = diag_text(sev_color, "selected") })
		groups["BufferVisible" .. sev_name] = with(vis, { fg = diag_text(sev_color, "visible") })
		groups["Buffer" .. sev_name] = with(nor, { fg = diag_text(sev_color, "normal") })

		groups["Diag" .. sev_name .. "Selected"] = with(sel, { fg = diag_count(sev_color, "selected"), bold = true })
		groups["Diag" .. sev_name .. "Visible"] = with(vis, { fg = diag_count(sev_color, "visible"), bold = true })
		groups["Diag" .. sev_name] = with(nor, { fg = diag_count(sev_color, "normal"), bold = true })
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
