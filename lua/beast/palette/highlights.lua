-- BeastVim base highlights — palette-driven, gated to builtin colorschemes.
--
-- Cyan + sky stay the dominant tone (matches Neovim `default`'s built-in
-- Function/Identifier coloring), but each role gets its own accent so the
-- buffer reads with real semantic diversity instead of two-tone blue.
--
--   cyan   (accent4) → callables  : Function, Special, Tag-attribute, property
--   cyan   (accent6) → values     : Constant, Number, Boolean, Float
--   sky    (accent5) → structure  : Keyword (italic), PreProc, Include,
--                                   Identifier, Title, Directory
--   yellow (accent2) → shape      : Type, Structure, Typedef, StorageClass,
--                                   Debug, WarningMsg, Todo
--   coral  (accent1) → flow break : Statement / Conditional / Repeat /
--                                   Exception / Label, Tag, SpecialChar,
--                                   Error
--   mint   (accent3) → content    : strings
--   dimmed           → scaffold   : Comment, Operator, Delimiter
--
-- Italic is reserved for Comment and Keyword — that's the BeastVim signature.
--
-- INVARIANT — Intro screen (`:intro`) parity with vanilla `default`:
--   Neovim's intro screen (src/nvim/version.c, do_intro_line) renders only via
--   `Special` (logo bars), `String` (diagonals + version), `Identifier`,
--   `NonText` (separators), and `SpecialKey` (`:` / `<Enter>`). We override the
--   first three below but pull their colors from accent4/3/5, which
--   `extract_builtin()` sources directly from `NvimLightCyan`/`Green`/`Blue` —
--   the exact hexes `default` uses. NonText and SpecialKey are intentionally
--   left untouched. Net effect: zero visual change to the intro screen.
--   Keep this property when editing accent4/3/5 mappings or extract_builtin().

local M = {}

function M.get()
	local p = Palette.get()
	local blend = Util.colors.blend
	return {
		-- :h group-name --------------------------------------------------------
		Comment = { fg = p.dimmed3, italic = true },

		-- Values (cyan6) — numbers, booleans, named constants.
		Constant = { fg = p.accent6 },
		Number = { fg = p.accent6 },
		Float = { fg = p.accent6 },
		Boolean = { fg = p.accent6 },

		-- Content (mint) — strings & character literals.
		String = { fg = p.accent3 },
		Character = { fg = p.accent3 },

		-- Callables & specials (cyan4) — Function is the workhorse color.
		Identifier = { fg = p.accent5 },
		Function = { fg = p.accent4 },
		Special = { fg = p.accent4 },

		-- Structure (sky) — Keyword italic is the signature; preprocessor /
		-- imports / titles share the structural sky tone but stay plain.
		Keyword = { fg = p.accent5, italic = true },
		PreProc = { fg = p.accent5 },
		Include = { fg = p.accent5 },
		Define = { fg = p.accent5 },
		Macro = { fg = p.accent5 },
		PreCondit = { fg = p.accent5 },

		-- Shape (yellow) — types and storage modifiers form their own family.
		Type = { fg = p.accent2 },
		Structure = { fg = p.accent2 },
		Typedef = { fg = p.accent2 },
		StorageClass = { fg = p.accent2 },
		Debug = { fg = p.accent2 },

		-- Flow break (coral) — `return` / `raise` / `if` etc. genuinely pop.
		Statement = { fg = p.accent1 },
		Conditional = { fg = p.accent1 },
		Repeat = { fg = p.accent1 },
		Label = { fg = p.accent1 },
		Exception = { fg = p.accent1 },
		Tag = { fg = p.accent1 },
		SpecialChar = { fg = p.accent1 },

		-- Scaffolding — quiet so syntax breathes.
		Operator = { fg = p.dimmed1 },
		Delimiter = { fg = p.dimmed2 },
		SpecialComment = { fg = p.dimmed2, italic = true },

		-- Text decoration
		Underlined = { underline = true },
		Bold = { bold = true, fg = p.text },
		Italic = { italic = true, fg = p.text },

		-- Messages & prompts
		Title = { fg = p.accent5, bold = true },
		Directory = { fg = p.accent5 },
		Question = { fg = p.accent5 },
		MoreMsg = { fg = p.accent3 },
		ModeMsg = { fg = p.text, bold = true },
		WarningMsg = { fg = p.accent2 },
		ErrorMsg = { fg = p.accent1 },

		Error = { fg = p.accent1 },
		Todo = { fg = p.background, bg = p.accent2, bold = true },

		-- Diagnostics — semantic convention: error=red, warn=yellow, info=blue, hint=green.
		DiagnosticError = { fg = p.accent1 },
		DiagnosticWarn = { fg = p.accent2 },
		DiagnosticInfo = { fg = p.accent5 },
		DiagnosticHint = { fg = p.accent3 },
		DiagnosticOk = { fg = p.accent3 },
		DiagnosticUnnecessary = { fg = p.dimmed4 },

		-- Diff — tinted backgrounds blended against Normal bg so colored fg
		-- (gitsigns, @diff.*) still reads on top.
		DiffAdd = { bg = blend(p.accent3, 0.18, p.background) },
		DiffChange = { bg = blend(p.accent5, 0.18, p.background) },
		DiffDelete = { bg = blend(p.accent1, 0.18, p.background) },
		DiffText = { bg = blend(p.accent5, 0.32, p.background) },

		-- Folds — collapsed ranges: quiet dimmed fg + faint sky tint so the
		-- fold line reads as "present but inactive" without competing with code.
		Folded = { bg = blend(p.accent5, 0.10, p.background) },
		FoldColumn = { fg = p.dimmed1, bg = p.background },

		WinSeparator = { fg = Util.colors.blend(p.text, 0.4, p.background) },
	}
end

return M
