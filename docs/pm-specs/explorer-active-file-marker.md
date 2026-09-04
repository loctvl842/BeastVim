---
name: explorer-active-file-marker
description: Mark the active file in the explorer with a left-edge bar icon instead of a background highlight
generated: 2026-09-04
---

# Summary

The file explorer marks whichever file is currently open in the editor with a small vertical bar (`┃`) at the far left of its row, replacing the current background-color highlight for that purpose.

---

# Problem

Today, the file that's open in the editor is marked by tinting its row background (`BeastExplorerActiveFile`). The cursor line in the explorer is also tinted, just a different shade (`BeastExplorerCursorLine`). Those two background colors sit close enough that it's easy to glance at the tree and not be sure: is this row highlighted because it's the open file, or just because the cursor happens to be sitting on it? Making the active-file color lighter or darker doesn't fully fix this — it's a color-vs-color distinction, and colors are inherently harder to tell apart at a glance than a shape.

## Why now

A shape-based marker (a bar in a fixed position) reads unambiguously regardless of what background color is under it, and doesn't require constantly re-tuning two highlight colors against each other every time a theme changes.

---

# Target Behavior

The active file's row gets a `┃` in the leftmost column of the tree. Every other row's leftmost column stays blank. The marker's color stays legible whether or not the cursor line is also sitting on that row.

```
 BEASTVIM
   lua/
   │ beast/
   │ │ libs/
   │ │ │ explorer/
┃   │ │ │  highlights.lua
    │ │ │  render.lua
    │ │  init.lua
```

Cursor line is a separate, independent signal (still a background tint) that can land on any row, including the marked one:

```
STATE 1 — cursor elsewhere, active file marked:
┃   │ │ │  highlights.lua
    │ │ │  render.lua        <- cursor line background here
    │ │  init.lua

─────────────────────────────────────────
STATE 2 — cursor moved onto the active file's row:
┃   │ │ │  highlights.lua    <- cursor line background AND marker, both visible
    │ │ │  render.lua
    │ │  init.lua
```

---

# Scenarios

## 1 — Open a file from the explorer

```
Step 1: Explorer is open, no file is active yet (no marker anywhere).
  Every row's left edge is blank.

Step 2: Move the cursor to "highlights.lua" and open it.
  Focus moves to the editor. The "highlights.lua" row now shows
  "┃" at the far left, replacing the leading blank space.
```

## 2 — Switch to a different open file

```
Step 1: "highlights.lua" is marked active; user switches buffers
        (e.g. via the finder, or `:bnext`) to "render.lua".
  The marker moves: "highlights.lua"'s left edge goes blank again,
  and "render.lua" now shows "┃".
```

## 3 — Browse the tree without changing the active file

```
Step 1: "highlights.lua" is the active file. User moves the cursor
        down through several other rows to look around.
  The "┃" marker stays put on "highlights.lua" the whole time — it
  never follows the cursor. Only the cursor-line background moves.
```

## 4 — Active file is inside a collapsed directory

```
Step 1: The directory containing the active file is collapsed, so
        the active file's row isn't currently shown in the tree.
  No "┃" appears anywhere, since there's no visible row to put it on.

Step 2: User expands that directory.
  The active file's row becomes visible and immediately shows "┃".
```

## 5 — No file is currently active

```
Step 1: Explorer is open over a buffer that isn't a real file on
        disk (e.g. a fresh unsaved buffer, or a non-file window).
  No row shows "┃" — the marker only ever points at a real open file.
```

---

# Behavior Rules

- The marker is a single `┃` character, always in the same fixed left column, regardless of the file's depth in the tree.
- Exactly one row (or zero, if the active file isn't visible) shows the marker at a time.
- The marker only applies to files, never to directories.
- The marker is independent of the cursor line: they can appear on the same row together, or on different rows, and neither affects whether the other shows.
- The background-tint approach for marking the active file is removed entirely — the marker is the only signal for "this is the open file."
- The marker glyph is configurable, the same way file icons and git badge icons already are — a user can set it to a different character (or turn it off) instead of being stuck with `┃`.

---

# Success Criteria

- [ ] The currently open file's row shows a `┃` at the far left of the explorer.
- [ ] No other row shows the marker.
- [ ] The marker relocates correctly when the user switches to a different open file.
- [ ] The marker is visually distinguishable at a glance from the cursor-line background, including when both land on the same row.
- [ ] The old active-file background highlight no longer appears anywhere in the explorer.

---

# Out of Scope

- Changing the cursor-line highlight color/behavior itself — it stays as-is, this spec only changes how the *active file* is signaled.
- Marking directories as "active" (e.g. the directory containing the active file) — only the file row itself is marked.
- Configuring the marker's column position — always the far left; only the glyph itself is configurable.
