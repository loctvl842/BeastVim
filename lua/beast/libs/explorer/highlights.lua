local p = Palette.get()

Util.colors.set_hl("BeastExplorer", {
	-- Sidebar base
	Normal = { fg = p.dimmed2, bg = p.dark1 },
  WinBar = { bg = Util.colors.darken(p.dark1, 1), sp = p.dimmed5, underline = true },
	EndOfBuffer = { fg = p.dark1, bg = p.dark1 },
	CursorLine = { bg = Util.colors.lighten(p.dark1, 30) },
	WinSeparator = { fg = p.background, bg = p.background },

	-- Tree structure
	Title = { fg = p.dimmed1, bold = true },
	Dir = { fg = p.dimmed1 },
	File = { fg = p.dimmed2 },
	Indent = { fg = p.dimmed4 },
	Comment = { fg = p.dimmed3 },
	Clip = { fg = p.accent5 },
	Cursor = { blend = 100, nocombine = true },

	-- Git status
	GitAdded = { fg = p.accent4 },
	GitModified = { fg = p.accent2 },
	GitDeleted = { fg = p.accent1 },
	GitUntracked = { fg = p.accent6 },
})
