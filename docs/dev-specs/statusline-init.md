---
name: statusline-init
description: Native statusline that shows mode, file state, and editor context
generated: 2026-05-02
---

> PM Spec: [docs/pm-specs/statusline-init.md](../pm-specs/statusline-init.md)

# Summary

Statusline is the native `%!` status bar for showing mode, file state, and cursor context. The implementation keeps the render path cheap, lets components own their own caching when needed, and follows BeastVim's native-library conventions.

---

# Context

## Problem

The repo needs a compact statusline that stays readable across splits, preserves file-bound values in transient UI buffers, and updates without extra framework overhead. The existing implementation already does this natively, but the dev spec needs to reflect the shipped architecture instead of the earlier heirline-style plan.

### Solution

Keep statusline as a native `%!` renderer with declarative components, per-component event gating, width-aware truncation, and highlight refresh through the shared color pipeline. File-bound values should remain visible while focus moves through BeastVim UI buffers.

---

# Research

### Repo Search
- Searched for: `statusline`, `stl`, `redrawstatus`, `winbar`, `%!`
- Found: `statusline/` already implements the native renderer, `lua/beast/plugins/bars/statusline/` is the older heirline version, `statusline/context.lua` documents `g:statusline_winid`, `statusline/highlights.lua` clears highlight caches on colorscheme changes, and `statusline/util.lua` owns file-bound component helpers.
- Reuse opportunity: Yes — reuse the native renderer, shared hl-group cache, and the existing component model.

### Built-in / Existing Lib Check
- Checked: Neovim `%!` statusline behavior, `g:statusline_winid`, `vim.o.columns`, `nvim_win_get_width`, `vim.api`, `vim.uv`, and the existing Beast libs under `lua/beast/libs/`
- Found: Neovim already provides the render hook and target-window context; BeastVim already has a full native statusline library and matching codemap coverage.
- Decision: **Reuse** — the feature belongs on the existing native implementation and shared highlight pipeline.

---

# Architecture Changes

- `statusline/init.lua` — own setup, render, component registry, and autocmd invalidation.
- `statusline/config.lua` — statusline defaults and frozen config.
- `statusline/context.lua` — per-render window context and width calculation.
- `statusline/hlgroup.lua` — deterministic highlight creation and cache.
- `statusline/highlights.lua` — colorscheme refresh hook.
- `statusline/util.lua` — fragment assembly and file-bound helpers.
- `statusline/truncate.lua` — width-based component dropping.
- `statusline/components/*` — mode, diagnostics, position, filetype, shiftwidth, encoding, git_branch, git_commit.

## Implementation Phases

## Phase 1: Native renderer — keep the bar compact and readable
1. **Render context and width handling** (File: `statusline/context.lua`)
   - Action: Build a per-render window context from `g:statusline_winid`, including the correct width for narrow windows and the global statusline case.
   - Why: Truncation must use the real available width.
   - Depends on: None
   - Risk: Low

2. **Component assembly** (File: `statusline/init.lua`, `statusline/util.lua`)
   - Action: Keep declarative left/center/right regions, component evaluation, and string assembly in the native renderer.
   - Why: This is the visible product behavior.
   - Depends on: Step 1
   - Risk: Medium

3. **Highlight refresh** (File: `statusline/highlights.lua`, `statusline/hlgroup.lua`)
   - Action: Refresh highlight groups when the colorscheme changes.
   - Why: The bar must stay legible across themes.
   - Depends on: None
   - Risk: Low

## Phase 2: Autocmds and component behavior — keep values fresh
1. **Event-gated updates** (File: `statusline/init.lua`)
   - Action: Invalidate cached component results when their update events fire.
   - Why: The bar must react to diagnostics, buffer changes, and mode changes without blocking renders.
   - Depends on: Phase 1
   - Risk: Medium

2. **File-bound values** (File: `statusline/util.lua`, `statusline/components/*`)
   - Action: Preserve file-bound values while focus moves through transient BeastVim UI buffers.
   - Why: Users should not lose file context when opening panels.
   - Depends on: Phase 1
   - Risk: Medium

---

# Testing Strategy

- Headless tests: `tests/test-lsp.lua` is unrelated; no dedicated statusline test file currently targeted here.
- Bench: `scripts/bench-statusline.lua` when verifying render hot-path cost.
- Manual: open multiple splits, resize windows narrow/wide, switch into transient BeastVim buffers, and confirm the bar stays readable and updates correctly.

# Success Criteria

- [x] The current mode is visible in the statusline.
- [x] File state and cursor location are visible while editing.
- [x] Active and inactive windows are easy to tell apart.
- [x] Narrow windows still show the most important information.
- [x] Special UI buffers do not look like normal file buffers.
- [ ] Rendering stays cheap enough for frequent redraws.
