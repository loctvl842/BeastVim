---
name: explorer-fs-watch
description: Explorer automatically refreshes when files change on disk
generated: 2026-07-17
---

# Summary

Explorer stays in sync with the filesystem while it is open. When files or folders change outside the editor, the tree updates automatically instead of waiting for the user to refresh it by hand.

---

# Problem

If a file is created, renamed, or deleted from another terminal or tool, the explorer can fall behind the real filesystem state. That makes the tree unreliable until the user manually navigates or refreshes it.

## Why now

Automatic refresh keeps the file tree trustworthy during normal work like saves, terminal edits, and version-control operations.

---

# Target Behavior

```
┌──────────────────────────────┐
│ explorer tree                │
│  project/                    │
│    src/                      │
│      new-file.lua            │
└──────────────────────────────┘
```

```
STATE 1 — Expanded folder changes:
  If a folder is open in the tree and files inside it change, the tree updates automatically.

STATE 2 — File save fallback:
  Saving a file also refreshes the matching folder in the tree.

STATE 3 — Backgrounded editor:
  When the editor regains focus, the explorer catches up with outside changes.

STATE 4 — Collapsed folder:
  A folder that is not expanded does not keep updating until the user opens it.
```

---

# Scenarios

## 1 — External file changes

```
Step 1: The user opens the explorer and expands a folder.
  The folder is shown live in the tree.

Step 2: Another terminal creates or removes a file in that folder.
  The explorer updates on its own.

Step 3: The user keeps working.
  The tree stays in sync without a manual refresh.
```

## 2 — Saving a file in the editor

```
Step 1: The user edits a file that appears in the explorer.
  The file is still visible in the tree.

Step 2: The user saves the file.
  The matching folder refreshes automatically.

Step 3: The user returns to the tree.
  The file list matches what is on disk.
```

## 3 — Switching away and back

```
Step 1: The user backgrounds the editor.
  The explorer is no longer in focus.

Step 2: Files change from another place.
  The tree does not need manual input to learn about the change.

Step 3: The user returns focus to the editor.
  The explorer updates to the latest filesystem state.
```

---

# Behavior Rules

- The explorer should follow the real filesystem while it is open.
- Expanded folders are the ones that stay live.
- Closed folders do not need to keep watching in the background.
- Saving a file should still refresh the surrounding folder.
- Returning focus to the editor should reconcile missed changes.

---

# Success Criteria

- [ ] Creating, deleting, or renaming a file outside the editor updates the open explorer automatically.
- [ ] Saving a file refreshes its folder in the tree.
- [ ] Returning focus to the editor catches up with missed filesystem changes.
- [ ] Collapsed folders do not keep updating until reopened.

---

# Out of Scope

- Git status badges
- Recursive watching of every folder in the repository
- Explorer layout changes
