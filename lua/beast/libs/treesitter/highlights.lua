-- BeastVim treesitter highlights — diversified, role-based.
--
-- READABILITY RULES (enforced uniformly):
--   1. Members recede, calls pop. @property / @variable.member render as plain
--      text so `foo.bar()` reads as text.text-cyan(): the call jumps out.
--   2. Parameters use italic alone, not yellow. Yellow is reserved for the
--      Type family so `def f(x: Type)` doesn't paint x and Type the same hue.
--   3. Italic is meaningful: keyword OR meta-marker (builtin / parameter /
--      comment / annotation). Never decorative.
--   4. Same role across nesting levels = same color (e.g. all @function.*
--      cyan); the only modifier is italic for builtin/special variants.
--
-- ROLE → COLOR:
--   text  (plain)     → noise: @variable, @variable.member, @property
--   text  (italic)    → params: @variable.parameter*
--   cyan  (accent4)   → callables: @function*, link targets
--   sky   (accent5)   → structure: @keyword* (decl/import), @module,
--                       @function.macro, @constant.macro
--   yellow (accent2)  → shape: @type*, @constructor, @attribute*,
--                       @annotation, @tag.attribute
--   coral (accent1)   → values + flow break + builtin markers:
--                       @constant*, @number, @boolean, @string.escape,
--                       @keyword.return/conditional/repeat/exception/function,
--                       @label, @tag, @variable.builtin
--   mint  (accent3)   → content: @string, @character
--   dimmed            → scaffold: @operator, @punctuation.*, @comment
--
-- We avoid `link = "Constant"` / "Boolean" / etc. — those are unstyled under
-- `default`, so linking collapses captures to plain text.

local M = {}

function M.get()
	local p = Theme.get()
	return {
		-- Identifiers ---------------------------------------------------------
		["@variable"] = { fg = p.text },
		["@variable.member"] = { fg = p.text },
		["@variable.parameter"] = { fg = p.text, italic = true },
		["@variable.parameter.builtin"] = { fg = p.text, italic = true },
		["@variable.builtin"] = { fg = p.accent1, italic = true },
		["@property"] = { fg = p.text },
		["@field"] = { fg = p.text },

		-- Values --------------------------------------------------------------
		["@constant"] = { fg = p.accent1 },
		["@constant.builtin"] = { fg = p.accent1, italic = true },
		["@constant.macro"] = { fg = p.accent5 },
		["@boolean"] = { fg = p.accent1 },
		["@number"] = { fg = p.accent1 },
		["@number.float"] = { fg = p.accent1 },

		-- Strings -------------------------------------------------------------
		["@string"] = { fg = p.accent3 },
		["@string.documentation"] = { fg = p.dimmed3, italic = true },
		["@string.escape"] = { fg = p.accent1 },
		["@string.regexp"] = { fg = p.accent3, italic = true },
		["@string.special"] = { fg = p.accent1 },
		["@string.special.symbol"] = { fg = p.accent1 },
		["@string.special.url"] = { fg = p.accent4, underline = true },
		["@character"] = { fg = p.accent3 },
		["@character.printf"] = { fg = p.accent1 },
		["@character.special"] = { fg = p.accent1 },

		-- Types & shape -------------------------------------------------------
		["@type"] = { fg = p.accent2 },
		["@type.builtin"] = { fg = p.accent2, italic = true },
		["@type.definition"] = { fg = p.accent2 },
		["@type.qualifier"] = { fg = p.accent2, italic = true },
		["@constructor"] = { fg = p.accent2 },
		["@attribute"] = { fg = p.accent2, italic = true },
		["@attribute.builtin"] = { fg = p.accent2, italic = true },
		["@annotation"] = { fg = p.accent2, italic = true },

		-- Functions -----------------------------------------------------------
		["@function"] = { fg = p.accent4 },
		["@function.builtin"] = { fg = p.accent4, italic = true },
		["@function.call"] = { link = "@function" },
		["@function.method"] = { link = "@function" },
		["@function.method.call"] = { link = "@function" },
		["@function.macro"] = { fg = p.accent5 },

		-- Modules & labels ----------------------------------------------------
		["@module"] = { fg = p.accent5 },
		["@module.builtin"] = { fg = p.accent5, italic = true },
		["@namespace.builtin"] = { fg = p.accent1, italic = true },
		["@label"] = { fg = p.accent1 },

		-- Operators & punctuation ---------------------------------------------
		["@operator"] = { fg = p.dimmed1 },
		["@punctuation.bracket"] = { fg = p.dimmed1 },
		["@punctuation.delimiter"] = { fg = p.dimmed2 },
		["@punctuation.special"] = { fg = p.dimmed2 },

		-- Keywords ------------------------------------------------------------
		["@keyword"] = { fg = p.accent5, italic = true },
		["@keyword.modifier"] = { link = "@keyword" },
		["@keyword.coroutine"] = { link = "@keyword" },
		["@keyword.import"] = { link = "@keyword" },
		["@keyword.export"] = { link = "@keyword" },
		["@keyword.directive"] = { link = "@keyword" },
		["@keyword.directive.define"] = { link = "@keyword" },
		["@keyword.operator"] = { link = "@operator" },

		["@keyword.storage"] = { fg = p.accent2, italic = true },
		["@keyword.type"] = { fg = p.accent2, italic = true },

		["@keyword.return"] = { fg = p.accent1, italic = true },
		["@keyword.conditional"] = { fg = p.accent1, italic = true },
		["@keyword.repeat"] = { fg = p.accent1, italic = true },
		["@keyword.exception"] = { fg = p.accent1, italic = true },
		["@keyword.function"] = { fg = p.accent1, italic = true },
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

		-- Diff ----------------------------------------------------------------
		["@diff.plus"] = { link = "DiffAdd" },
		["@diff.minus"] = { link = "DiffDelete" },
		["@diff.delta"] = { link = "DiffChange" },

		-- Tags (HTML/JSX) -----------------------------------------------------
		["@tag"] = { fg = p.accent1 },
		["@tag.builtin"] = { fg = p.accent1, italic = true },
		["@tag.attribute"] = { fg = p.accent2 },
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
		["@punctuation.special.markdown"] = { fg = p.accent6, bold = true },
	}
end

return M
