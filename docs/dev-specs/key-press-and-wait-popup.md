---
name: key-press-and-wait-popup
description: Leader-key popup that shows available key continuations
generated: 2026-06-03
---

> PM Spec: [docs/pm-specs/key-press-and-wait-popup.md](../pm-specs/key-press-and-wait-popup.md)

# Summary

The key hint popup is the native leader-key discovery surface for BeastVim. It builds a prefix tree from the managed key registry and shows available continuations in a small floating window.

---

# Context

## Problem

Users need a quick way to discover what comes next after a prefix keypress. The current implementation already does that natively, so the dev spec should describe the actual popup and key-tree behavior instead of the original which-key replacement plan.

### Solution

Keep the popup as a small state machine over `Key.managed`, with a Helix-style float, trigger registration, and a suspend-and-feed flow for the chosen mapping.

---

# Research

### Repo Search
- Searched for: `which-key|getcharstr|press.and.wait|popup.trigger|prefix.tree`
- Found: `lua/beast/libs/key/*` already implements the popup, the managed key registry, and the full-screen browser; `lua/beast/libs/confirm/ui.lua` and `lua/beast/libs/scroll/init.lua` provide the input-loop and timer patterns reused here.
- Reuse opportunity: Yes — reuse `Key.managed`, `Beast.View`, the existing key highlights, and the popup window helpers.

### Built-in / Existing Lib Check
- Checked: `vim.fn.getcharstr`, `vim.api.nvim_feedkeys`, `vim.api.nvim_replace_termcodes`, `vim.fn.reg_recording`, `vim.o.timeoutlen`
- Found: Neovim already provides all primitives needed for the popup loop.
- Decision: **Reuse** — the popup is a native state machine over existing key metadata.

---

# Architecture Changes

- `lua/beast/libs/key/popup.lua` — prefix index, trigger registration, popup loop, and window rendering.
- `lua/beast/libs/key/config.lua` — popup options and defaults.
- `lua/beast/libs/key/init.lua` — setup wiring.
- `lua/beast/libs/key/highlights.lua` — popup highlight groups.

## Implementation Phases

## Phase 1: Popup core — prefix tree and floating window
1. **Popup config and highlights** (File: `lua/beast/libs/key/config.lua`, `lua/beast/libs/key/highlights.lua`)
   - Action: Add popup settings and the matching highlight groups.
   - Why: The popup needs stable visuals and configuration.
   - Depends on: None
   - Risk: Low

2. **Popup module** (File: `lua/beast/libs/key/popup.lua`)
   - Action: Build the prefix tree, show the popup, and resolve the selected mapping.
   - Why: This is the user-facing discovery behavior.
   - Depends on: Phase 1 config and highlights
   - Risk: Medium

3. **Setup wiring** (File: `lua/beast/libs/key/init.lua`)
   - Action: Turn the popup on from the key library setup path.
   - Why: The feature needs one clear entry point.
   - Depends on: Step 2
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: `scripts/bench-key-popup.lua` for popup open and key resolution cost.
- Manual: press a leader prefix, narrow the popup, back out, and confirm the chosen mapping still runs.

# Success Criteria

- [x] Pressing a configured prefix shows available continuations.
- [x] The popup narrows as more keys are typed.
- [x] Backspace and Escape back out cleanly.
- [x] Chosen mappings still run normally.
- [x] Buffer-local mappings appear when applicable.
- [ ] The popup feels instant and does not block typing.
