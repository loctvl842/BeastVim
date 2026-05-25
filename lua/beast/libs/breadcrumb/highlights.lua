-- Beast.Breadcrumb highlight refresh hook.
-- Re-executed on every ColorScheme change via M.highlight_modules.

local p = Palette.get()

Util.colors.set_hl("BeastBc", {
	Dir = { fg = p.dimmed3 },
	Sep = { fg = p.dimmed3 },
	File = { fg = p.dimmed2 },
	Modified = { fg = p.accent3 },
})
Util.colors.set_hl("", {
	WinBar = { bg = p.background },
	WinBarNC = { bg = p.background },
})

vim.cmd("redrawstatus")
