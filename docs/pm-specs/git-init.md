---
name: git-init
description: Git signs, hunk actions, previews, and blame in the editor
generated: 2026-07-17
---

# Summary

Git helps users see file changes directly in the editor and act on them without leaving the buffer. It shows per-line signs, lets users move between hunks, previews changes, and exposes blame information for the current line or file.

---

# Problem

When a file has several changes, it is hard to understand what changed and what to do next without switching to a separate git tool. Users need git context close to the code so they can review, stage, reset, or inspect history quickly.

## Why now

This keeps git work inside the editor and makes code review and editing faster during normal development.

---

# Target Behavior

```
┌──────────────────────────────────────────────┐
│  12  function foo()                          │
│  13  local x = 1          M                  │
│  14  local y = 2          +                  │
└──────────────────────────────────────────────┘
```

```
STATE 1 — Normal file with changes:
  Changed lines show visible git signs in the gutter.

STATE 2 — Hunk navigation:
  The user can jump to the next or previous hunk.

STATE 3 — Preview:
  The user can open a preview showing the current hunk diff.

STATE 4 — Blame:
  The current line or file can show who last changed it.
```

---

# Scenarios

## 1 — Reviewing file changes

```
Step 1: The user opens a modified file.
  Git signs appear next to changed lines.

Step 2: The user moves through hunks.
  The selection jumps between change blocks.

Step 3: The user opens a preview.
  A floating window shows the diff for the selected hunk.
```

## 2 — Working with a change

```
Step 1: The user selects a hunk.
  The current change is ready for an action.

Step 2: The user stages, unstages, or resets it.
  The file state updates in the editor.

Step 3: The user repeats the action if needed.
  The last git action can be run again quickly.
```

## 3 — Inspecting blame

```
Step 1: The user asks for blame on a line or file.
  Git shows who last changed the content.

Step 2: The user toggles current-line blame.
  The blame info appears and disappears without leaving the buffer.
```

---

# Behavior Rules

- Git signs should be visible next to changed lines.
- Hunk navigation should move the cursor through changes quickly.
- Preview should show the current change before the user acts.
- Stage, unstage, and reset actions should update the file state immediately.
- Blame should be available as an on-demand view and as a current-line overlay.
- The editor should stay usable even when a file is not in a git repository.

---

# Success Criteria

- [ ] Changed lines show git signs in the editor.
- [ ] Users can move between hunks and preview the current one.
- [ ] Users can stage, unstage, or reset a hunk from the editor.
- [ ] Blame information is available for the current line or file.
- [ ] Files outside a git repository still open normally.

---

# Out of Scope

- Git history browsers
- Branch management
- Merge conflict resolution UI beyond what is already shown in-editor
