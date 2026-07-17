---
name: explorer-highlights-palette
description: "Explorer Highlights with Beast Palette"
generated: 2026-05-01
---

# Dev Spec: Explorer Highlights with Beast Palette

## Summary

Redesign the explorer's `highlights.lua` to use `Beast.Palette` for all color values, following the sidebar pattern from monokai-pro (distinct sidebar background, muted foreground, themed cursor/selection). Add missing highlight groups (Normal background, CursorLine, WinSeparator, Git status, RootName) and expose an `M.apply()` function for reload on ColorScheme change.

## Requirements

- Explorer sidebar has a distinct background (darker than editor — `Palette.dark1`)
- Text in explorer uses a muted foreground (`Palette.dimmed2`)
- CursorLine is visible against the sidebar background (`Palette.dimmed5`)
- Root header is bold and uses section header color (`Palette.dimmed1`)
- Directory icons/names are slightly brighter than plain files
- Indent markers use a very dim color (`Palette.dimmed4`)
- Hidden files use comment-level dimming (`Palette.dimmed3`)
- Clipboard indicator uses accent color (`Palette.accent5`)
- WinSeparator between explorer and editor is subtle
- Git status colors use accent1 (deleted), accent2 (modified), accent4 (added), accent6 (untracked)
- All highlights reload on colorscheme change via `M.apply()`

## Research

### Repo Search
- Searched for: `BeastExplorer` highlight usage across all explorer files
- Found: 11 highlight groups currently referenced: `Normal`, `Title`, `Dir`, `File`, `Indent`, `Comment`, `Clip`, `Cursor` (in autocmds.lua)
- Also found: `winhighlight = "Normal:BeastExplorerNormal"` in ui.lua
- Reuse opportunity: **Yes** — keep existing group names, add new ones, replace definitions with Palette-based values

### Package Search
- Searched Neovim ecosystem: sidebar highlight patterns
- Found: neo-tree.lua from monokai-pro (user-provided reference) — shows distinct sidebar bg/fg, CursorLine, WinSeparator, Git status highlights
- Decision: **Build** — use the reference pattern adapted to Beast.Palette fields

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/explorer/highlights.lua` | **Rewrite** | Palette-based highlights with `M.apply()` |
| `lua/beast/libs/explorer/ui.lua` | **Modify** | Add winhighlight for CursorLine + WinSeparator |

## Implementation Phases

### Phase 1: Explorer highlights using Palette

1. **Rewrite `explorer/highlights.lua` with Palette** (File: `lua/beast/libs/explorer/highlights.lua`)
   - Action: Use `Palette.get()` at the top level and call `Util.colors.set_hl("BeastExplorer", {...})` directly — no wrapper function needed. Define groups: Normal (sidebar bg/fg), Title (bold, dimmed1), Dir, File, Indent, Comment, Clip, CursorLine, WinSeparator, Cursor, GitAdded, GitModified, GitDeleted, GitUntracked. The reload mechanism in `beast/init.lua` will clear the module from `package.loaded` and re-require it.
   - Why: Simplest possible pattern — just top-level code that reads Palette and sets highlights
   - Depends on: None (Palette module already exists)
   - Risk: Low

2. **Update ui.lua winhighlight** (File: `lua/beast/libs/explorer/ui.lua`)
   - Action: Expand `winhighlight` to also remap `CursorLine` and `WinSeparator` to BeastExplorer variants.
   - Why: Explorer split needs its own cursor line and separator styling
   - Depends on: Step 1
   - Risk: Low

## Testing Strategy

- Manual verification: Open explorer, confirm sidebar has distinct background from editor
- Manual verification: CursorLine is visible when navigating
- Manual verification: Switch colorscheme → explorer highlights update
- Manual verification: `:hi BeastExplorerNormal` shows Palette-derived colors

## Risks & Mitigations

- **Risk**: Some themes have very light sidebar bg making text unreadable → **Mitigation**: Palette extracts from standard groups; fallback defaults are reasonable dark values
- **Risk**: Existing render.lua references stay correct → **Mitigation**: Keep all existing group names unchanged, only add new ones

## Success Criteria

- [ ] Explorer has distinct sidebar background (not same as editor Normal)
- [ ] CursorLine is themed for the sidebar
- [ ] Indent markers, titles, files show palette-appropriate colors
- [ ] `:colorscheme X` re-applies all BeastExplorer* groups automatically
- [ ] No regression in existing explorer rendering
