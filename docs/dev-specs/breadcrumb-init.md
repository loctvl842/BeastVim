---
name: breadcrumb-init
description: Native winbar breadcrumb with file path and code context
generated: 2026-05-25
---

> PM Spec: [docs/pm-specs/breadcrumb-init.md](../pm-specs/breadcrumb-init.md)

# Summary

Breadcrumb is the native winbar library for showing the current file path and code context. The implementation uses Neovim's `%!` winbar evaluation model so each window can render its own breadcrumb trail without depending on heirline or navic.

---

# Context

## Problem

The repo already has a breadcrumb implementation, but the spec/docs need to reflect the current product behavior and the existing native winbar architecture. The code path must keep per-window state, show file path plus context, and stay fast enough to render on every status redraw.

### Solution

Keep the breadcrumb library as a native winbar module with per-window cache, code-context segments after the file name, and highlight refresh on colorscheme changes. The implementation should match the existing BeastVim bar patterns while staying independent from plugin-based breadcrumb solutions.

---

# Research

### Repo Search
- Searched for: `breadcrumb`, `winbar`, `navic`, `g:statusline_winid`, `hlgroup`
- Found: `lua/beast/libs/breadcrumb/*` already exists, `lua/beast/libs/statusline/context.lua` documents `g:statusline_winid`, `lua/beast/libs/statusline/hlgroup.lua` provides highlight-group helpers, `lua/beast/libs/tabline/*` shows the cache pattern, and `scripts/bench-breadcrumb.lua`/`lua/beast/libs/breadcrumb/health.lua` already exercise the feature.
- Reuse opportunity: Yes — reuse the native `%!` winbar model, `g:statusline_winid` context handling, and the existing breadcrumb cache/highlight patterns.

### Built-in / Existing Lib Check
- Checked: Neovim winbar `%!` evaluation, `g:statusline_winid`, `nvim_win_get_width`, `vim.o.winbar`, `vim.api`, existing Beast libs under `lua/beast/libs/`
- Found: Neovim already provides the winbar hook and per-window target resolution needed here; BeastVim already has the breadcrumb module, highlight helpers, and benchmark harness.
- Decision: **Reuse** — the feature belongs on native Neovim APIs with BeastVim's existing breadcrumb module structure.

---

# Architecture Changes

- `lua/beast/libs/breadcrumb/config.lua` — keep winbar defaults, ignored buffers, and read-only config handling.
- `lua/beast/libs/breadcrumb/context.lua` — build per-render window context from `g:statusline_winid`.
- `lua/beast/libs/breadcrumb/filepath.lua` — render the file path and code-context trail.
- `lua/beast/libs/breadcrumb/highlights.lua` — define breadcrumb highlight groups and refresh on colorscheme changes.
- `lua/beast/libs/breadcrumb/init.lua` — own setup, render, cache invalidation, and winbar registration.
- `lua/beast/libs/breadcrumb/health.lua` — report winbar registration, API contract, and benchmark thresholds.
- `scripts/bench-breadcrumb.lua` — measure hot and cold render costs.

## Implementation Phases

## Phase 1: Native winbar core — render the breadcrumb trail
1. **Context and config wiring** (File: `lua/beast/libs/breadcrumb/context.lua`, `lua/beast/libs/breadcrumb/config.lua`)
   - Action: Keep a per-render window context and the ignored-buffer config used by the winbar.
   - Why: Breadcrumb must resolve the right window and hide itself in transient UI buffers.
   - Depends on: None
   - Risk: Low

2. **Trail formatting** (File: `lua/beast/libs/breadcrumb/filepath.lua`)
   - Action: Render the file icon, file name, and code-context trail into a single winbar string.
   - Why: This is the visible product behavior.
   - Depends on: Step 1
   - Risk: Medium

3. **Highlight groups** (File: `lua/beast/libs/breadcrumb/highlights.lua`)
   - Action: Define breadcrumb highlight groups and refresh them with colorscheme changes.
   - Why: The breadcrumb must stay legible across themes.
   - Depends on: None
   - Risk: Low

## Phase 2: Winbar lifecycle — setup, cache, and invalidation
1. **Library setup and render entrypoint** (File: `lua/beast/libs/breadcrumb/init.lua`)
   - Action: Register the winbar expression, maintain per-window cache entries, and invalidate on buffer/window changes.
   - Why: The winbar must be cheap enough to run continuously.
   - Depends on: Phase 1
   - Risk: High

2. **Health and benchmark coverage** (File: `lua/beast/libs/breadcrumb/health.lua`, `scripts/bench-breadcrumb.lua`)
   - Action: Keep health checks and benchmark output aligned with the library's hot path.
   - Why: Breadcrumb is a rendering path and needs explicit performance gates.
   - Depends on: Phase 2 step 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: `nvim --clean --headless -l scripts/bench-breadcrumb.lua`
- Manual: verify the PM-spec scenarios in a live Neovim window, including path trail updates, modified marker behavior, hidden special buffers, and per-window independence.

# Success Criteria

- [x] Open files show a readable breadcrumb trail in the winbar.
- [x] Unsaved edits show a visible modified marker.
- [x] Special UI buffers do not show the breadcrumb bar.
- [x] Separate splits can show different breadcrumb trails at the same time.
- [x] The winbar can show code context after the file name.
- [ ] Benchmark stays within the breadcrumb hot/cold render thresholds.
