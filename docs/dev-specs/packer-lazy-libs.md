---
name: packer-lazy-libs
description: Lazy-load Beast libraries on demand
generated: 2026-05-13
---

> PM Spec: [docs/pm-specs/packer-lazy-libs.md](../pm-specs/packer-lazy-libs.md)

# Summary

Packer lazy-loading lets Beast libraries defer their setup work until the first trigger that actually needs them. The implementation reuses the existing plugin trigger system and adds a library loader on top of it.

---

# Context

## Problem

Some Beast libraries are not needed at startup, but loading them eagerly still costs time. The codebase already has a trigger-based plugin loader, so the spec should describe the current library-lazy mechanism rather than the older startup plan.

### Solution

Keep `packer.lazy()` as a small adapter over the existing trigger modules, and let libraries register their own load/setup hooks and highlight modules when they are first used.

---

# Research

### Repo Search
- Searched for: `packer.lazy`, `UIEnter`, `BufWinEnter`, `<leader>e`, `highlight_modules`
- Found: `lua/beast/libs/packer/*` already contains the lazy loader and trigger modules, and `lua/beast/init.lua` uses it to defer library setup.
- Reuse opportunity: Yes — reuse the existing trigger modules and library setup hooks.

### Built-in / Existing Lib Check
- Checked: `package.searchers`, `require`, `vim.schedule`, trigger autocmds, and keymap callbacks
- Found: The existing loader already wraps native Lua module loading and editor triggers.
- Decision: **Reuse** — the library loader is already native and integrated.

---

# Architecture Changes

- `lua/beast/libs/packer/init.lua` — lazy loader entry point.
- `lua/beast/libs/packer/triggers/*` — event, key, filetype, command, module, and path triggers.
- `lua/beast/init.lua` — registers library loads through `packer.lazy()`.

## Implementation Phases

## Phase 1: Library loader — trigger a setup when needed
1. **Module loader** (File: `lua/beast/libs/packer/init.lua`, `lua/beast/libs/packer/triggers/module.lua`)
   - Action: Load Beast libraries when a trigger or direct require needs them.
   - Why: The user should pay setup cost only on first use.
   - Depends on: None
   - Risk: Low

2. **Trigger integration** (File: `lua/beast/libs/packer/triggers/*`, `lua/beast/init.lua`)
   - Action: Wire library startup through the existing trigger types.
   - Why: The loader should behave like the rest of the editor's lazy startup.
   - Depends on: Step 1
   - Risk: Medium

---

# Testing Strategy

- Headless tests: none currently targeted for this loader.
- Bench: startup timing checks via the existing packer profiling path.
- Manual: open the editor, trigger a deferred library, and confirm it loads only on first use.

# Success Criteria

- [ ] Deferred libraries do not load during startup.
- [ ] The library loads automatically on first use.
- [ ] The library behaves normally after it loads.
- [ ] Core startup features still work immediately.
