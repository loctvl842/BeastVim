local p = Palette.get()

-- Palette mapping (modeled after tokyonight):
--   accent1 (pink)  → magenta/red role: variable.builtin, constructor, string.escape
--   accent2 (yellow) → yellow role: variable.parameter, string.documentation, type
--   accent3 (green)  → string role
--   accent4 (cyan)   → teal/green1 role: property, variable.member, markup.link
--   accent5 (blue)   → purple role: keywords
--   accent6 (cyan)   → constant/number role

Util.colors.set_hl("", {
	-- Identifiers
	["@variable"] = { fg = p.text },
	["@variable.builtin"] = { fg = p.accent1 },
	["@variable.member"] = { fg = p.accent4 },
	["@variable.parameter"] = { fg = p.accent2, italic = true },
	["@variable.parameter.builtin"] = { fg = p.accent2, italic = true },

	-- Constants
	["@constant"] = { link = "Constant" },
	["@constant.builtin"] = { link = "Special" },
	["@constant.macro"] = { link = "Define" },

	-- Modules & Labels
	["@module"] = { link = "Include" },
	["@module.builtin"] = { fg = p.accent1 },
	["@namespace.builtin"] = { link = "@variable.builtin" },
	["@label"] = { fg = p.accent5 },

	-- Literals
	["@string"] = { link = "String" },
	["@string.documentation"] = { fg = p.accent2 },
	["@string.escape"] = { fg = p.accent1 },
	["@string.regexp"] = { fg = p.accent6 },
	["@string.special"] = { link = "Special" },
	["@character"] = { link = "Character" },
	["@character.printf"] = { link = "SpecialChar" },
	["@character.special"] = { link = "SpecialChar" },
	["@boolean"] = { link = "Boolean" },
	["@number"] = { link = "Number" },
	["@number.float"] = { link = "Float" },

	-- Types
	["@type"] = { link = "Type" },
	["@type.builtin"] = { fg = p.accent5, italic = true },
	["@type.definition"] = { link = "Typedef" },
	["@type.qualifier"] = { link = "@keyword" },

	-- Attributes & Annotations
	["@attribute"] = { link = "PreProc" },
	["@annotation"] = { link = "PreProc" },
	["@property"] = { fg = p.accent4 },

	-- Functions
	["@function"] = { link = "Function" },
	["@function.builtin"] = { link = "Special" },
	["@function.call"] = { link = "@function" },
	["@function.macro"] = { link = "Macro" },
	["@function.method"] = { link = "Function" },
	["@function.method.call"] = { link = "@function.method" },
	["@constructor"] = { fg = p.accent1 },

	-- Operators
	["@operator"] = { fg = p.dimmed1 },

	-- Keywords
	["@keyword"] = { fg = p.accent5, italic = true },
	["@keyword.modifier"] = { link = "@keyword" },
	["@keyword.type"] = { link = "@keyword" },
	["@keyword.coroutine"] = { link = "@keyword" },
	["@keyword.function"] = { fg = p.accent1, italic = true },
	["@keyword.operator"] = { link = "@operator" },
	["@keyword.import"] = { link = "Include" },
	["@keyword.repeat"] = { link = "Repeat" },
	["@keyword.return"] = { link = "@keyword" },
	["@keyword.debug"] = { link = "Debug" },
	["@keyword.exception"] = { link = "Exception" },
	["@keyword.conditional"] = { link = "Conditional" },
	["@keyword.conditional.ternary"] = { link = "@operator" },
	["@keyword.directive"] = { link = "PreProc" },
	["@keyword.directive.define"] = { link = "Define" },
	["@keyword.storage"] = { link = "StorageClass" },
	["@keyword.export"] = { link = "@keyword" },

	-- Punctuation
	["@punctuation.bracket"] = { fg = p.dimmed1 },
	["@punctuation.delimiter"] = { fg = p.dimmed2 },
	["@punctuation.special"] = { fg = p.dimmed2 },

	-- Comments
	["@comment"] = { link = "Comment" },
	["@comment.documentation"] = { link = "Comment" },
	["@comment.error"] = { fg = p.accent1 },
	["@comment.warning"] = { fg = p.accent2 },
	["@comment.todo"] = { fg = p.accent4 },
	["@comment.hint"] = { fg = p.accent5 },
	["@comment.info"] = { fg = p.accent5 },
	["@comment.note"] = { fg = p.accent5 },

	-- Markup
	["@markup"] = { link = "@none" },
	["@markup.strong"] = { bold = true },
	["@markup.italic"] = { italic = true },
	["@markup.emphasis"] = { italic = true },
	["@markup.strikethrough"] = { strikethrough = true },
	["@markup.underline"] = { underline = true },
	["@markup.heading"] = { link = "Title" },
	["@markup.quote"] = { fg = p.text, italic = true },
	["@markup.math"] = { link = "Special" },
	["@markup.environment"] = { link = "Macro" },
	["@markup.environment.name"] = { link = "Type" },
	["@markup.link"] = { fg = p.accent4 },
	["@markup.link.label"] = { link = "SpecialChar" },
	["@markup.link.label.symbol"] = { link = "Identifier" },
	["@markup.link.url"] = { link = "Underlined" },
	["@markup.raw"] = { link = "String" },
	["@markup.raw.markdown_inline"] = { fg = p.accent5, bg = p.dark1 },
	["@markup.list"] = { fg = p.accent5 },
	["@markup.list.checked"] = { fg = p.accent3 },
	["@markup.list.unchecked"] = { fg = p.dimmed2 },
	["@markup.list.markdown"] = { fg = p.accent6, bold = true },
	["@none"] = {},

	-- Diff
	["@diff.plus"] = { link = "DiffAdd" },
	["@diff.minus"] = { link = "DiffDelete" },
	["@diff.delta"] = { link = "DiffChange" },

	-- Tags (HTML/JSX)
	["@tag"] = { link = "Label" },
	["@tag.builtin"] = { link = "Label" },
	["@tag.attribute"] = { link = "@property" },
	["@tag.delimiter"] = { link = "Delimiter" },

	-- Misc
	["@conceal"] = { link = "Conceal" },

	-- LSP semantic tokens
	["@lsp.type.comment"] = {},
	["@lsp.type.enum"] = { link = "@type" },
	["@lsp.type.interface"] = { link = "@type" },
	["@lsp.type.keyword"] = { link = "@keyword" },
	["@lsp.type.namespace"] = { link = "@module" },
	["@lsp.type.parameter"] = { link = "@variable.parameter" },
	["@lsp.type.property"] = { link = "@property" },
	["@lsp.typemod.function.defaultLibrary"] = { link = "@function.builtin" },
	["@lsp.typemod.operator.injected"] = { link = "@operator" },
	["@lsp.typemod.string.injected"] = { link = "@string" },
	["@lsp.typemod.variable.constant"] = { link = "@constant" },
	["@lsp.typemod.variable.defaultLibrary"] = { link = "@variable.builtin" },
	["@lsp.typemod.variable.injected"] = { link = "@variable" },

	-- Language specific: Lua
	["@constructor.lua"] = { link = "@punctuation.bracket" },

	-- Language specific: Markdown
	["@conceal.markdown"] = { fg = p.dimmed2 },
	["@markup.raw.block.markdown"] = { bg = p.dark1 },
	["@markup.raw.delimiter.markdown"] = { fg = p.dimmed2 },
	["@punctuation.special.markdown"] = { fg = p.accent6, bold = true },
})
