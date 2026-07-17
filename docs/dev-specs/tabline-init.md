---
name: tabline-init
description: Native tabline with buffer tabs and sidebar offset
generated: 2026-05-13
---

> PM Spec: [docs/pm-specs/tabline-init.md](../pm-specs/tabline-init.md)

# Summary

Tabline is the native buffer tab bar for BeastVim. It renders open buffers, sidebar offsets, and tabpages with a cached `%!` string so the active workspace stays easy to read.

---

# Context

## Problem

The current tabline needs to keep buffer tabs readable, reserve space for sidebars, and keep the active buffer obvious even when focus moves elsewhere. The shipped implementation already does this natively, so the spec should describe the actual buffer-tab architecture.

### Solution

Keep tabline as a native render pipeline with a single context build, cached output, and helper APIs for buffer navigation. The layout should continue to support sidebar offsets, tabpages, and click handlers.

---

# Research

### Repo Search
- Searched for: `tabline`, `redrawtabline`, `make_buflist`, `make_tablist`, `vim.o.tabline`, `Buffer.delete`, `is_sidebar_buf`, `get_unique_name`, `truncate_buffers`, `truncate_text`, `strdisplaywidth`
- Found: `lua/beast/libs/tabline/*` already implements the current tabline, `lua/beast/plugins/bars/tabline/` is the older heirline version, and `lua/beast/init.lua` exposes the buffer deletion helper used by click handlers.
- Reuse opportunity: Yes — reuse the existing tabline modules, context builder, and shared highlight pipeline.

### Built-in / Existing Lib Check
- Checked: `vim.o.tabline`, `vim.api.nvim_list_bufs`, `vim.api.nvim_list_tabpages`, `vim.api.nvim_set_current_buf`, and click-handler format strings
- Found: Neovim already provides the native tabline hooks and buffer navigation primitives.
- Decision: **Reuse** — the native tabline implementation is already in place.

---

# Architecture Changes

- `lua/beast/libs/tabline/init.lua` — public API, render loop, and click handlers.
- `lua/beast/libs/tabline/config.lua` — tabline defaults and frozen config.
- `lua/beast/libs/tabline/context.lua` — render context with buffer and tabpage data.
- `lua/beast/libs/tabline/buffers.lua` — buffer discovery and sidebar detection.
- `lua/beast/libs/tabline/name.lua` — unique buffer names.
- `lua/beast/libs/tabline/truncate.lua` — truncation around the active buffer.
- `lua/beast/libs/tabline/icons.lua` — icon highlight handling.
- `lua/beast/libs/tabline/highlights.lua` — tabline highlight groups.
- `lua/beast/libs/tabline/sections/*` — buffer list, offset, and tabpages sections.

## Implementation Phases

## Phase 1: Native tabline core — buffer tabs and context
1. **Context and config** (File: `lua/beast/libs/tabline/context.lua`, `lua/beast/libs/tabline/config.lua`)
   - Action: Gather buffer and tabpage data once per render and keep the config stable.
   - Why: The tabline needs one shared source of truth.
   - Depends on: None
   - Risk: Low

2. **Buffer list rendering** (File: `lua/beast/libs/tabline/buffers.lua`, `lua/beast/libs/tabline/name.lua`, `lua/beast/libs/tabline/truncate.lua`)
   - Action: Compute buffer names, truncation, and sidebar offsets.
   - Why: This is the visible part of the tabline.
   - Depends on: Step 1
   - Risk: Medium

3. **Render entrypoint** (File: `lua/beast/libs/tabline/init.lua`)
   - Action: Cache the final tabline string and expose navigation helpers.
   - Why: The editor needs a cheap render path and a stable public API.
   - Depends on: Steps 1-2
   - Risk: Medium

## Phase 2: Visual polish — icons, highlights, and click actions
1. **Icons and highlights** (File: `lua/beast/libs/tabline/icons.lua`, `lua/beast/libs/tabline/highlights.lua`)
   - Action: Keep buffer icons readable and the active buffer visually clear.
   - Why: Tabs need compact visual cues.
   - Depends on: Phase 1
   - Risk: Low

2. **Click handlers and tabpages** (File: `lua/beast/libs/tabline/sections/*`)
   - Action: Make buffer tabs and tabpages clickable.
   - Why: Users should be able to navigate directly from the bar.
   - Depends on: Phase 1
   - Risk: Medium

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: `scripts/bench-tabline.lua`
- Manual: open multiple buffers, open a sidebar, and verify the active buffer highlight, truncation, and click behavior.

# Success Criteria

- [x] Open buffers appear as tabs in the tabline.
- [x] Sidebar layouts keep the buffer tabs aligned.
- [x] The active buffer is easy to spot.
- [x] Multiple tabpages appear on the right side.
- [x] Clicking a tab switches to that buffer.
- [ ] Render output stays cached and responsive.
