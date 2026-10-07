-- BeastVim treesitter highlights - role-based, mapped from monokai-pro.nvim.
--
-- Source of truth: monokai-pro.nvim `theme/plugins/treesitter.lua`. Its
-- `c.base.*` names map to palette keys (see `theme/scheme.lua`):
--   red → accent1, orange ("blue") → accent2, yellow → accent3,
--   green → accent4, cyan → accent5, magenta → accent6, white → text.
--
-- ROLE → COLOR:
--   text   (plain)    → noise: @variable, @variable.member, @property, @markup.list*
--   orange (accent2)  → params: @variable.parameter* (italic), @markup.link*
--   red    (accent1)  → flow + syntax: @keyword*, @operator, @punctuation.bracket,
--                       @tag, @field
--   yellow (accent3)  → content: @string*, @character*, @markup.raw, @markup.math
--   green  (accent4)  → callables + shape: @function*, @constructor, @attribute*,
--                       @type.definition, @markup.heading
--   cyan   (accent5)  → types + names: @type*, @module*, @label, @annotation,
--                       @tag.attribute, @keyword.function, @keyword.type
--   purple (accent6)  → values: @constant*, @boolean, @number, @string.escape
--   dimmed            → scaffold: @punctuation.delimiter/special, @comment
--
-- We avoid `link = "Constant"` / "Boolean" / etc. - those are unstyled under
-- `default`, so linking collapses captures to plain text.

local M = {}

function M.get()
  if Theme.kind() == "plugin" then return end
	local p = Theme.get()
	return {
		-- Identifiers ---------------------------------------------------------
		["@variable"] = { fg = p.text },
		["@variable.member"] = { fg = p.text },
		["@variable.parameter"] = { fg = p.accent2, italic = true },
		["@variable.parameter.builtin"] = { fg = p.accent2, italic = true },
		["@variable.builtin"] = { fg = p.dimmed1, italic = true },
		["@property"] = { fg = p.text },
		["@field"] = { fg = p.accent1 },

		-- Values --------------------------------------------------------------
		["@constant"] = { fg = p.accent6 },
		["@constant.builtin"] = { fg = p.accent6, italic = true },
		["@constant.macro"] = { fg = p.accent6 },
		["@boolean"] = { fg = p.accent6 },
		["@number"] = { fg = p.accent6 },
		["@number.float"] = { fg = p.accent6 },

		-- Strings -------------------------------------------------------------
		["@string"] = { fg = p.accent3 },
		["@string.documentation"] = { fg = p.dimmed3 },
		["@string.escape"] = { fg = p.accent6 },
		["@string.regexp"] = { fg = p.accent3, italic = true },
		["@string.special"] = { fg = p.accent1 },
		["@string.special.symbol"] = { fg = p.accent1 },
		["@string.special.url"] = { fg = p.accent4, underline = true },
		["@character"] = { fg = p.accent3 },
		["@character.printf"] = { fg = p.accent3 },
		["@character.special"] = { fg = p.accent3 },

		-- Types & shape -------------------------------------------------------
		["@type"] = { fg = p.accent5 },
		["@type.builtin"] = { fg = p.accent5, italic = true },
		["@type.definition"] = { fg = p.accent4 },
		["@type.qualifier"] = { fg = p.accent5, italic = true },
		["@constructor"] = { fg = p.accent4 },
		["@attribute"] = { fg = p.accent4, italic = true },
		["@attribute.builtin"] = { fg = p.accent4, italic = true },
		["@annotation"] = { fg = p.accent5, italic = true },

		-- Functions -----------------------------------------------------------
		["@function"] = { fg = p.accent4 },
		["@function.builtin"] = { fg = p.accent4, italic = true },
		["@function.call"] = { link = "@function" },
		["@function.method"] = { link = "@function" },
		["@function.method.call"] = { link = "@function" },
		["@function.macro"] = { fg = p.accent4 },

		-- Modules & labels ----------------------------------------------------
		["@module"] = { fg = p.accent5 },
		["@module.builtin"] = { fg = p.accent5, italic = true },
		["@namespace.builtin"] = { fg = p.accent5, italic = true },
		["@label"] = { fg = p.accent5 },

		-- Operators & punctuation ---------------------------------------------
		["@operator"] = { fg = p.accent1 },
		["@punctuation.bracket"] = { fg = p.accent1 },
		["@punctuation.delimiter"] = { fg = p.dimmed2 },
		["@punctuation.special"] = { fg = p.dimmed2 },

		-- Keywords ------------------------------------------------------------
		["@keyword"] = { fg = p.accent1, italic = true },
		["@keyword.modifier"] = { link = "@keyword" },
		["@keyword.coroutine"] = { link = "@keyword" },
		["@keyword.import"] = { link = "@keyword" },
		["@keyword.export"] = { link = "@keyword" },
		["@keyword.directive"] = { link = "@keyword" },
		["@keyword.directive.define"] = { link = "@keyword" },
		["@keyword.operator"] = { link = "@operator" },

		["@keyword.storage"] = { fg = p.accent1, italic = true },
		["@keyword.type"] = { fg = p.accent5, italic = true },

		["@keyword.return"] = { fg = p.accent1, italic = true },
		["@keyword.conditional"] = { fg = p.accent1, italic = true },
		["@keyword.repeat"] = { fg = p.accent1, italic = true },
		["@keyword.exception"] = { fg = p.accent1, italic = true },
		["@keyword.function"] = { fg = p.accent5, italic = true },
		["@keyword.debug"] = { fg = p.accent1, italic = true },
		["@keyword.conditional.ternary"] = { link = "@operator" },

		-- Comments ------------------------------------------------------------
		["@comment"] = { link = "Comment" },
		["@comment.documentation"] = { link = "Comment" },
		["@comment.error"] = { fg = p.accent1 },
		["@comment.warning"] = { fg = p.accent2 },
		["@comment.todo"] = { fg = p.accent4 },
		["@comment.hint"] = { fg = p.accent3 },
		["@comment.info"] = { fg = p.accent5 },
		["@comment.note"] = { fg = p.accent5 },

		-- Markup --------------------------------------------------------------
		["@markup"] = { link = "@none" },
		["@markup.strong"] = { bold = true },
		["@markup.italic"] = { italic = true },
		["@markup.emphasis"] = { italic = true },
		["@markup.strikethrough"] = { strikethrough = true },
		["@markup.underline"] = { underline = true },
		["@markup.heading"] = { fg = p.accent4, bold = true },
		["@markup.quote"] = { fg = p.text, italic = true },
		["@markup.math"] = { fg = p.accent3 },
		["@markup.environment"] = { fg = p.text },
		["@markup.environment.name"] = { fg = p.text },
		["@markup.link"] = { fg = p.accent2, underline = true },
		["@markup.link.label"] = { fg = p.accent2, underline = true },
		["@markup.link.label.symbol"] = { fg = p.accent2, underline = true },
		["@markup.link.url"] = { fg = p.accent2, underline = true },
		["@markup.raw"] = { fg = p.accent3 },
		["@markup.raw.markdown_inline"] = { fg = p.accent3, bg = p.dark1 },
		["@markup.list"] = { fg = p.text },
		["@markup.list.checked"] = { fg = p.text },
		["@markup.list.unchecked"] = { fg = p.text },
		["@markup.list.markdown"] = { fg = p.text, bold = true },
		["@none"] = {},

		-- Diff ----------------------------------------------------------------
		["@diff.plus"] = { link = "DiffAdd" },
		["@diff.minus"] = { link = "DiffDelete" },
		["@diff.delta"] = { link = "DiffChange" },

		-- Tags (HTML/JSX) -----------------------------------------------------
		["@tag"] = { fg = p.accent1 },
		["@tag.builtin"] = { fg = p.accent1, italic = true },
		["@tag.attribute"] = { fg = p.accent5 },
		["@tag.delimiter"] = { fg = p.dimmed2 },

		-- Misc ----------------------------------------------------------------
		["@conceal"] = { link = "Conceal" },

		-- LSP semantic tokens -------------------------------------------------
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

		-- Language-specific ---------------------------------------------------
		["@constructor.lua"] = { link = "@punctuation.bracket" },
		["@constructor.tsx"] = { fg = p.accent5 },
		["@tag.tsx"] = { fg = p.accent1 },
		["@tag.javascript"] = { fg = p.accent1 },
		["@conceal.markdown"] = { fg = p.dimmed2 },
		["@markup.raw.block.markdown"] = { bg = p.dark1 },
		["@markup.raw.delimiter.markdown"] = { fg = p.dimmed2 },
		["@punctuation.special.markdown"] = { fg = p.dimmed2 },
	}
end

return M
