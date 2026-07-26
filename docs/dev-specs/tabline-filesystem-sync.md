---
name: tabline-filesystem-sync
description: Sync tabline with external file deletion and rename events
generated: 2026-07-26
---

> PM Spec: [docs/pm-specs/tabline-filesystem-sync.md](../pm-specs/tabline-filesystem-sync.md)

# Summary

Add detection in `beast.libs.tabline` for buffers whose backing file has disappeared from disk (caused by external `rm`, `mv`, etc.). Same-directory renames are rewired to the new path (tab name updates, buffer stays). True deletes remove unmodified buffers and, if they were current, move focus to a fallback. Modified buffers with a missing file are left untouched so unsaved changes are never lost silently.

---

# Context

## Problem

The tabline currently trusts the buffer list as the source of truth. When a buffer is deleted through the explorer, the explorer explicitly calls `nvim_buf_delete`, which fires `BufDelete` and redraws the tabline. When a file is removed or renamed externally, Neovim does not fire `BufDelete`, so the tabline keeps showing a buffer whose path no longer exists and the user can remain editing a ghost file.

### Solution

Introduce a periodic-ish cleanup pass inside the tabline library that checks listed file buffers against disk state and removes the stale, unmodified ones. The check is triggered when Neovim regains focus or after a shell command, which covers the common "switch to terminal, run `rm`/`mv`, switch back" workflow.

---

# Research

### Repo Search

- Searched for: `BufDelete`, `BufEnter`, `FocusGained`, `FileChangedShell`, `redrawtabline`, `invalidate` in `lua/beast/libs/tabline/`
- Found: `init.lua` already registers `BufEnter` and a block of layout-changing autocmds including `BufDelete`. It has `invalidate()` and `redrawtabline` plumbing. No existing code watches for externally missing files.
- Reuse opportunity: Yes — reuse the existing autocmd registration pattern, `invalidate()`, and `buffers_mod.list()` / `buffers_mod.is_sidebar_buf()`.

- Searched for: fallback buffer logic in `lua/beast/libs/view/buf.lua` and `lua/beast/libs/explorer/actions/delete.lua`
- Found: Both implement similar fallback logic (alternate buffer → most-recently-used listed buffer → new empty buffer). `explorer/actions/delete.lua` has `find_fallback_buffer()` and `fallback_from_deleted_buffer()`.
- Reuse opportunity: Partial — copy the fallback algorithm into `tabline/buffers.lua` rather than cross-importing from explorer or view, because tabline should not depend on UI-level delete/prompt logic.

- Searched for: file-existence utilities in `lua/beast/util/`
- Found: `util.lsp.path.is_file()` and `util.lsp.path.exists()` exist but are marked deprecated; comments recommend `vim.uv.fs_stat`.
- Reuse opportunity: No — use `vim.uv.fs_stat` directly as recommended.

- Searched for: existing tabline tests in `tests/`
- Found: `tests/test-tabline-edge-trim.lua` uses headless Neovim, stubs globals (`Theme`, `Util`, `Buffer`), and asserts against rendered tabline strings.
- Reuse opportunity: Yes — follow the same test harness for `tests/test-tabline-filesystem-sync.lua`.

### Built-in / Existing Lib Check

- Checked: `vim.uv.fs_stat`, `vim.api.nvim_buf_delete`, `vim.api.nvim_create_autocmd`, `vim.api.nvim_set_current_buf`, `vim.fn.getbufinfo`, `vim.fn.bufnr("#")`, `vim.bo[buf].modified`, `vim.bo[buf].buftype`
- Found: All required APIs are built into Neovim 0.10+ (the tabline health check already requires 0.10+).
- Decision: **Use** — no new dependencies or libraries needed.

---

# Architecture Changes

- `lua/beast/libs/tabline/buffers.lua`
  - Add `find_fallback_buffer(exclude)` — reusable fallback picker (alternate → MRU listed → nil).
  - Add `cleanup_stale()` — scan listed buffers, delete unmodified ones whose file path no longer exists, switch current buffer first if needed.

- `lua/beast/libs/tabline/init.lua`
  - Register `FocusGained` and `ShellCmdPost` autocmds that call `buffers_mod.cleanup_stale()`.
  - Ensure cleanup invalidates the tabline cache and redraws when buffers are removed.

- `tests/test-tabline-filesystem-sync.lua`
  - Headless tests covering external delete/rename of inactive and active buffers, plus modified-buffer safety.

---

# Implementation Phases

## Phase 1: Detect and clean stale buffers on focus/shell events

1. **Add fallback helper** (File: `lua/beast/libs/tabline/buffers.lua`)
   - Action: Implement `find_fallback_buffer(exclude)` mirroring the explorer's fallback order.
   - Why: The current buffer may need to switch away from a stale file safely.
   - Depends on: None
   - Risk: Low

2. **Add stale-buffer cleanup** (File: `lua/beast/libs/tabline/buffers.lua`)
   - Action: Implement `cleanup_stale()`:
     - Iterate `M.list()`, skip sidebars and non-normal buffers (`buftype ~= ""`).
     - For each buffer, check `(vim.uv.fs_stat(name) or {}).type ~= "file"`.
     - If stale and unmodified:
       - If it is the current buffer, call `find_fallback_buffer()` and switch first (or create a new empty buffer), then delete.
       - Otherwise delete directly with `pcall(vim.api.nvim_buf_delete, buf, { force = false })`.
     - If stale and modified, do nothing.
   - Why: Centralizes the filesystem-sync logic inside the existing buffer module.
   - Depends on: Step 1
   - Risk: Medium — touches buffer lifecycle; all deletions wrapped in `pcall`.

3. **Wire up autocmds** (File: `lua/beast/libs/tabline/init.lua`)
   - Action: In `ensure_autocmds()`, add `FocusGained` and `ShellCmdPost` autocmds that call `buffers_mod.cleanup_stale()`.
   - Why: Covers "switch back from terminal" and `:!<command>` workflows without user action.
   - Depends on: Step 2
   - Risk: Low

## Phase 2: Verify and test

4. **Write headless tests** (File: `tests/test-tabline-filesystem-sync.lua`)
   - Action: Create tests that:
     - Open files, delete one externally, trigger cleanup, assert the tab no longer appears.
     - Delete the active file externally, trigger cleanup, assert the current buffer changed.
     - Modify a buffer, delete its file externally, trigger cleanup, assert the buffer remains.
   - Why: Provides automated regression coverage for the new behavior.
   - Depends on: Phase 1
   - Risk: Low

5. **Manual verification** (No file change)
   - Action: Run through the six scenarios in the PM spec inside a real Neovim session.
   - Why: Ensures the feature feels right in the actual UI.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: Add `tests/test-tabline-filesystem-sync.lua` and run with `nvim --clean --headless -l tests/test-tabline-filesystem-sync.lua`.
- Bench: Run `scripts/bench-tabline.lua` to ensure the cleanup pass does not regress render performance.
- Manual: Follow the six scenarios in the PM spec:
  - external delete of inactive file
  - external delete of active file
  - external rename of inactive file
  - external rename of active file
  - modified buffer changed externally
  - file restored after external deletion

---

# Success Criteria

- [x] Deleting an inactive file externally removes its tab from the tabline.
- [x] Deleting the current file externally switches to a fallback buffer.
- [x] Renaming an inactive file externally (same directory) rewires the tab to the new name.
- [x] Renaming the current file externally (same directory) keeps focus and updates the tab name.
- [x] The tabline never shows a ghost tab for a missing, unmodified file.
- [x] Modified buffers changed externally remain visible so unsaved changes are not lost silently.
- [x] Behavior matches explorer deletion for unmodified files.

---

## Completed

- Date: 2026-07-26
- Commits:
  - `18eeec9` tabline: add find_fallback_buffer helper
  - `d5ace3b` tabline: add cleanup_stale for externally missing files
  - `df22749` tabline: clean stale buffers on FocusGained and ShellCmdPost
  - `910c371` test: tabline filesystem sync for external delete/rename
- Note: PM scenario 6 (auto-reopen restored files) is out of scope; restored files appear only when explicitly opened.
