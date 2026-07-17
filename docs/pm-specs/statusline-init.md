---
name: statusline-init
description: Native statusline that shows mode, file state, and editor context
generated: 2026-07-17
---

# Summary

Statusline gives each window a compact, always-visible strip of editor state. It helps users see where they are, what file they are editing, and whether anything needs attention without opening extra panels.

---

# Problem

When editing several files at once, the editor's bottom line is the fastest place to understand the current buffer. Without a clear statusline, users have to guess mode, file state, and cursor position from scattered cues.

## Why now

This keeps core editing feedback in one place and makes multitasking across splits less confusing.

---

# Target Behavior

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ NORMAL  main     23                     loctvl842 (2 days ago)   Ln 41 25% │
└──────────────────────────────────────────────────────────────────────────────┘
```

```
STATE 1 — Active window:
  The statusline shows the current mode, file-related indicators, and cursor location.

STATE 2 — Inactive window:
  The same layout appears, but the inactive window is visually quieter.

STATE 3 — Narrow windows:
  Low-priority items disappear first so the most important information still fits.

STATE 4 — Special UI buffers:
  Transient BeastVim panels keep their own statusline behavior and do not look like normal files.
```

---

# Scenarios

## 1 — Editing a normal file

```
Step 1: The user opens a file.
  The statusline appears with mode, file indicators, and cursor position.

Step 2: The user moves through the file.
  The location portion updates to follow the cursor.

Step 3: The user changes modes.
  The mode label changes immediately.
```

## 2 — Working with multiple splits

```
Step 1: The user opens a second split.
  Each window shows its own statusline context.

Step 2: The user focuses the other split.
  The active window becomes visually emphasized.

Step 3: The user returns to the first split.
  That window regains the active styling.
```

## 3 — Narrowing the available space

```
Step 1: The user opens several splits or a narrow sidebar.
  The statusline becomes constrained.

Step 2: Space runs short.
  Less important items disappear before the core file/location information.

Step 3: The window widens again.
  Hidden items return automatically.
```

---

# Behavior Rules

- The statusline always stays compact and readable.
- Active and inactive windows can be distinguished at a glance.
- File state and cursor location are more important than decorative details.
- Narrow layouts should drop less important information before core file context.
- Special UI buffers should not be treated like normal code files.

---

# Success Criteria

- [x] The current mode is visible in the statusline.
- [x] File state and cursor location are visible while editing.
- [x] Narrow windows still show the most important information.
- [x] Special UI buffers do not look like normal file buffers.

---

# Out of Scope

- Clickable statusline actions
- Alternative statusline themes or layouts
- Winbar / tabline behavior
