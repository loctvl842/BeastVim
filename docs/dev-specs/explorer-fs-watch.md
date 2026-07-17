---
name: explorer-fs-watch
description: Explorer automatically refreshes when files change on disk
generated: 2026-05-17
---

> PM Spec: [docs/pm-specs/explorer-fs-watch.md](../pm-specs/explorer-fs-watch.md)

# Summary

Explorer needs live filesystem refresh so it stays accurate when files change outside the editor. The implementation uses libuv file watchers, a debounced refresh path, and existing explorer lifecycle hooks.

---

# Context

## Problem

The explorer currently reflects only the changes it makes itself. External file operations can leave the tree stale until the user manually refreshes or navigates again.

### Solution

Keep the explorer tree synchronized with expanded directories and editor focus changes so the tree follows the real filesystem while the explorer is open.

---

# Research

### Repo Search
- Searched for: `fs_event`, `fs_poll`, `watch`, `new_fs`, `tree:refresh`, `ui.render`
- Found: explorer already has the tree, render, and close lifecycle; `lua/beast/libs/explorer/watch.lua` owns the watcher loop; `lua/beast/libs/explorer/autocmds.lua` and `lua/beast/libs/explorer/init.lua` integrate refresh and cleanup.
- Reuse opportunity: Yes — reuse the existing explorer lifecycle, render path, and watcher state.

### Built-in / Existing Lib Check
- Checked: `vim.uv.new_fs_event()`, `vim.uv.new_timer()`, `BufWritePost`, `FocusGained`, and the current explorer refresh helpers
- Found: Neovim provides the watcher and debounce primitives directly.
- Decision: **Build** — keep the implementation native and small.

---

# Architecture Changes

- `lua/beast/libs/explorer/watch.lua` — filesystem watchers and refresh debounce.
- `lua/beast/libs/explorer/tree.lua` — watcher start/stop hooks when directories expand or collapse.
- `lua/beast/libs/explorer/autocmds.lua` — refresh on save and focus return.
- `lua/beast/libs/explorer/init.lua` — stop all watchers when the explorer closes.
- `lua/beast/libs/explorer/state.lua` — store active watcher handles.

## Implementation Phases

## Phase 1: Watchers and refresh routing
1. **Watcher module** (File: `lua/beast/libs/explorer/watch.lua`)
   - Action: Track watched directories and debounce refreshes when filesystem events arrive.
   - Why: This is the core of live explorer updates.
   - Depends on: None
   - Risk: Low

2. **Tree lifecycle hooks** (File: `lua/beast/libs/explorer/tree.lua`, `lua/beast/libs/explorer/state.lua`)
   - Action: Start watchers when a directory expands and stop them when it collapses.
   - Why: Only visible folders need to stay live.
   - Depends on: Step 1
   - Risk: Medium

3. **Explorer cleanup and fallbacks** (File: `lua/beast/libs/explorer/init.lua`, `lua/beast/libs/explorer/autocmds.lua`)
   - Action: Stop watchers on close and refresh the tree on save or focus return.
   - Why: The explorer should recover from missed filesystem changes.
   - Depends on: Step 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: none; this is event-driven.
- Manual: open the explorer, change files from another terminal, save files in Neovim, and background/foreground the editor to confirm the tree stays current.

# Success Criteria

- [ ] External file creation/deletion/rename is reflected in the explorer automatically.
- [ ] Saving a file refreshes its folder in the tree.
- [ ] Returning focus to the editor catches up with missed filesystem changes.
- [ ] Collapsed folders do not keep updating until reopened.

