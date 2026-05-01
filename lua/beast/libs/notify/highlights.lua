local p = Palette.get()

Util.colors.set_hl("BeastNotify", {
	Border = { bg = p.dimmed5, fg = p.background },
	Normal = { bg = p.dimmed5, fg = p.dimmed2 },

  ERROR = { link = "DiagnosticError" },
  WARN = { link = "DiagnosticWarn" },
  INFO = { link = "DiagnosticInfo" },
  DEBUG = { link = "DiagnosticHint" },
  TRACE = { link = "Comment" },
})
