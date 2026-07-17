---
name: window-init
description: Manage window layout, maximize, and autowidth
generated: 2026-07-17
---

# Summary

The window library should manage split sizing, maximize and restore layouts, and auto-grow the focused window when needed. It should feel native and keep split behavior predictable.

---

# Target Behavior

- The focused window can be maximized and restored.
- Autowidth adjusts splits to fit the active content.
- Window toggles and commands are available to the user.
- Floating windows and ignored buffers are left alone.

---

# Scenarios

## 1 — Maximize a split

```
Step 1: Trigger maximize.
  The current split fills the available space.
Step 2: Trigger maximize again.
  The previous layout is restored.
```

## 2 — Autowidth

```
Step 1: Open a file that needs more width.
  The window expands to fit.
Step 2: Move to another split.
  The active window can be resized again.
```

## 3 — Ignore rules

```
Step 1: Focus a floating window or ignored buffer.
  No resize action is taken.
Step 2: Return to a normal split.
  Window management works again.
```

---

# Behavior Rules

- Maximize should restore the previous layout cleanly.
- Autowidth should respect filetype and buffer ignore rules.
- The feature should avoid touching floating windows.

---

# Success Criteria

- [ ] Maximize toggles the current layout on and off.
- [ ] Autowidth adjusts the focused window.
- [ ] Ignored windows are left unchanged.
- [ ] The user commands work as expected.
