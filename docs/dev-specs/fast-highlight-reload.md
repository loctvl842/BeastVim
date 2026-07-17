---
name: fast-highlight-reload
description: Fast colorscheme changes without stale UI colors
generated: 2026-06-05
---

> PM Spec: [docs/pm-specs/fast-highlight-reload.md](../pm-specs/fast-highlight-reload.md)

# Summary

Highlight reload keeps BeastVim UI colors in sync with the active colorscheme. The implementation centralizes highlight-module reloading so color changes apply cleanly across the editor without stale UI surfaces hanging around.

---

# Context

## Problem

The editor needs a reliable way to refresh theme-dependent UI colors quickly when the colorscheme changes. Without a coordinated refresh pipeline, different surfaces can briefly disagree or keep stale colors until they are reopened.

### Solution

Keep highlight refresh as a single dispatcher that knows which highlight modules exist, reloads them together, and reapplies the resulting groups on colorscheme change. That gives every BeastVim surface the same palette at the same time.

---

# Research

### Repo Search
- Searched for: `require("beast.libs.*highlights")`, `M.apply`, `M.get`, `package.loaded.*highlights`, top-level `Util.colors.set_hl`
- Found: `lua/beast/hl_reload.lua` owns `highlight_modules`, `apply_highlights`, and `reload_highlights`, while every lib's `highlights.lua` follows the same return-table pattern used by the dispatcher.
- Reuse opportunity: Yes — reuse the existing highlight-module registry and the shared color helpers already in the repo.

### Built-in / Existing Lib Check
- Checked: `vim.api.nvim_set_hl`, `vim.schedule`, `vim.json`, `vim.uv`, `loadfile`, and the current colorscheme lifecycle
- Found: Neovim already provides the hooks needed to refresh colors on theme change.
- Decision: **Reuse** — the pipeline already exists natively and does not need a plugin.

---

# Architecture Changes

- `lua/beast/hl_reload.lua` — highlight module registry and reload dispatcher.
- `lua/beast/init.lua` — wires the dispatcher into `beast.setup()` and colorscheme setup.
- `lua/beast/libs/*/highlights.lua` — per-library highlight tables.

## Implementation Phases

## Phase 1: Central dispatcher — reload theme-aware UI colors together
1. **Highlight registry** (File: `lua/beast/hl_reload.lua`)
   - Action: Keep the list of highlight modules to reload on colorscheme change.
   - Why: The dispatcher needs a single source of truth.
   - Depends on: None
   - Risk: Low

2. **Reload flow** (File: `lua/beast/hl_reload.lua`, `lua/beast/init.lua`)
   - Action: Reload all registered highlight modules together when the colorscheme changes.
   - Why: This keeps BeastVim surfaces visually consistent.
   - Depends on: Step 1
   - Risk: Medium

## Phase 2: Module contract — every surface provides highlight groups
1. **Library highlight modules** (File: `lua/beast/libs/*/highlights.lua`)
   - Action: Keep each library's highlight definitions in one place.
   - Why: The dispatcher can only refresh what each lib exposes.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this pipeline.
- Bench: `scripts/bench-highlight-reload.lua` for refresh timing.
- Manual: switch colorschemes and confirm the UI updates together without stale colors.

# Success Criteria

- [ ] Changing the colorscheme updates BeastVim UI colors together.
- [ ] Stale highlight colors do not linger after a theme switch.
- [ ] New BeastVim UI surfaces use the active palette immediately.
- [ ] Highlight reload stays quick enough to feel instant.
