-- Beast.Tabline highlight refresh hook.
-- Re-executed on every ColorScheme change via M.highlight_modules.

local icons = require("beast.libs.tabline.icons")
local p = Palette.get()

icons.clear_cache()

local active_bg = p.background
local inactive_bg = Util.colors.lighten(p.background, 15)
local inactive_fg = Util.colors.blend(p.text, 0.6, active_bg)
local normal_fg = Util.colors.blend(p.text, 0.4, inactive_bg)
local active_border = p.accent3
local inactive_border = p.dimmed4

-- Diagnostic foreground colors (Selected: full, Visible: blended on active_bg, Normal: blended on inactive_bg)
local error_active_fg = p.accent1
local error_visible_fg = Util.colors.blend(p.accent1, 0.6, active_bg)
local error_normal_fg = Util.colors.blend(p.accent1, 0.4, inactive_bg)
local warn_active_fg = p.accent2
local warn_visible_fg = Util.colors.blend(p.accent2, 0.6, active_bg)
local warn_normal_fg = Util.colors.blend(p.accent2, 0.4, inactive_bg)
local info_hint_active_fg = p.accent5
local info_hint_visible_fg = Util.colors.blend(p.accent5, 0.6, active_bg)
local info_hint_normal_fg = Util.colors.blend(p.accent5, 0.4, inactive_bg)

-- Diagnostic count foreground colors (slightly blended)
local error_count_active_fg = Util.colors.blend(p.accent1, 0.75, active_bg)
local error_count_visible_fg = Util.colors.blend(p.accent1, 0.75 * 0.6, active_bg)
local error_count_normal_fg = Util.colors.blend(p.accent1, 0.75 * 0.4, inactive_bg)
local warn_count_active_fg = Util.colors.blend(p.accent2, 0.75, active_bg)
local warn_count_visible_fg = Util.colors.blend(p.accent2, 0.75 * 0.6, active_bg)
local warn_count_normal_fg = Util.colors.blend(p.accent2, 0.75 * 0.4, inactive_bg)
local info_hint_count_active_fg = Util.colors.blend(p.accent5, 0.75, active_bg)
local info_hint_count_visible_fg = Util.colors.blend(p.accent5, 0.75 * 0.6, active_bg)
local info_hint_count_normal_fg = Util.colors.blend(p.accent5, 0.75 * 0.4, inactive_bg)

Util.colors.set_hl("BeastTl", {
	-- Buffer cell: plain (no diagnostics)
	BufferSelected = { fg = p.accent3, bg = active_bg, underline = true, sp = active_border },
	BufferVisible = { fg = inactive_fg, bg = active_bg, underline = true, sp = inactive_border },
	Buffer = { fg = normal_fg, bg = inactive_bg, underline = true, sp = inactive_border },

	-- Buffer cell: diagnostic severity variants
	BufferSelectedError = { fg = error_active_fg, bg = active_bg, underline = true, sp = active_border },
	BufferVisibleError = { fg = error_visible_fg, bg = active_bg, underline = true, sp = inactive_border },
	BufferError = { fg = error_normal_fg, bg = inactive_bg, underline = true, sp = inactive_border },
	BufferSelectedWarn = { fg = warn_active_fg, bg = active_bg, underline = true, sp = active_border },
	BufferVisibleWarn = { fg = warn_visible_fg, bg = active_bg, underline = true, sp = inactive_border },
	BufferWarn = { fg = warn_normal_fg, bg = inactive_bg, underline = true, sp = inactive_border },
	BufferSelectedInfo = { fg = info_hint_active_fg, bg = active_bg, underline = true, sp = active_border },
	BufferVisibleInfo = { fg = info_hint_visible_fg, bg = active_bg, underline = true, sp = inactive_border },
	BufferInfo = { fg = info_hint_normal_fg, bg = inactive_bg, underline = true, sp = inactive_border },
	BufferSelectedHint = { fg = info_hint_active_fg, bg = active_bg, underline = true, sp = active_border },
	BufferVisibleHint = { fg = info_hint_visible_fg, bg = active_bg, underline = true, sp = inactive_border },
	BufferHint = { fg = info_hint_normal_fg, bg = inactive_bg, underline = true, sp = inactive_border },

	-- Diagnostic count indicators
	DiagErrorSelected = { fg = error_count_active_fg, bg = active_bg, bold = true, underline = true, sp = active_border },
	DiagErrorVisible = { fg = error_count_visible_fg, bg = active_bg, bold = true, underline = true, sp = inactive_border },
	DiagError = { fg = error_count_normal_fg, bg = inactive_bg, bold = true, underline = true, sp = inactive_border },
	DiagWarnSelected = { fg = warn_count_active_fg, bg = active_bg, bold = true, underline = true, sp = active_border },
	DiagWarnVisible = { fg = warn_count_visible_fg, bg = active_bg, bold = true, underline = true, sp = inactive_border },
	DiagWarn = { fg = warn_count_normal_fg, bg = inactive_bg, bold = true, underline = true, sp = inactive_border },
	DiagInfoSelected = { fg = info_hint_count_active_fg, bg = active_bg, bold = true, underline = true, sp = active_border },
	DiagInfoVisible = { fg = info_hint_count_visible_fg, bg = active_bg, bold = true, underline = true, sp = inactive_border },
	DiagInfo = { fg = info_hint_count_normal_fg, bg = inactive_bg, bold = true, underline = true, sp = inactive_border },
	DiagHintSelected = { fg = info_hint_count_active_fg, bg = active_bg, bold = true, underline = true, sp = active_border },
	DiagHintVisible = { fg = info_hint_count_visible_fg, bg = active_bg, bold = true, underline = true, sp = inactive_border },
	DiagHint = { fg = info_hint_count_normal_fg, bg = inactive_bg, bold = true, underline = true, sp = inactive_border },

	-- Modified dot
	ModifiedSelected = { fg = p.accent3, bg = active_bg, underline = true, sp = active_border },
	ModifiedVisible = { fg = p.accent3, bg = active_bg, underline = true, sp = inactive_border },
	Modified = { fg = p.accent3, bg = inactive_bg, underline = true, sp = inactive_border },

	-- Close button
	CloseButton = { fg = p.accent3, bg = active_bg, underline = true, sp = active_border },

	-- Separator between buffer cells
	Separator = { fg = p.dimmed3, bg = inactive_bg, underline = true, sp = inactive_border },
	SeparatorVisible = { fg = inactive_border, bg = active_bg, underline = true, sp = inactive_border },
	SeparatorSelected = { fg = inactive_border, bg = active_bg, underline = true, sp = active_border },

	-- Tabpages
	TabSelected = { fg = p.accent3, bg = active_bg },
	TabVisible = { fg = inactive_fg, bg = inactive_bg, bold = true },

	-- Offset (sidebar title)
	Offset = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
	OffsetSeparator = { fg = p.background, bg = p.background },

	-- Truncation markers
	TruncMarker = { fg = p.dimmed3, bg = active_bg },

	-- Fill (background)
	Fill = { bg = p.dark1, underline = true, sp = inactive_border },
})

vim.cmd("redrawtabline")
