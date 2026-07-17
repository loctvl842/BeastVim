---
name: scroll-init
description: Smooth viewport scrolling inside Neovim
generated: 2026-05-28
---

> PM Spec: [docs/pm-specs/scroll-init.md](../pm-specs/scroll-init.md)

# Summary

Scroll is a native smooth-scrolling library that animates viewport movement when the cursor pushes the window. It keeps repeated movement responsive while avoiding the jumpy feel of plain redraws.

---

# Context

## Problem

The editor already supports smooth wrapped-line rendering, but it still jumps the viewport when the cursor moves quickly. The library needs a native animation layer that keeps up with repeated scroll input without depending on a plugin.

### Solution

Keep scroll as a small native lib with per-window state, a timer-driven animation loop, and autocmd-based reset logic. It should animate only when the viewport changes enough to be noticeable and skip cases where the editor already behaves well.

---

# Research

### Repo Search
- Searched for: `scroll`, `smoothscroll`, `WinScrolled`, `neoscroll`, `cinnamon`, `<C-e>`, `<C-y>`, `animate`
- Found: `lua/beast/option.lua` already enables Neovim's smoothscroll option, `lua/beast/libs/animate.lua` handles float geometry rather than viewport motion, and `lua/beast/libs/explorer/autocmds.lua` shows the repo's `WinScrolled` autocmd style.
- Reuse opportunity: Yes — reuse the native lib skeleton and timer/autocmd patterns, but not the float animation engine.

### Built-in / Existing Lib Check
- Checked: `vim.api.nvim_create_autocmd`, `vim.fn.winsaveview`, `vim.fn.winrestview`, `vim.api.nvim_win_call`, `vim.api.nvim_win_text_height`, `vim.uv.new_timer`, and `vim.on_key`
- Found: Neovim already provides all primitives needed for viewport animation.
- Decision: **Build** — implement a focused native scroll animator.

---

# Architecture Changes

- `lua/beast/libs/scroll/config.lua` — animation defaults and config setup.
- `lua/beast/libs/scroll/state.lua` — per-window animation state and backup/restore.
- `lua/beast/libs/scroll/init.lua` — public API, autocmds, mouse-wheel detection, and animation hot path.

## Implementation Phases

## Phase 1: Core scroll engine — state and timer-driven animation
1. **Config** (File: `lua/beast/libs/scroll/config.lua`)
   - Action: Define animation profiles, repeat timing, and the default filter.
   - Why: The rest of the library needs stable timing defaults.
   - Depends on: None
   - Risk: Low

2. **State object** (File: `lua/beast/libs/scroll/state.lua`)
   - Action: Track per-window animation state, current and target views, and timer cleanup.
   - Why: Each window needs independent scroll motion.
   - Depends on: None
   - Risk: Low

3. **Animation controller** (File: `lua/beast/libs/scroll/init.lua`)
   - Action: Hook autocmds, detect repeats, and drive the animation tick loop.
   - Why: This is the user-facing scroll behavior.
   - Depends on: Phase 1 steps 1-2
   - Risk: Medium

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: none; this is interaction-driven rather than a pure hot path.
- Manual: hold movement keys, jump through a file, scroll with the mouse wheel, and verify filtered buffers and macros skip animation.

# Success Criteria

- [x] Large vertical jumps animate smoothly.
- [x] Repeated scrolling uses a faster repeat profile.
- [x] Mouse wheel, macros, paste mode, and filtered buffers skip animation.
- [x] The editor still behaves normally when no animation should run.
- [ ] Each window animates independently without leaking state.

