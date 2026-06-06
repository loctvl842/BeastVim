local M = {}

function M.get()
	local p = Palette.get()
	return Util.colors.build("BeastExplorer", {
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

		-- Git status. Color = kind (what changed). Staged-only files get a
		-- dimmed variant blended toward the sidebar bg, so worktree changes
		-- read brighter than already-indexed ones. The "both" phase falls
		-- through to the full-intensity color (worktree state wins visually,
		-- matching Zed and git CLI conventions).
		GitConflict = { fg = p.accent1, bold = true },
		GitDeleted = { fg = p.accent1 },
		GitDeletedStaged = { fg = Util.colors.blend(p.accent1, 0.7, Util.colors.darken(p.dark1, 5)) },
		GitModified = { fg = p.accent2 },
		GitModifiedStaged = { fg = Util.colors.blend(p.accent2, 0.7, Util.colors.darken(p.dark1, 5)) },
		GitAdded = { fg = p.accent3 },
		GitAddedStaged = { fg = Util.colors.blend(p.accent3, 0.7, Util.colors.darken(p.dark1, 5)) },
		GitRenamed = { fg = p.accent5 },
		GitRenamedStaged = { fg = Util.colors.blend(p.accent5, 0.7, Util.colors.darken(p.dark1, 5)) },
		GitUntracked = { fg = p.accent3 },
		GitIgnored = { fg = p.dimmed4 },

		-- Sticky ancestor headers (float overlay)
		StickyBg = { fg = p.dimmed1, bg = Util.colors.darken(p.dark1, 3) },
		-- No `fg` so indent / icon / label colors on the last line still show
		-- through; only the underline (sp) is contributed by this group.
		StickyBorder = { sp = Util.colors.darken(p.dimmed3, 10), underline = true },
	})
end

return M
