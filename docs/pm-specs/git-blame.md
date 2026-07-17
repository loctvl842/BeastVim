---
name: git-blame
description: Show line and file blame information in the git UI
generated: 2026-07-17
---

# Summary

Git blame should be available both as an inline line annotation and as a full-file blame view. That gives users quick context for the current line and a deeper view when they need it.

---

# Target Behavior

- The current line can show blame text inline.
- A full blame view can open in a split.
- The blame info updates safely as the cursor moves.
- The UI stays consistent with the rest of the git tools.

---

# Scenarios

## 1 — Inspect the current line

```
Step 1: Sit on a git-tracked line.
  The blame text appears inline.
Step 2: Move the cursor.
  The annotation updates safely.
```

## 2 — Open full blame

```
Step 1: Open the blame view.
  A split shows commit context.
Step 2: Navigate commits.
  The view stays synced with the file.
```

## 3 — Toggle blame off

```
Step 1: Disable blame.
  The inline annotations stop.
Step 2: Continue editing.
  The rest of git still works.
```

---

# Behavior Rules

- Inline blame should be lightweight.
- Full blame should be on-demand.
- The same git data engine should back both views.

---

# Success Criteria

- [ ] Inline blame appears on tracked lines.
- [ ] A full blame view can open.
- [ ] Cursor movement updates blame safely.
