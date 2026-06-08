-- =========================================================================
-- Highlight
-- =========================================================================

---@class Beast.Statusline.HighlightSpec
---@field fg? string         Hex color (#rrggbb) or palette alias (e.g. "accent1")
---@field bg? string         Hex color or palette alias
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field reverse? boolean
---@field link? string       If set, all other fields are ignored

---A highlight reference is either an existing group name (string) or a spec
---to be resolved + cached into a generated group.
---@alias Beast.Statusline.HighlightRef string|Beast.Statusline.HighlightSpec

-- =========================================================================
-- Fragment
-- =========================================================================

---A unit of rendered text emitted by a component's provider. Multiple fragments
---per component allow multi-colored output (e.g. diagnostics with E/W/I/H groups).
---@class Beast.Statusline.Fragment
---@field text string                          Displayable text. Native % items pass through.
---@field hl? Beast.Statusline.HighlightRef    Highlight to apply to this fragment.
---@field width? integer                       Pre-computed strdisplaywidth (filled by the engine).

-- =========================================================================
-- Component
-- =========================================================================

---@alias Beast.Statusline.Scope "global"|"buffer"|"window"

---Declarative table spec. Components have no `self`; `provider` receives ctx.
---@class Beast.Statusline.ComponentSpec
---@field provider fun(ctx: Beast.Statusline.Context): Beast.Statusline.Fragment[]?
---@field condition? fun(ctx: Beast.Statusline.Context): boolean
---@field update? string[]                  Autocmd events that invalidate this component's cache.
---@field scope? Beast.Statusline.Scope      Cache scope (default "global").
---@field priority? integer                  Truncation priority (higher = hidden last). Default 50.
---@field separator? string                  Override the section's default separator after this component.

-- =========================================================================
-- Render-time helpers
-- =========================================================================

---@class Beast.Statusline.VisibleItem
---@field spec Beast.Statusline.ComponentSpec
---@field fragments Beast.Statusline.Fragment[]

-- =========================================================================
-- Public API
-- =========================================================================

local M = {}

M.diagnostics = require("beast.libs.statusline.components.diagnostics")
M.encoding = require("beast.libs.statusline.components.encoding")
M.filetype = require("beast.libs.statusline.components.filetype")
M.git_branch = require("beast.libs.statusline.components.git_branch")
M.git_commit = require("beast.libs.statusline.components.git_commit")
M.macro = require("beast.libs.statusline.components.macro")
M.mode = require("beast.libs.statusline.components.mode")
M.position = require("beast.libs.statusline.components.position")
M.shiftwidth = require("beast.libs.statusline.components.shiftwidth")

return M
