local p = Palette.get()

Util.colors.set_hl("BeastIndent", {
	Guide = { fg = Util.colors.darken(p.dimmed3, 40) },
	Scope = { fg = p.accent3 },
	Underline = { sp = p.accent3, underline = true },
})
