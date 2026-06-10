-- BeastVim blink.cmp highlights — palette-driven, applied through the same
-- ColorScheme-reload pipeline as every other lib (see beast/hl_reload.lua).
--
-- Maps blink kind groups to the same semantic accents used by
-- beast.theme.highlights so the popup reads as part of the buffer, not as
-- a foreign overlay:
--
--   accent4 cyan   → callables  (Function, Method, Constructor)
--   accent5 sky    → structure  (Variable, Field, Property, Module, ...)
--   accent2 yellow → shape      (Class, Interface, Struct, Enum, TypeParam)
--   accent1 coral  → flow       (Keyword, Operator)
--   accent3 mint   → content    (String, Text, Snippet, AI sources)
--   accent6 cyan6  → values     (Number, Boolean, Constant, EnumMember)
--   dimmed         → scaffold   (Menu chrome, source name, kind fallback)
--
-- BlinkCmpLabelMatch uses accent2 + bold so the fuzzy-matched characters
-- pop without re-coloring the whole label. BlinkCmpMenuSelection uses dark2
-- as its background to mirror the statusline's selected-tab treatment.

local M = {}

function M.get()
	local p = Theme.get()

	local callables = p.accent4 -- cyan  → Function / Method / Constructor
	local structure = p.accent5 -- sky   → Variable / Field / Property / Module
	local shape = p.accent2 -- yellow → Class / Interface / Struct / Enum
	local flow = p.accent1 -- coral  → Keyword / Operator
	local content = p.accent3 -- mint  → String / Text / Snippet / AI
	local values = p.accent6 -- cyan6 → Number / Boolean / Constant

	local menu_bg = p.dark1
	local menu_sel_bg = p.dark2
	local border_fg = p.dimmed3

	return {
		-- Containers ----------------------------------------------------------
		BlinkCmpMenu = { fg = p.text, bg = menu_bg },
		BlinkCmpMenuBorder = { fg = border_fg, bg = menu_bg },
		BlinkCmpMenuSelection = { bg = menu_sel_bg, bold = true },
		BlinkCmpScrollBarThumb = { bg = p.dimmed4 },
		BlinkCmpScrollBarGutter = { bg = menu_bg },

		-- Documentation pane --------------------------------------------------
		BlinkCmpDoc = { fg = p.text, bg = menu_bg },
		BlinkCmpDocBorder = { fg = border_fg, bg = menu_bg },
		BlinkCmpDocSeparator = { fg = border_fg, bg = menu_bg },
		BlinkCmpDocCursorLine = { bg = menu_sel_bg },

		-- Signature help ------------------------------------------------------
		BlinkCmpSignatureHelp = { fg = p.text, bg = menu_bg },
		BlinkCmpSignatureHelpBorder = { fg = border_fg, bg = menu_bg },
		BlinkCmpSignatureHelpActiveParameter = { fg = shape, bold = true },

		-- Labels --------------------------------------------------------------
		BlinkCmpLabel = { fg = p.text },
		BlinkCmpLabelDeprecated = { fg = p.dimmed3, strikethrough = true },
		BlinkCmpLabelMatch = { fg = shape, bold = true },
		BlinkCmpLabelDescription = { fg = p.dimmed2 },
		BlinkCmpLabelDetail = { fg = p.dimmed2 },
		BlinkCmpSource = { fg = p.dimmed2 },
		BlinkCmpGhostText = { fg = p.dimmed4, italic = true },

		-- Kind icons & labels — fallback --------------------------------------
		BlinkCmpKind = { fg = p.dimmed1 },

		-- Callables (cyan)
		BlinkCmpKindFunction = { fg = callables },
		BlinkCmpKindMethod = { fg = callables },
		BlinkCmpKindConstructor = { fg = callables },

		-- Structure (sky)
		BlinkCmpKindVariable = { fg = structure },
		BlinkCmpKindField = { fg = structure },
		BlinkCmpKindProperty = { fg = structure },
		BlinkCmpKindModule = { fg = structure },
		BlinkCmpKindNamespace = { fg = structure },
		BlinkCmpKindPackage = { fg = structure },
		BlinkCmpKindReference = { fg = structure },
		BlinkCmpKindEvent = { fg = structure },
		BlinkCmpKindKey = { fg = structure },

		-- Shape (yellow)
		BlinkCmpKindClass = { fg = shape },
		BlinkCmpKindInterface = { fg = shape },
		BlinkCmpKindStruct = { fg = shape },
		BlinkCmpKindEnum = { fg = shape },
		BlinkCmpKindTypeParameter = { fg = shape },

		-- Flow (coral)
		BlinkCmpKindKeyword = { fg = flow },
		BlinkCmpKindOperator = { fg = flow },

		-- Content (mint)
		BlinkCmpKindString = { fg = content },
		BlinkCmpKindText = { fg = content },
		BlinkCmpKindSnippet = { fg = content },
		BlinkCmpKindCopilot = { fg = content },
		BlinkCmpKindCodeium = { fg = content },
		BlinkCmpKindTabNine = { fg = content },
		BlinkCmpKindSupermaven = { fg = content },

		-- Values (cyan6)
		BlinkCmpKindNumber = { fg = values },
		BlinkCmpKindBoolean = { fg = values },
		BlinkCmpKindConstant = { fg = values },
		BlinkCmpKindEnumMember = { fg = values },
		BlinkCmpKindValue = { fg = values },

		-- Scaffold (dimmed)
		BlinkCmpKindFile = { fg = p.dimmed1 },
		BlinkCmpKindFolder = { fg = p.dimmed1 },
		BlinkCmpKindUnit = { fg = p.dimmed2 },
		BlinkCmpKindColor = { fg = p.dimmed2 },
		BlinkCmpKindArray = { fg = p.dimmed1 },
		BlinkCmpKindObject = { fg = p.dimmed1 },
		BlinkCmpKindNull = { fg = p.dimmed3, italic = true },
		BlinkCmpKindDefault = { fg = p.dimmed1 },
	}
end

return M
