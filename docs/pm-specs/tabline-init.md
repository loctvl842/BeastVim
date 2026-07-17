---
name: tabline-init
description: Native tabline with buffer tabs and sidebar offset
generated: 2026-07-17
---

# Summary

Tabline gives the editor a buffer-focused tab bar that shows open files, sidebar offsets, and tabpage numbers. It helps users switch buffers quickly and keeps the active file easy to spot.

---

# Problem

With many buffers open, it is hard to see what is active, what is hidden, and how to jump around quickly. A clear tabline makes buffer navigation and workspace structure easier to read.

## Why now

This keeps buffer switching and sidebar layouts visible at a glance without opening another panel.

---

# Target Behavior

```
EXPLORER  init.lua  config.lua  state.lua        1  2
```

```
STATE 1 — Buffer tabs:
  Open buffers appear as tabs with names, icons, and status hints.

STATE 2 — Sidebar offset:
  When a sidebar is open, the buffer tabs start after a title block that matches the sidebar width.

STATE 3 — Tabpages:
  Multiple tabpages appear on the right side of the bar.

STATE 4 — Active buffer:
  The current buffer is highlighted even when focus is in a sidebar.
```

---

# Scenarios

## 1 — Switching buffers

```
Step 1: The user opens multiple files.
  Each file appears as a buffer tab.

Step 2: The user switches between files.
  The active tab highlight moves with the file.
```

## 2 — Working with a sidebar

```
Step 1: The user opens a sidebar such as the explorer.
  The tabline adds an offset block.

Step 2: The user returns to a file.
  The buffer tabs remain aligned after the sidebar area.
```

## 3 — Using tabpages

```
Step 1: The user opens multiple tabpages.
  Tabpage numbers appear on the right.

Step 2: The user changes tabpages.
  The active tabpage highlight updates.
```

---

# Behavior Rules

- Buffer tabs should show file names and small status hints.
- The active buffer should remain visible even when focus is on a sidebar.
- Sidebar layouts should reserve their own space so the tabs stay aligned.
- Tabpages should stay on the right side of the bar.
- Clicking a tab should switch to that buffer.

---

# Success Criteria

- [ ] Open buffers appear as tabs in the tabline.
- [ ] Sidebar layouts keep the buffer tabs aligned.
- [ ] The active buffer is easy to spot.
- [ ] Multiple tabpages appear on the right side.
- [ ] Clicking a tab switches to that buffer.

---

# Out of Scope

- Buffer pinning or groups
- Hover popups
- Winbar behavior
