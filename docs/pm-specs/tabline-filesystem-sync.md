---
name: tabline-filesystem-sync
description: Keep tabline and current buffer in sync when files change outside Neovim
generated: 2026-07-26
---

# Summary

When a file is deleted or renamed by an external tool (for example, `rm -f x.txt` or `mv old.txt new.txt` in another terminal), the tabline should stop showing the stale buffer tab and move the editor away from the now-missing path. Modified buffers stay visible so unsaved changes are never lost silently.

---

# Problem

Deleting or renaming a file from the explorer updates the tabline immediately. But doing the same thing from a terminal leaves the old tab visible and often leaves the cursor in a buffer whose path no longer exists. The editor state no longer matches the filesystem, so the user can keep editing a file that has disappeared or been moved.

## Why now

Users frequently switch between Neovim and terminal tools. Without this fix, the tabline becomes a source of stale information after any external file operation.

---

# Target Behavior

EXPLORER  init.lua  config.lua        1
STATE 1 — Normal editing:
  Several files are open as buffer tabs.
STATE 2 — External delete/rename of an inactive file:
  The stale buffer tab disappears from the tabline.
STATE 3 — External delete/rename of the active file:
  The stale tab disappears and focus moves to another buffer.

---

# Scenarios

## 1 — Delete an inactive file externally

Step 1: The user has three files open: init.lua, config.lua, and state.lua.
  Tabline shows:  init.lua  config.lua  state.lua
Step 2: In another terminal, the user runs rm -f config.lua.
  After Neovim detects the change, the tabline updates to:  init.lua  state.lua
  config.lua is no longer listed.
Step 3: The user continues working.
  The remaining tabs stay aligned and clickable.

## 2 — Delete the active file externally

Step 1: state.lua is the current buffer.
  Tabline shows:  init.lua  config.lua  state.lua
Step 2: In another terminal, the user runs rm -f state.lua.
  After detection, the editor switches to config.lua (or another fallback buffer).
  Tabline updates to:  init.lua  config.lua
Step 3: The user is not left editing a deleted file.

## 3 — Rename an inactive file externally

Step 1: The user has init.lua and old_name.lua open.
  Tabline shows:  init.lua  old_name.lua
Step 2: In another terminal, the user runs mv old_name.lua new_name.lua (same directory).
  After detection, the tabline updates to:  init.lua  new_name.lua
  The same buffer is rewired to the new path; the tab is not closed.

## 4 — Rename the active file externally

Step 1: old_name.lua is the current buffer.
  Tabline shows:  init.lua  old_name.lua
Step 2: In another terminal, the user runs mv old_name.lua new_name.lua (same directory).
  After detection, the user stays on the same buffer.
  Tabline updates to:  init.lua  new_name.lua

## 5 — Modified buffer changed externally

Step 1: The user has unsaved changes in x.txt.
  Tabline shows x.txt with a modified indicator.
Step 2: x.txt is deleted or renamed outside Neovim.
  The buffer is not silently discarded.
  The tabline keeps x.txt visible with the modified indicator,
  and Neovim's normal warnings apply when the user tries to write or quit.

## 6 — File is restored after external deletion

Step 1: x.txt is deleted externally, so its tab is removed.
  Tabline no longer shows x.txt.
Step 2: The user restores x.txt from a terminal (e.g., git checkout).
  x.txt's tab reappears in the tabline once Neovim detects the file is back.

---

# Behavior Rules

- Detection should happen without requiring the user to switch buffers or run a command.
- External deletion should behave the same as deletion from the explorer whenever safe.
- Same-directory external rename (`mv old new`) rewires the buffer to the new path and updates the tab name (does not close the buffer).
- If the buffer is unmodified and its file path no longer exists (true delete, or rename that cannot be resolved), remove it from the tabline and delete the buffer.
- If a deleted buffer was the current buffer, move focus to the alternate buffer, then the most recently used listed buffer, then a new empty buffer if nothing else exists.
- If the buffer has unsaved changes and the file was deleted, keep it visible and let Neovim's normal modified-buffer handling take over.
- Scratch buffers, terminal buffers, and other non-file buffers are never affected.

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

# Out of Scope

- Cross-directory external rename detection (only same-directory `mv` is rewired via inode match).
- External file creation (new files only appear when explicitly opened).
- A dedicated "orphaned buffer" visual style beyond existing modified indicators.
- Automatic restoration of deleted file contents.
