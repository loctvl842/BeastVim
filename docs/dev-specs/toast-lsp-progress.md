---
name: toast-lsp-progress
description: Show LSP progress as live toast notifications
generated: 2026-06-10
---

> PM Spec: [docs/pm-specs/toast-lsp-progress.md](../pm-specs/toast-lsp-progress.md)

# Summary

`toast` now owns a native LSP progress adapter. It listens to `LspProgress`, coalesces updates by token, and reuses the toast stack to show one live notification per task.

---

# Context

## Problem

LSP progress was previously only available as a static notification. The current codebase already has a mutable toast stack, so the implementation should describe the adapter that updates an existing toast in place.

### Solution

Add a small progress adapter under `lua/beast/libs/toast/` and expose two public helpers, `Toast.update(record)` and `Toast.dismiss_id(id)`, so the adapter never reaches into toast internals directly.

---

# Research

### Repo Search
- Searched for: `LspProgress`, `$/progress`, `toast.update`, `toast.dismiss_id`
- Found: `lua/beast/libs/toast/progress.lua` already contains the adapter, and `toast/init.lua`, `toast/stack.lua`, and `toast/ui.lua` already expose the required update path.
- Reuse opportunity: Yes — reuse the existing toast core and the native `LspProgress` autocmd.

### Built-in / Existing Lib Check
- Checked: `vim.api.nvim_create_autocmd("LspProgress")`, `vim.lsp.get_client_by_id`, `vim.uv.new_timer`, `vim.defer_fn`
- Found: Neovim provides all the hooks needed for the adapter.
- Decision: **Reuse** — keep the feature native and loosely coupled.

---

# Architecture Changes

- `lua/beast/libs/toast/init.lua` — public `update(record)` / `dismiss_id(id)` helpers and progress setup hook.
- `lua/beast/libs/toast/progress.lua` — `LspProgress` autocmd, token tracking, throttled rerender, completion linger.
- `lua/beast/libs/toast/stack.lua` — in-place update path.
- `lua/beast/libs/toast/ui.lua` — refresh toast width when progress text changes.
- `lua/beast/libs/toast/config.lua` — progress config block.

## Implementation Phases

## Phase 1: Toast mutation API
1. **Add toast update helpers** (File: `lua/beast/libs/toast/init.lua`, `lua/beast/libs/toast/stack.lua`)
   - Action: Expose in-place update and selective dismiss helpers.
   - Why: The adapter needs a public surface.
   - Depends on: None
   - Risk: Low

2. **Resize live toast windows** (File: `lua/beast/libs/toast/ui.lua`)
   - Action: Recompute float width when the rendered content changes.
   - Why: Progress messages change length over time.
   - Depends on: Step 1
   - Risk: Medium

## Phase 2: LSP progress adapter
1. **Add progress config** (File: `lua/beast/libs/toast/config.lua`)
   - Action: Add the opt-in progress config block.
   - Why: The adapter should be user-controlled.
   - Depends on: None
   - Risk: Low

2. **Implement adapter** (File: `lua/beast/libs/toast/progress.lua`)
   - Action: Subscribe to `LspProgress`, track tokens, update existing toasts, and dismiss on completion.
   - Why: This is the feature itself.
   - Depends on: Phase 1 helpers
   - Risk: Medium

3. **Wire setup** (File: `lua/beast/libs/toast/init.lua`)
   - Action: Load the adapter when progress is enabled.
   - Why: Keeps startup behavior predictable.
   - Depends on: Step 2
   - Risk: Low

---

# Testing Strategy

- Manual smoke: trigger an LSP operation and confirm the toast updates in place.
- Manual disable check: turn progress off in config and confirm the autocmd is not registered.

# Success Criteria

- [x] Progress creates a sticky toast on first update.
- [x] Report updates replace the existing toast.
- [x] Completion shows a brief done state.
- [x] The toast dismisses itself after completion.
- [x] Users can disable the feature in config.
