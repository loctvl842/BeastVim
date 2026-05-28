local p = Palette.get()

-- Palette mapping (modeled after tokyonight):
--   accent1 (pink)   → magenta/red role: variable.builtin, constructor, string.escape, tags
--   accent2 (yellow) → yellow role: variable.parameter, string.documentation, type
--   accent3 (green)  → string role
--   accent4 (cyan)   → teal/green1 role: function, property, variable.member, markup.link
--   accent5 (blue)   → purple/blue role: keywords, labels, modules, headings
--   accent6 (cyan)   → constant/number role
--
-- NOTE: We intentionally avoid `link = "Constant"`, `link = "Boolean"`,
-- `link = "Macro"`, `link = "Title"`, etc. Those base groups are unstyled
-- (plain foreground) under Neovim's builtin `default` colorscheme, which would
-- collapse most treesitter captures back to white text. Setting fg explicitly
-- keeps highlights consistent across colorschemes (tokyonight-derived palette,
-- monokai-pro, builtin default).

Util.colors.set_hl("", {
	-- Identifiers
	["@variable"] = { fg = p.text },
	["@variable.builtin"] = { fg = p.accent1 },
	["@variable.member"] = { fg = p.accent4 },
	["@variable.parameter"] = { fg = p.accent2, italic = true },
	["@variable.parameter.builtin"] = { fg = p.accent2, italic = true },

	-- Constants
	["@constant"] = { fg = p.accent6 },
	["@constant.builtin"] = { fg = p.accent6, italic = true },
	["@constant.macro"] = { fg = p.accent5 },

	-- Modules & Labels
	["@module"] = { fg = p.accent5 },
	["@module.builtin"] = { fg = p.accent1 },
	["@namespace.builtin"] = { link = "@variable.builtin" },
	["@label"] = { fg = p.accent5 },

	-- Literals
	["@string"] = { fg = p.accent3 },
	["@string.documentation"] = { fg = p.accent2 },
	["@string.escape"] = { fg = p.accent1 },
	["@string.regexp"] = { fg = p.accent6 },
	["@string.special"] = { fg = p.accent1 },
	["@string.special.symbol"] = { fg = p.accent6 },
	["@string.special.url"] = { fg = p.accent4, underline = true },
	["@character"] = { fg = p.accent3 },
	["@character.printf"] = { fg = p.accent1 },
	["@character.special"] = { fg = p.accent1 },
	["@boolean"] = { fg = p.accent6 },
	["@number"] = { fg = p.accent6 },
	["@number.float"] = { fg = p.accent6 },

	-- Types
	["@type"] = { fg = p.accent2 },
	["@type.builtin"] = { fg = p.accent2, italic = true },
	["@type.definition"] = { fg = p.accent2 },
	["@type.qualifier"] = { link = "@keyword" },

	-- Attributes & Annotations
	["@attribute"] = { fg = p.accent5, italic = true },
	["@attribute.builtin"] = { fg = p.accent5, italic = true },
	["@annotation"] = { fg = p.accent5, italic = true },
	["@property"] = { fg = p.accent4 },

	-- Functions
	["@function"] = { fg = p.accent4 },
	["@function.builtin"] = { fg = p.accent4, italic = true },
	["@function.call"] = { link = "@function" },
	["@function.macro"] = { fg = p.accent5 },
	["@function.method"] = { link = "@function" },
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
	["@keyword.import"] = { fg = p.accent5, italic = true },
	["@keyword.repeat"] = { link = "@keyword" },
	["@keyword.return"] = { link = "@keyword" },
	["@keyword.debug"] = { fg = p.accent1 },
	["@keyword.exception"] = { link = "@keyword" },
	["@keyword.conditional"] = { link = "@keyword" },
	["@keyword.conditional.ternary"] = { link = "@operator" },
	["@keyword.directive"] = { fg = p.accent5, italic = true },
	["@keyword.directive.define"] = { fg = p.accent5, italic = true },
	["@keyword.storage"] = { fg = p.accent5, italic = true },
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
	["@markup.heading"] = { fg = p.accent5, bold = true },
	["@markup.quote"] = { fg = p.text, italic = true },
	["@markup.math"] = { fg = p.accent1 },
	["@markup.environment"] = { fg = p.accent5 },
	["@markup.environment.name"] = { fg = p.accent2 },
	["@markup.link"] = { fg = p.accent4 },
	["@markup.link.label"] = { fg = p.accent1 },
	["@markup.link.label.symbol"] = { fg = p.accent1 },
	["@markup.link.url"] = { fg = p.accent4, underline = true },
	["@markup.raw"] = { fg = p.accent3 },
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
	["@tag"] = { fg = p.accent1 },
	["@tag.builtin"] = { fg = p.accent1 },
	["@tag.attribute"] = { link = "@property" },
	["@tag.delimiter"] = { fg = p.dimmed2 },

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

	-- Language specific: TSX/JSX (mirror tokyonight: tag/constructor lean blue)
	["@constructor.tsx"] = { fg = p.accent5 },
	["@tag.tsx"] = { fg = p.accent1 },
	["@tag.javascript"] = { fg = p.accent1 },

	-- Language specific: Markdown
	["@conceal.markdown"] = { fg = p.dimmed2 },
	["@markup.raw.block.markdown"] = { bg = p.dark1 },
	["@markup.raw.delimiter.markdown"] = { fg = p.dimmed2 },
	["@punctuation.special.markdown"] = { fg = p.accent6, bold = true },
})
