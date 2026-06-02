local p = Palette.get()

Util.colors.set_hl("BeastExplorer", {
	-- Sidebar base
	Normal = { fg = p.dimmed2, bg = Util.colors.darken(p.dark1, 5) },
	WinBar = { bg = Util.colors.darken(p.dark1, 1), sp = Util.colors.darken(p.dimmed5, 10), underline = true },
	EndOfBuffer = { fg = p.dark1, bg = Util.colors.darken(p.dark1, 5) },
	CursorLine = { bg = Util.colors.lighten(p.dark1, 30) },
	WinSeparator = { fg = p.background, bg = p.background },

	Prompt = { bg = Util.colors.lighten(p.dark1, 20), fg = Util.colors.darken(p.text, 20) },

	-- Tree structure
	Title = { fg = p.dimmed1, bold = true },
	Dir = { fg = p.dimmed1 },
	File = { fg = p.dimmed2 },
	Indent = { fg = Util.colors.darken(p.dimmed3, 30) },
	Comment = { fg = p.dimmed3 },
	Clip = { fg = p.accent5 },
	Cursor = { blend = 100, nocombine = true },

	-- Git status (by phase: glyph kind is independent, color is by phase).
	GitUnstaged = { fg = p.accent2 }, -- yellow/orange: unstaged only
	GitStaged = { fg = p.accent3 }, -- green-ish: staged only
	GitBoth = { fg = p.accent4 }, -- red-ish: both staged & unstaged
	GitConflict = { fg = p.accent2 }, -- attention: merge conflict
	GitUntracked = { fg = p.dimmed1 },
	GitIgnored = { fg = p.dimmed4 },

	-- Sticky ancestor headers (float overlay)
	StickyBg = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
	-- No `fg` so indent / icon / label colors on the last line still show
	-- through; only the underline (sp) is contributed by this group.
	StickyBorder = { sp = Util.colors.darken(p.dimmed3, 10), underline = true },
})
