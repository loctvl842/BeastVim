---
name: statuscolumn-init
description: Configurable gutter with numbers, signs, and folds
generated: 2026-05-31
---

> PM Spec: [docs/pm-specs/statuscolumn-init.md](../pm-specs/statuscolumn-init.md)

# Summary

Statuscolumn is the native gutter renderer for line numbers, diagnostic and git signs, and fold markers. The implementation keeps the render path cheap by classifying signs once per redraw and reusing cached formatted strings per line.

---

# Context

## Problem

The left gutter needs to show numbers, signs, and folds in one compact layout without becoming slow or visually noisy. The current implementation already does this natively, so the spec should describe the actual slot-based engine rather than the earlier design notes.

### Solution

Keep statuscolumn as a native `%!` renderer with configurable slots, cached line strings, and a single sign scan per redraw. The engine should stay plugin-free and degrade cleanly when a sign source is absent.

---

# Research

### Repo Search
- Searched for: `statuscolumn`, `stc`, `vim.o.stc`, `sign_text`, `nvim_buf_get_extmarks.*sign`
- Found: `lua/beast/libs/statuscolumn/*` already implements the current gutter engine, `lua/beast/libs/statuscolumn/signs.lua` classifies signs by namespace/name, and `lua/beast/libs/statuscolumn/init.lua` drives the render path.
- Reuse opportunity: Yes — reuse the existing statuscolumn modules and the shared highlight pipeline.

### Built-in / Existing Lib Check
- Checked: `vim.o.statuscolumn`, `vim.v.lnum`, `vim.v.relnum`, `vim.v.virtnum`, `nvim_buf_get_extmarks`, `vim.opt.fillchars`, and FFI helpers for folds
- Found: Neovim already provides the primitives needed for the gutter renderer.
- Decision: **Reuse** — the native engine is already in place.

---

# Architecture Changes

- `lua/beast/libs/statuscolumn/init.lua` — public API, render loop, and caches.
- `lua/beast/libs/statuscolumn/config.lua` — slot layout, ignore lists, and options.
- `lua/beast/libs/statuscolumn/signs.lua` — sign collection and classification.
- `lua/beast/libs/statuscolumn/fold.lua` — fold marker rendering.
- `lua/beast/libs/statuscolumn/number.lua` — line/relative number formatting.
- `lua/beast/libs/statuscolumn/cache.lua` — per-window and per-line caches.
- `lua/beast/libs/statuscolumn/highlights.lua` — highlight groups.
- `lua/beast/libs/statuscolumn/health.lua` — health checks for render wiring.

## Implementation Phases

## Phase 1: Native gutter core — number rendering and cache plumbing
1. **Config and cache** (File: `lua/beast/libs/statuscolumn/config.lua`, `lua/beast/libs/statuscolumn/cache.lua`)
   - Action: Keep the slot layout and render caches in one place.
   - Why: The renderer needs stable configuration and fast lookups.
   - Depends on: None
   - Risk: Low

2. **Number column** (File: `lua/beast/libs/statuscolumn/number.lua`)
   - Action: Render line numbers and relative numbers according to window settings.
   - Why: The gutter needs a dependable baseline even when no signs are present.
   - Depends on: Phase 1 config
   - Risk: Low

3. **Render entrypoint** (File: `lua/beast/libs/statuscolumn/init.lua`)
   - Action: Assemble the final gutter string from the configured slots.
   - Why: This is the user-visible gutter behavior.
   - Depends on: Steps 1-2
   - Risk: Medium

## Phase 2: Signs and folds — add status and structure cues
1. **Sign classification** (File: `lua/beast/libs/statuscolumn/signs.lua`)
   - Action: Collect extmarks once per redraw and bucket them by class.
   - Why: The gutter needs diagnostic and git cues without scanning repeatedly.
   - Depends on: Phase 1
   - Risk: Medium

2. **Fold markers and highlights** (File: `lua/beast/libs/statuscolumn/fold.lua`, `lua/beast/libs/statuscolumn/highlights.lua`)
   - Action: Show fold markers and keep the gutter colors readable.
   - Why: Fold state is part of the gutter experience.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: `scripts/bench-statuscolumn.lua`
- Manual: open files with numbers, folds, diagnostics, and git changes, then resize and wrap the window to confirm the gutter stays aligned.

# Success Criteria

- [x] Line numbers or relative numbers appear in the gutter.
- [x] Diagnostic and git signs appear when present.
- [x] Fold markers appear and update with the fold state.
- [x] Wrapped lines stay aligned and readable.
- [ ] The gutter stays fast on redraw.
