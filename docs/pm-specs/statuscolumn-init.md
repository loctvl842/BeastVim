---
name: statuscolumn-init
description: Configurable gutter with numbers, signs, and folds
generated: 2026-07-17
---

# Summary

Statuscolumn gives the editor a configurable left gutter that can show line numbers, git and diagnostic signs, and fold markers. It keeps important file state visible without taking over the whole screen.

---

# Problem

Users need the left gutter to carry useful information, but different kinds of markers can compete for space. The editor needs a single gutter layout that keeps the most important cues visible and readable.

## Why now

This makes the file view more useful during everyday coding, review, and navigation.

---

# Target Behavior

```
 12 │ main.lua
 13 │ modified line
 14 │ folded section ▸
```

```
STATE 1 — Numbers:
  The gutter shows line numbers or relative numbers depending on the window settings.

STATE 2 — Signs:
  Diagnostic and git markers appear in the gutter when they are present.

STATE 3 — Folds:
  Fold open/close markers appear alongside the line numbers and signs.

STATE 4 — Wrapped lines:
  Wrapped continuation lines keep the gutter readable and aligned.
```

---

# Scenarios

## 1 — Editing a file

```
Step 1: The user opens a buffer with line numbers enabled.
  The gutter shows the current line number mode.

Step 2: Diagnostics or git changes appear.
  Signs show up in the gutter next to the affected lines.
```

## 2 — Working with folds

```
Step 1: The user opens a foldable file.
  Fold markers appear in the gutter.

Step 2: The user opens or closes a fold.
  The marker updates to match the fold state.
```

## 3 — Narrow or wrapped layouts

```
Step 1: The user resizes the window or opens wrapped lines.
  The gutter stays aligned.

Step 2: The user continues editing.
  The gutter remains readable and stable.
```

---

# Behavior Rules

- The gutter should show the most useful line context without feeling crowded.
- Numbers, signs, and folds should work together in one layout.
- Wrapped lines should keep the gutter aligned.
- If a marker is unavailable, the gutter should stay readable instead of breaking.

---

# Success Criteria

- [ ] Line numbers or relative numbers appear in the gutter.
- [ ] Diagnostic and git signs appear when present.
- [ ] Fold markers appear and update with the fold state.
- [ ] Wrapped lines stay aligned and readable.

---

# Out of Scope

- Clickable gutter actions
- Custom producer plugins
- Right-side gutter decorations
