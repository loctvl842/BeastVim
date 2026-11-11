---
name: finder-colorscheme-stable-menu
description: Freeze the colorscheme picker's colors in per-window highlight namespaces and drop its backdrop
generated: 2026-11-11
---

> PM Spec: [docs/pm-specs/finder-colorscheme-stable-menu.md](../pm-specs/finder-colorscheme-stable-menu.md)

# Summary
At open time the colorscheme picker copies every `BeastFinder*` highlight (plus `Normal`/`NormalFloat`/`FloatBorder`/`EndOfBuffer` per panel) into two window-local highlight namespaces, one for the prompt panel and one for the list panel, and attaches them with `nvim_win_set_hl_ns`. `:colorscheme` during live preview rewrites only global highlights, so the panels keep their snapshot colors. The backdrop is made opt-out and turned off for this picker.

---

# Context

## Problem
Picker colors are global groups rebuilt by `hl_reload` on every `ColorScheme`, so each preview repaints the picker. The backdrop overlay also dims the editor being previewed.

### Solution
`highlights.freeze()` builds the two namespaces from the current palette. `state.lua` attaches them when `opts.freeze_colors` is set, swatch groups are defined into the list namespace, and the old per-picker swatch reset hook is removed. `opts.backdrop = false` skips creating the overlay.

---

# Research

### Repo Search
- Searched for: `backdrop` (state.lua, ui/backdrop.lua, config.lua), `winhl` (ui/list.lua, ui/input.lua), `swatch`/`reset_swatches` (highlights.lua, autocmds.lua), `hl_reload` ColorScheme handler, `apply_highlights`.
- Found:
  - `state.lua` creates the backdrop unconditionally; `reset` already guards `if self.view.backdrop`, but `relayout` calls `self.view.backdrop:is_valid()` unguarded.
  - Panel colors reach windows through `winhl` mappings to `BeastFinderCardList` / `BeastFinderCardInputNormal` / `BeastFinderCardInputBorder`; all groups come from `highlights.get()` via `Util.colors.build`.
  - `hl_reload.reload_highlights()` re-sets those global groups on every `ColorScheme` (scheduled).
  - The swatch `ColorScheme` autocmd + `reset_swatches()` exist only because previews wipe global groups.
- Reuse opportunity: Yes - `highlights.get()` already returns the full group table, so the snapshot is "copy these defs into a namespace".

### Built-in / Existing Lib Check
- Checked: `nvim_set_hl(ns, ...)`, `nvim_win_set_hl_ns`, `nvim_get_hl_ns`, `winhl`.
- Found (verified by spike in a real nvim, tmux): a float given `nvim_win_set_hl_ns` keeps ns-defined `Normal`, `NormalFloat`, `FloatBorder` and extmark `hl_group` colors across `:colorscheme` (panel bg stayed `#112233` while the editor bg went dark to light). `winhl` mappings do NOT resolve through the namespace, so base groups must be defined directly in the ns.
- Decision: **Use** window namespaces; **Reuse** `highlights.get()`; **Build** `freeze()` and the opt-in plumbing.

---

# Architecture Changes
- Modified `lua/beast/libs/finder/highlights.lua` - add `freeze()` returning `{ input = ns, list = ns }`, route `swatch(hex)` into the active list namespace, delete `reset_swatches`.
- Modified `lua/beast/libs/finder/state.lua` - `opts.backdrop == false` skips the overlay, `relayout` guards a missing backdrop, `opts.freeze_colors` calls `freeze()` and attaches the namespaces to the input and list windows.
- Modified `lua/beast/libs/finder/ui/list.lua`, `ui/input.lua` - stop setting `winhl` for card style (it is a no-op under a namespace); base groups come from the namespace.
- Modified `lua/beast/libs/finder/autocmds.lua` - remove the swatch `ColorScheme` autocmd.
- Modified `lua/beast/init.lua` - `<leader>c` passes `backdrop = false, freeze_colors = true`.
- New `tests/test-finder-frozen-colors.lua`.

## Implementation Phases

## Phase 1: Optional backdrop - the preview is no longer dimmed
1. **Opt-out** (File: `lua/beast/libs/finder/state.lua`)
   - Action: create the backdrop only when `opts.backdrop ~= false`; guard `relayout`'s backdrop reposition; add `backdrop?` to `Beast.Finder.Opts`.
   - Why: PM rule - no overlay for the theme picker, other pickers keep theirs.
   - Depends on: None
   - Risk: Low
2. **Wire the mapping** (File: `lua/beast/init.lua`)
   - Action: add `backdrop = false` to the `<leader>c` open call.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Frozen colors - the menu keeps the opening theme's colors
1. **freeze()** (File: `lua/beast/libs/finder/highlights.lua`)
   - Action: from `M.get()` copy every group into two named namespaces; in the input ns also define `Normal`, `NormalFloat`, `FloatBorder`, `EndOfBuffer` from `CardInputNormal`/`CardInputBorder`; in the list ns from `CardList`. Remember the list ns so `swatch(hex)` defines `BeastFinderSwatch<hex>` there; remove `reset_swatches` and its bookkeeping.
   - Why: window namespaces survive `:colorscheme`; `winhl` does not work with them.
   - Depends on: None
   - Risk: Medium - any group the panels use that is not copied falls back to the global (previewed) theme; E2E must check prompt text, cursor-hidden state, end-of-buffer cells and match highlights.
2. **Attach** (File: `lua/beast/libs/finder/state.lua`)
   - Action: when `opts.freeze_colors`, call `freeze()` before creating views and `nvim_win_set_hl_ns` on the input and list windows right after creation.
   - Depends on: Step 1
   - Risk: Medium - must run before the first render so swatch groups land in the namespace.
3. **Remove winhl and the swatch hook** (Files: `ui/list.lua`, `ui/input.lua`, `autocmds.lua`)
   - Action: card style no longer sets `winhl`; delete the swatch `ColorScheme` autocmd.
   - Depends on: Steps 1-2
   - Risk: Low
4. **Mapping** (File: `lua/beast/init.lua`)
   - Action: add `freeze_colors = true`.
   - Depends on: Step 2
   - Risk: Low
5. **Test** (File: `tests/test-finder-frozen-colors.lua`)
   - Action: freeze under monokai-pro, switch to `monokai-pro-light`, assert the namespace group values are unchanged while the global ones differ, `nvim_get_hl_ns({ winid })` equals the namespace for both windows, and `swatch()` defines in the list namespace.
   - Depends on: Steps 1-3
   - Risk: Low

# Testing Strategy
- Headless: `nvim --clean --headless -l tests/test-finder-frozen-colors.lua`, plus all existing `tests/test-finder-*.lua`.
- Bench: finder render path changed only through an opt-in; no hot-path lib touched, so no bench needed.
- Manual (`NVIM_APPNAME=BeastVim`, tmux): PM scenarios 1-5. Compare numeric panel colors before/after navigating dark -> light themes (prompt, list, selection line, pointer, dashes, match highlight, end-of-buffer cells), then Enter and reopen, then Esc restore.

# Success Criteria
- [ ] Menu colors do not change between dark and light previews (prompt, list, lines, pointer, selection, match highlights).
- [ ] Editor previews at full brightness (no overlay) for the theme picker.
- [ ] After Enter, reopening shows the menu in the new theme.
- [ ] Esc restores the original theme.
- [ ] Other pickers keep their overlay and unchanged colors.
- [ ] All `tests/test-finder-*.lua` pass, stylua clean.
