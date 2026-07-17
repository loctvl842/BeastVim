---
name: autopairs-init
description: Automatic pairing for brackets and quotes while typing
generated: 2026-06-08
---

> PM Spec: [docs/pm-specs/autopairs-init.md](../pm-specs/autopairs-init.md)

# Summary

Autopairs is the native insert-mode pair helper for brackets and quotes. It keeps the editor responsive by returning keystrokes directly, while smart vetoes keep the behavior out of the way in contexts where literal typing is better.

---

# Context

## Problem

Typing matching brackets and quotes by hand is slow and error-prone. The editor needs a lightweight pair engine that works with normal typing, backspace, and enter without depending on a third-party plugin.

### Solution

Keep autopairs as a pure-Lua native keymap engine with configurable pairs, smart veto rules, and an idempotent install/uninstall lifecycle. The mapping layer should remain managed by BeastVim's key registry.

---

# Research

### Repo Search
- Searched for: `autopairs`, `mini.pairs`, `nvim-autopairs`, `<BS>`, `<CR>`, insert-mode keymap setup, treesitter capture lookup
- Found: `lua/beast/plugins/init.lua` used to carry the `mini.pairs` wrapper, `lua/beast/libs/key/core.lua` provides `Key.safe_set`, `lua/beast/libs/confirm/config.lua` shows the frozen-config pattern, and `tests/test-autopairs-engine.lua` / `tests/test-autopairs-skip.lua` cover the current native behavior.
- Reuse opportunity: Yes — reuse `Key.safe_set`, the existing test runner pattern, and the native Neovim APIs already used by the shipped lib.

### Built-in / Existing Lib Check
- Checked: `vim.keymap.set(..., { expr = true })`, `vim.api.nvim_replace_termcodes`, `vim.api.nvim_win_get_cursor`, `vim.api.nvim_get_current_line`, `vim.treesitter.get_captures_at_pos`, and `vim.fn.getcmdline()`
- Found: Neovim already provides everything needed for native pair insertion, smart backspace/enter, and context-sensitive vetoes.
- Decision: **Build** — no external pair plugin is needed.

---

# Architecture Changes

- `lua/beast/libs/autopairs/config.lua` — frozen config and pair defaults.
- `lua/beast/libs/autopairs/pairs.lua` — pair registry and neighborhood matching.
- `lua/beast/libs/autopairs/actions.lua` — keystroke-string actions for open/close/backspace/enter.
- `lua/beast/libs/autopairs/skip.lua` — smart veto rules.
- `lua/beast/libs/autopairs/keymap.lua` — install and uninstall managed expr mappings.
- `lua/beast/libs/autopairs/init.lua` — public API and lifecycle ownership.
- `lua/beast/libs/autopairs/health.lua` — health checks for mapping setup and config shape.

## Implementation Phases

## Phase 1: Native engine — pair insertion and keymap install
1. **Config and pair registry** (File: `lua/beast/libs/autopairs/config.lua`, `lua/beast/libs/autopairs/pairs.lua`)
   - Action: Define the default pair set and the pure matching helpers.
   - Why: The rest of the engine needs a stable config shape.
   - Depends on: None
   - Risk: Low

2. **Action strings** (File: `lua/beast/libs/autopairs/actions.lua`)
   - Action: Return literal keystroke strings for open, close, backspace, and enter handling.
   - Why: The editor should see normal keystrokes, not a plugin-specific API.
   - Depends on: Step 1
   - Risk: Medium

3. **Managed mappings** (File: `lua/beast/libs/autopairs/keymap.lua`, `lua/beast/libs/autopairs/init.lua`)
   - Action: Install and remove the expr mappings through the key registry.
   - Why: Users need a single enable/disable switch and clean integration with the cheatsheet.
   - Depends on: Step 2
   - Risk: Medium

## Phase 2: Smart vetoes — keep literal typing available when needed
1. **Skip rules** (File: `lua/beast/libs/autopairs/skip.lua`, `lua/beast/libs/autopairs/actions.lua`)
   - Action: Add context checks for next-character skipping, treesitter-aware skipping, unbalanced lines, and markdown fences.
   - Why: The pair engine must stay predictable in code and prose.
   - Depends on: Phase 1
   - Risk: Medium

## Phase 3: Health and cutover — document and expose the feature
1. **Health check and setup wiring** (File: `lua/beast/libs/autopairs/health.lua`, `lua/beast/init.lua`)
   - Action: Keep health reporting current and wire the lib into startup.
   - Why: The feature needs an obvious startup path and a way to verify it is installed correctly.
   - Depends on: Phase 2
   - Risk: Low

---

# Testing Strategy

- Headless tests: `tests/test-autopairs-engine.lua`, `tests/test-autopairs-skip.lua`
- Bench: none; this is covered by unit tests rather than a dedicated perf bench
- Manual: type openers, closers, backspace, and enter in a normal file, then verify the toggle and markdown behavior

# Success Criteria

- [x] Typing openers like `(`, `{`, `[`, `"`, `'`, and `` ` `` in active contexts inserts balanced pairs with cursor-in-middle.
- [x] Pressing backspace or enter between a valid pair behaves as smart pair-aware editing, not plain single-character editing.
- [x] Users can toggle autopairs off and on and immediately see literal-vs-smart behavior change.
- [x] Markdown users can create fenced code blocks faster via backtick expansion behavior.
- [ ] The keymaps are installed and removed cleanly without leaving stale bindings behind.
