local p = Palette.get()

Util.colors.set_hl("", {
	-- Annotations & Attributes
	["@annotation"] = { fg = p.accent5, italic = true },
	["@attribute"] = { fg = p.accent4 },

	-- Booleans & Constants
	["@boolean"] = { fg = p.accent6 },
	["@constant"] = { fg = p.accent6 },
	["@constant.builtin"] = { fg = p.accent6 },
	["@constant.macro"] = { fg = p.accent6 },

	-- Constructors & Fields
	["@constructor"] = { fg = p.accent4 },
	["@field"] = { fg = p.accent1 },

	-- Diff Changes
	["@diff.delta"] = { fg = p.accent3 },
	["@diff.minus"] = { fg = p.accent1 },
	["@diff.plus"] = { fg = p.accent4 },

	-- Functions & Methods
	["@function"] = { fg = p.accent4 },
	["@function.builtin"] = { fg = p.accent4 },
	["@function.call"] = { fg = p.accent4 },
	["@function.macro"] = { fg = p.accent4 },
	["@function.method"] = { fg = p.accent4 },
	["@function.method.call"] = { fg = p.accent4 },

	-- Keywords
	["@keyword"] = { fg = p.accent1, italic = true },
	["@keyword.conditional"] = { fg = p.accent1 },
	["@keyword.coroutine"] = { fg = p.accent1 },
	["@keyword.debug"] = { fg = p.accent1 },
	["@keyword.directive"] = { fg = p.accent1 },
	["@keyword.directive.define"] = { fg = p.accent1 },
	["@keyword.exception"] = { fg = p.accent1 },
	["@keyword.function"] = { fg = p.accent5, italic = true },
	["@keyword.import"] = { fg = p.accent1 },
	["@keyword.operator"] = { fg = p.accent1 },
	["@keyword.repeat"] = { fg = p.accent1 },
	["@keyword.return"] = { fg = p.accent1 },
	["@keyword.storage"] = { fg = p.accent1 },
	["@keyword.type"] = { fg = p.accent5, italic = true },

	-- Numbers & Operators
	["@number"] = { fg = p.accent6 },
	["@number.float"] = { fg = p.accent6 },
	["@operator"] = { fg = p.accent1 },

	-- Parameters & Variables
	["@variable"] = { fg = p.text },
	["@variable.builtin"] = { fg = p.dimmed1, italic = true },
	["@variable.member"] = { fg = p.text },
	["@variable.parameter"] = { fg = p.accent2, italic = true },
	["@variable.parameter.builtin"] = { fg = p.accent2, italic = true },

	-- Punctuation
	["@punctuation.bracket"] = { fg = p.accent1 },
	["@punctuation.delimiter"] = { fg = p.dimmed2 },
	["@punctuation.special"] = { fg = p.dimmed2 },

	-- Strings & Characters
	["@string"] = { fg = p.accent3 },
	["@string.documentation"] = { fg = p.dimmed3 },
	["@string.escape"] = { fg = p.accent6 },
	["@string.regexp"] = { fg = p.accent3 },
	["@character"] = { fg = p.accent3 },
	["@character.printf"] = { fg = p.accent3 },
	["@character.special"] = { fg = p.accent3 },

	-- Tags & Markup
	["@tag"] = { fg = p.accent1 },
	["@tag.attribute"] = { fg = p.accent5, italic = true },
	["@tag.builtin"] = { fg = p.accent1 },
	["@tag.delimiter"] = { fg = p.dimmed2 },

	-- Markup Highlight Groups
	["@markup"] = { fg = p.text },
	["@markup.emphasis"] = { fg = p.text, italic = true },
	["@markup.environment"] = { fg = p.text },
	["@markup.environment.name"] = { fg = p.text },
	["@markup.heading"] = { fg = p.accent4, bold = true },
	["@markup.italic"] = { fg = p.text, italic = true },
	["@markup.link"] = { fg = p.accent2, underline = true },
	["@markup.link.label"] = { fg = p.accent2, underline = true },
	["@markup.link.label.symbol"] = { fg = p.accent2, underline = true },
	["@markup.link.url"] = { fg = p.accent2, underline = true },
	["@markup.list"] = { fg = p.text },
	["@markup.list.checked"] = { fg = p.text },
	["@markup.list.markdown"] = { fg = p.text },
	["@markup.list.unchecked"] = { fg = p.text },
	["@markup.math"] = { fg = p.accent3 },
	["@markup.raw"] = { fg = p.accent3 },
	["@markup.raw.markdown_inline"] = { fg = p.accent3 },
	["@markup.strikethrough"] = { fg = p.text, strikethrough = true },
	["@markup.strong"] = { fg = p.text, bold = true },
	["@markup.underline"] = { fg = p.text, underline = true },

	-- Types
	["@type"] = { fg = p.accent5 },
	["@type.builtin"] = { fg = p.accent5, italic = true },
	["@type.definition"] = { fg = p.accent4 },
	["@type.qualifier"] = { fg = p.accent5 },
	["@module"] = { fg = p.accent5 },
	["@module.builtin"] = { fg = p.accent5 },
	["@namespace.builtin"] = { fg = p.accent5 },

	-- Labels
	["@label"] = { fg = p.accent5 },

	-- Language specific: C++
	["@constant.cpp"] = { fg = p.accent5 },
	["@constant.macro.cpp"] = { fg = p.accent1 },
	["@keyword.cpp"] = { fg = p.accent5, italic = true },
	["@namespace.cpp"] = { fg = p.accent4 },
	["@operator.cpp"] = { fg = p.accent1 },
	["@punctuation.delimiter.cpp"] = { fg = p.dimmed2 },
	["@type.cpp"] = { fg = p.accent2, italic = true },
	["@variable.cpp"] = { fg = p.text },

	-- Language specific: Dockerfile/Bash
	["@function.call.bash"] = { fg = p.accent4 },
	["@keyword.dockerfile"] = { fg = p.accent1 },
	["@lsp.type.class.dockerfile"] = { fg = p.accent5 },
	["@parameter.bash"] = { fg = p.text },

	-- Language specific: Go
	["@keyword.function.go"] = { fg = p.accent1 },
	["@module.go"] = { fg = p.text },
	["@string.escape.go"] = { fg = p.accent6 },

	-- Language specific: LaTeX
	["@function.macro.latex"] = { fg = p.accent4 },
	["@punctuation.special.latex"] = { fg = p.accent1 },
	["@string.latex"] = { fg = p.accent5 },
	["@text.emphasis.latex"] = { italic = true },
	["@text.environment.latex"] = { fg = p.accent4 },
	["@text.environment.name.latex"] = { fg = p.accent2, italic = true },
	["@text.math.latex"] = { fg = p.accent6 },
	["@text.strong.latex"] = { bold = true },

	-- Language specific: Markdown
	["@conceal.markdown"] = { bg = p.dark1 },
	["@markup.italic.markdown_inline"] = { italic = true },
	["@markup.link.label.markdown_inline"] = { fg = p.accent1 },
	["@markup.link.url.markdown_inline"] = { fg = p.accent4, underline = true },
	["@markup.raw.block.markdown"] = { bg = p.dark1 },
	["@markup.raw.delimiter.markdown"] = { bg = p.dark1, fg = p.dimmed2 },
	["@markup.strong.markdown_inline"] = { bold = true },
	["@none.markdown"] = { bg = p.dark1 },
	["@punctuation.special.markdown"] = { fg = p.dimmed2 },
	["@text.emphasis.markdown_inline"] = { fg = p.text, italic = true },
	["@text.literal.block.markdown"] = { bg = p.background },
	["@text.literal.markdown_inline"] = { bg = p.dimmed4, fg = p.text },
	["@text.quote.markdown"] = { bg = p.dimmed5, fg = p.text },
	["@text.reference.markdown_inline"] = { fg = p.accent1 },
	["@text.strong.markdown_inline"] = { bold = true },
	["@text.uri.markdown_inline"] = { fg = p.accent4, sp = p.accent4, underline = true },

	-- Language specific: SCSS
	["@function.scss"] = { fg = p.accent5 },
	["@keyword.scss"] = { fg = p.accent1 },
	["@number.scss"] = { fg = p.accent6 },
	["@property.scss"] = { fg = p.accent4 },
	["@string.scss"] = { fg = p.accent2, italic = true },
	["@type.scss"] = { fg = p.accent5 },

	-- Language specific: Lua
	["@comment.documentation.lua"] = { fg = p.accent5 },
	["@conditional.lua"] = { fg = p.accent1 },
	["@field.lua"] = { fg = p.text },
	["@function.builtin.lua"] = { fg = p.accent4 },
	["@keyword.function.lua"] = { fg = p.accent1 },
	["@keyword.lua"] = { fg = p.accent1, italic = true },
	["@namespace.lua"] = { fg = p.accent1 },
	["@parameter.lua"] = { fg = p.accent2, italic = true },
	["@variable.lua"] = { fg = p.text },

	-- Language specific: YAML
	["@number.yaml"] = { fg = p.accent6 },
	["@property.yaml"] = { fg = p.accent1 },
	["@punctuation.special.yaml"] = { fg = p.text },
	["@string.yaml"] = { fg = p.accent3 },
})
