---
name: window-init
description: Beast Window library for maximize and autowidth
generated: 2026-06-05
---

> PM Spec: [docs/pm-specs/window-init.md](../pm-specs/window-init.md)

# Summary

The window lib manages split sizing, maximize/restore, and autowidth. It keeps the logic in one place and avoids touching floating windows or ignored buffers.

---

# Context

## Problem

Window layout behavior needs to be predictable and reusable, but it spans split math, animation, and autocmd-driven resize behavior.

### Solution

Use a dedicated native lib with config, state, layout helpers, and an autocmd layer.

---

# Research

### Repo Search
- Searched for: `winlayout`, `nvim_win_set_width`, `nvim_win_set_height`, `WinNew`, `BufWinEnter`
- Found: the live `lua/beast/libs/window/` implementation.
- Reuse opportunity: Yes — the existing implementation already matches the intended native approach.

### Built-in / Existing Lib Check
- Checked: `vim.fn.winlayout`, `vim.api.nvim_win_set_width`, `vim.api.nvim_win_set_height`, `vim.uv.new_timer`
- Found: the required primitives are builtin.
- Decision: **Reuse** — no external window plugin is needed.

---

# Architecture Changes

- `lua/beast/libs/window/init.lua` — public API and commands.
- `lua/beast/libs/window/config.lua` — config defaults and merge.
- `lua/beast/libs/window/state.lua` — per-tab cache and guard state.
- `lua/beast/libs/window/frame.lua` — split layout tree.
- `lua/beast/libs/window/layout.lua` — autowidth / maximize / equalize logic.
- `lua/beast/libs/window/resize.lua` — apply merged resize data.
- `lua/beast/libs/window/autocmds.lua` — autowidth triggers.
- `lua/beast/libs/window/animate.lua` — animated resize path.

## Implementation Phases

## Phase 1: Core helpers
1. **Config and state** (Files: `lua/beast/libs/window/config.lua`, `lua/beast/libs/window/state.lua`)
   - Action: Store live config and per-tab snapshots.
   - Why: The API needs stable defaults and state ownership.
   - Depends on: None
   - Risk: Low

2. **Layout and resize helpers** (Files: `lua/beast/libs/window/frame.lua`, `lua/beast/libs/window/layout.lua`, `lua/beast/libs/window/resize.lua`)
   - Action: Compute and apply split sizes.
   - Why: Core behavior for maximize and autowidth.
   - Depends on: Step 1
   - Risk: Medium

## Phase 2: Public API
1. **Main module** (File: `lua/beast/libs/window/init.lua`)
   - Action: Expose setup, maximize, equalize, and autowidth toggles.
   - Why: Gives users one entry point.
   - Depends on: Phase 1
   - Risk: Medium

## Phase 3: Autowidth and animation
1. **Autocmds** (File: `lua/beast/libs/window/autocmds.lua`)
   - Action: Recompute widths on editor events.
   - Why: Makes autowidth happen automatically.
   - Depends on: Phase 2
   - Risk: Medium

2. **Animation** (File: `lua/beast/libs/window/animate.lua`)
   - Action: Smooth split resizing when enabled.
   - Why: Keeps the UI feeling native.
   - Depends on: Phase 1
   - Risk: Low

# Testing Strategy

- Manual: maximize and restore a split.
- Manual: open a wide file and confirm autowidth responds.

# Success Criteria

- [x] Maximize toggles the current layout on and off.
- [x] Autowidth adjusts the focused window.
- [x] Ignored windows are left unchanged.
- [x] The user commands work as expected.
