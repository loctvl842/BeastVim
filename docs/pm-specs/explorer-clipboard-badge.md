---
name: explorer-clipboard-badge
description: Replace the inline "(copy)"/"(cut)" text suffix in the explorer sidebar with a right-aligned icon badge, matching how git status is shown.
generated: 2026-09-04
---

# Summary
When a file or folder is marked to copy or cut in the explorer sidebar, its clipboard state shows as a small icon pinned to the right edge of the sidebar - the same way git status already appears - instead of literal `(copy)`/`(cut)` text glued onto the name.

---

# Problem

Marking a file to copy or cut in the explorer sidebar currently appends the literal text `(copy)` or `(cut)` right after the file's name, on the same line. This looks out of place next to a clean file name, and it competes with everything else already crowded onto that line - the icon, the name, a git status color.

It gets worse on longer names or a narrower sidebar: the suffix gets pushed further right, and once the whole line runs past the edge of the sidebar window, the marker scrolls off screen entirely. The one thing a user needs to see right now - "did my copy/cut register?" - becomes invisible exactly when the file name is inconvenient.

Git status already solves a near-identical problem: instead of stuffing a letter into the name, it's shown as a small badge pinned to the right edge of the sidebar, so it never depends on how long the name is or how narrow the sidebar is.

## Why now
The clipboard marker is the most actively-used piece of transient feedback in the explorer - it's the only confirmation a copy/cut actually took. Losing that confirmation off-screen on ordinary files (long names, deep nesting, a narrow sidebar) undermines the one thing the marker exists for.

---

# Target Behavior

A file just cut shows a cut badge pinned to the sidebar's right edge:

```
┌──────────────────────────────┐
│ MY-PROJECT                   │
│  src/                        │
│    app.lua                󰆐 │
│    utils.lua                 │
│  README.md                   │
└──────────────────────────────┘
```

A file just copied shows a different badge, same position:

```
┌──────────────────────────────┐
│ MY-PROJECT                   │
│  src/                        │
│    app.lua                󰆏 │
│    utils.lua                 │
│  README.md                   │
└──────────────────────────────┘
```

The name itself is untouched - no trailing text, no extra characters pushed into it. Compare to today's inline marker, gone in this redesign:

```
BEFORE (today)                          AFTER (this spec)
│    app.lua (cut)                      │    app.lua                󰆐
```

A long name in a narrow sidebar - the case that motivated this - still shows the badge, because the badge lives at the window's right edge, not appended after the name:

```
┌───────────────────────┐
│ MY-PROJECT             │
│  a-very-long-component-│
│  file-name.tsx       󰆏 │
└───────────────────────┘
```

When a marked file also has a git status and/or a diagnostic, all badges sit together at the right edge, clipboard badge outermost (rightmost):

```
│    app.lua              E M 󰆏 │
                           ▲ ▲ ▲
                    diagnostic│clipboard
                            git
```

---

# Scenarios

## 1 — Cut a file

```
Step 1: Cursor on app.lua, press the cut key
  app.lua's line changes: no text is added to the name; a  󰆐  badge
  appears pinned to the right edge of the sidebar, on app.lua's line.

Step 2: Cursor moves to another file
  The  󰆐  badge stays on app.lua's line - it doesn't move or disappear
  just because the cursor moved elsewhere.

Step 3: Paste elsewhere
  app.lua disappears from its original location (moved). The badge
  goes with it - there is nothing left to badge in the old spot.
```

## 2 — Copy a file

```
Step 1: Cursor on utils.lua, press the copy key
  A  󰆏  badge appears at the right edge of utils.lua's line. The name
  "utils.lua" is unchanged.

Step 2: Paste elsewhere
  A new copy of utils.lua appears at the paste location, with no badge
  (it isn't marked). The original utils.lua keeps its  󰆏  badge - copy
  doesn't clear the source the way cut does.
```

## 3 — Long file name in a narrow sidebar

```
Step 1: Sidebar is narrow; cursor on a file whose name nearly fills
        the visible width, press the copy key
  The file name is not touched or truncated by the marker. The  󰆏
  badge still renders at the sidebar's right edge - it does not depend
  on how much of the name is visible.
```

## 4 — Marked file also has git status and a diagnostic

```
Step 1: A modified file with an active lint warning is cut
  Three badges share the right edge of that file's line: the
  diagnostic glyph, then the git status letter, then the  󰆐  badge -
  all visible at once, none overwriting the others.
```

## 5 — Clearing the clipboard

```
Step 1: A file is cut (shows  󰆐 ), then the user cancels/clears the
        clipboard (e.g. cuts a different file, or explicitly clears it)
  The  󰆐  badge disappears from the first file's line. If a different
  file was just cut instead, that file now shows the  󰆐  badge and the
  first file's badge is gone - only files currently on the clipboard
  are ever badged.
```

---

# Behavior Rules

- Only files/folders currently held on the clipboard show a badge - never more than one badge per clipboard-marked line.
- The badge glyph tells copy from cut apart (`󰆏` = copy, `󰆐` = cut); no other visual difference between the two is required.
- The badge never alters the file/folder name text - the name renders exactly as it would for an unmarked node.
- The badge sits at the sidebar's right edge, alongside any diagnostic and git-status badges already shown there, without hiding or displacing them.
- The badge's visibility does not degrade as the name gets longer or the sidebar gets narrower, the way the old inline suffix did.

---

# Success Criteria

- [ ] Copying or cutting a node no longer appends `(copy)`/`(cut)` text to its name.
- [ ] A copied node shows the `󰆏` badge at the sidebar's right edge; a cut node shows `󰆐`.
- [ ] The badge stays visible regardless of file name length or sidebar width.
- [ ] The badge coexists cleanly with existing diagnostic and git-status badges on the same line.
- [ ] Pasting, or marking a different file, updates badges so only currently-clipboard-held nodes show one.

---

# Out of Scope

- Changing which keys trigger copy/cut/paste, or any clipboard behavior beyond how the marker is displayed.
- Adding new colors or highlight styling beyond reusing the existing clipboard highlight - this spec only changes the marker's shape and position, not its color.
- Making the badge glyphs user-configurable is assumed (matching the existing git/diagnostic icon config pattern) but not elaborated here - that's an implementation detail for the dev spec.
