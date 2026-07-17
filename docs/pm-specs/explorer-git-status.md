---
name: explorer-git-status
description: Explorer shows git status colors and badges
generated: 2026-07-17
---

# Summary

Explorer shows git-aware file colors and small status badges so users can tell at a glance what changed. Parent folders also reflect the most important status from their children, which makes it easier to navigate active work without opening each folder.

---

# Problem

In a busy repo, it is hard to tell which files are modified, new, deleted, or part of a conflict just from the tree. Users need visible status clues directly in the explorer so they can spot work quickly.

## Why now

This makes the file tree useful for day-to-day git work instead of being only a directory browser.

---

# Target Behavior

```
project/
  src/
    main.lua        M
    new-file.lua    U
  docs/             M
```

```
STATE 1 — File changes:
  Files change color and show a status badge when they are modified, added, deleted, renamed, copied, conflicted, untracked, or ignored.

STATE 2 — Folder inheritance:
  Parent folders take on the strongest visible status from their children.

STATE 3 — Sticky folder headers:
  Folder headers use the same git color cues as the tree entries.

STATE 4 — No git repo:
  The explorer stays normal when the current folder is not inside a git repository.
```

---

# Scenarios

## 1 — Opening a repo

```
Step 1: The user opens the explorer in a git repository.
  Files and folders show git-aware colors and badges.

Step 2: The user moves around the tree.
  The status cues stay visible as the selection changes.
```

## 2 — Changing files on disk

```
Step 1: A file is edited or created.
  The corresponding entry updates its color and badge.

Step 2: The user saves or returns focus to the editor.
  The tree catches up with the latest git state.
```

## 3 — Navigating folders

```
Step 1: The user opens a folder with mixed file states.
  The folder itself shows the strongest child status.

Step 2: The user scrolls so the folder becomes sticky.
  The sticky header keeps the same git cue.
```

---

# Behavior Rules

- Files should show visible git status cues directly in the tree.
- Parent folders should inherit the strongest status from visible descendants.
- Sticky folder headers should match the tree's git cues.
- Ignored items should stay visually quiet.
- If git data is unavailable, the explorer should still work normally.

---

# Success Criteria

- [ ] Modified, added, deleted, renamed, copied, conflicted, untracked, and ignored files are visually distinguishable.
- [ ] Parent folders show the strongest status from their children.
- [ ] Sticky folder headers use the same git cues as the tree.
- [ ] The explorer still works normally when no git repository is present.

---

# Out of Scope

- Staging or un-staging files from the tree
- Git history views
- Multi-repository trees
