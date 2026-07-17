---
name: breadcrumb-init
description: Winbar breadcrumb that shows the current file path and code context
generated: 2026-07-17
---

# Summary

Breadcrumb shows the current file path and nearby code context in the winbar so each split stays oriented without opening the file tree. It keeps the top of the window useful while staying small and unobtrusive.

---

# Problem

When several files are open, it is easy to lose track of where the current buffer lives and which part of the file you are editing. The editor title alone does not give enough context, so you end up checking the file tree or scanning the file by hand.

## Why now

This gives a quick, always-visible location cue for the active file and makes multi-split editing easier to follow.

---

# Target Behavior

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 󰢱 init.lua   require("beast").setup   key   mappings                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

```
STATE 1 — Normal file:
  The winbar shows the file name with its icon, then a readable trail of code context segments.

STATE 2 — Unsaved changes:
  A small modified marker appears when the buffer has changes.

STATE 3 — Special UI buffers:
  The winbar is hidden in transient BeastVim panels and other special buffers so those screens stay clean.

STATE 4 — File outside the project root:
  Only the file name and code context that applies to the current buffer are shown.
```

---

# Scenarios

## 1 — Opening a regular project file

```
Step 1: The user opens a source file.
  The winbar appears with a file icon, the file name, and context segments.

Step 2: The user switches to another file in the same window.
  The winbar updates to match the new buffer.

Step 3: The user opens the file in a second split.
  That split shows its own breadcrumb trail, independent of the first window.
```

## 2 — Editing and saving a file

```
Step 1: The user types into the buffer.
  A modified marker appears at the end of the winbar.

Step 2: The user saves the file.
  The modified marker disappears.

Step 3: The user keeps editing.
  The modified marker returns while the file is dirty again.
```

## 3 — Entering a special UI buffer

```
Step 1: The user opens a transient BeastVim panel.
  The winbar is hidden.

Step 2: The user returns to a normal file buffer.
  The breadcrumb bar appears again.
```

## 4 — Reading code context

```
Step 1: The user moves deeper into a function or section.
  The winbar updates to show the current code trail.

Step 2: The user jumps to another symbol.
  The context trail changes to match the new location.
```

---

# Behavior Rules

- The breadcrumb bar shows the current file path and code context, not just the file name.
- Path and context segments use a clear separator so the trail is easy to scan.
- The file icon is part of the winbar and helps distinguish file types at a glance.
- The modified marker only appears while the buffer has unsaved changes.
- The winbar stays hidden in transient BeastVim panels and other special buffers.
- Each window reflects the file and context shown in that window.

---

# Success Criteria

- [x] Open files show a readable breadcrumb trail in the winbar.
- [x] Unsaved edits show a visible modified marker.
- [x] Special UI buffers do not show the breadcrumb bar.
- [x] Separate splits can show different breadcrumb trails at the same time.
- [x] The winbar can show code context after the file name.

---

# Out of Scope

- Clickable path segments
- Long-path truncation rules beyond the current display behavior
