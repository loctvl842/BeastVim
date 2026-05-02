# ADR-012: Compound-Fragment Component Model

**Status:** Accepted

**Date:** 2026-05-02

**Evidence:** `lua/beast/libs/statusline/components/init.lua` — `Beast.Statusline.Fragment` typedef; `components/mode.lua`, `components/diagnostics.lua`, `components/git_branch.lua` — multi-fragment providers; `lua/beast/libs/statusline/util.lua` — `M.assemble`

## Context

A statusline component often needs to render text with multiple highlights — diagnostics with separate colors per severity (E/W/I/H), mode with a colored mode-name and a plain trailing space, git branch with an icon in one color and the name in another. Heirline solves this with nested children components and parent-child highlight inheritance. That machinery is more than what we need for a flat list of components.

## Decision

A component's `provider` returns a **list of fragments**, where each fragment is `{ text, hl, width? }`. Each fragment can have its own highlight (string group name or `{fg, bg, bold, ...}` spec). The assembler emits `%#GroupName#text%*` per fragment, so adjacent fragments visually compose into one component while keeping their own colors.

```lua
---@class Beast.Statusline.Fragment
---@field text string
---@field hl?  string|Beast.Statusline.HighlightSpec
---@field width? integer  -- pre-computed by the engine
```

```lua
-- diagnostics: 4 fragments, 4 highlights, one component
provider = function(ctx)
    return {
        { text = "E "..err.." ",  hl = { fg = "accent1" } },
        { text = "W "..warn.." ", hl = { fg = "accent3" } },
        { text = "I "..info.." ", hl = { fg = "accent5" } },
        { text = "H "..hint,      hl = { fg = "accent4" } },
    }
end
```

The whole component is still treated as one unit by the truncation pass — the priority belongs to the component, not to individual fragments.

## Alternatives Considered

- **One highlight per component** — rejected: would force diagnostics to split into four separate components, multiplying the work the engine does for what is logically one piece of information. It also confuses truncation: if low-priority severities drop independently, the bar reorders awkwardly.
- **Heirline-style nested children with parent→child highlight merge** — rejected: gives more flexibility than we need (we don't have multi-level nesting anywhere) and adds metatable chains and ancestry tracking. The flat compound-fragment model achieves the same visual result.
- **Return a pre-built statusline string from the provider** (so each component does its own `%#…#` assembly) — rejected: forces every component author to know `%*` reset semantics and emit truncation-safe markers, and prevents the engine from pre-computing widths.

## Rationale

1. Multi-color visuals are a core need (diagnostics, mode pill) — first-class support is cleaner than working around a one-color model
2. Truncation operates on whole components — keeping fragments as a flat list means a component is atomic from the truncation perspective, exactly as desired
3. Width pre-computation per fragment in the engine (`f.width = vim.fn.strdisplaywidth(f.text)`) lets `truncate.fit` and `util.assemble` reuse the value without re-calling `strdisplaywidth`
4. The pattern is simple enough to learn from one example (open `diagnostics.lua`, copy)
5. `%*` reset between fragments makes truncation safe — no highlight bleeds across the cut point

## Consequences

- **Positive:** Multi-color components are a one-liner per fragment; engine controls assembly + truncation; pattern is extensible (a future tabline/winbar lib can reuse the fragment shape)
- **Negative:** Slightly more verbose than `{ text = "...", hl = "..." }` for single-fragment components — every provider returns a list even when it only has one element
- **Risks:** Users may try to over-compose (one giant component with 20 fragments). Mitigation is convention: if a "component" gets that big, it should be split into multiple components with priorities.

## References

- Type: `lua/beast/libs/statusline/components/init.lua` — `Beast.Statusline.Fragment`
- Assembly: `lua/beast/libs/statusline/util.lua` — `M.assemble` (emits `%#G#text%*` per fragment)
- Examples: `components/mode.lua`, `components/diagnostics.lua`, `components/git_branch.lua`
- Dev spec: `docs/dev-specs/statusline-library.md` § "Component Spec Reference"
- Related ADRs:
  - [ADR-009](009-native-statusline-replaces-heirline.md) — Native `%!` Statusline
  - [ADR-010](010-no-engine-level-statusline-cache.md) — No Engine-Level Statusline Cache
