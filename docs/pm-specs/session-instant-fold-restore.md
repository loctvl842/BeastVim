---
name: session-instant-fold-restore
description: Restores previously closed folds immediately when a session is loaded, even before language tooling finishes
generated: 2026-07-21
---

# Summary

When a user loads a saved session, folds they previously closed should appear closed immediately. The experience should not depend on whether language tooling is still starting in the background.

---

# Problem

Today, a user can close a fold, quit, reopen, and load the session, but that fold may appear open at first. This feels like the session restore is incomplete or broken, because the editor state briefly does not match what the user saved.

## Why now

Session restore is meant to return the user to exactly where they left off. If fold state is delayed or inconsistent, users lose trust in restore and must manually re-close folds every time.

---

# Target Behavior

STATE 1 — Before quitting (saved state):

```
┌─────────────────────────────────────────┐
│  13                                     │
│  14   if os.getenv("BEAST_PROFILE")…   │
│  21                                     │
│  22                                     │
│  23   require("beast").setup({         │
└─────────────────────────────────────────┘
```

─────────────────────────────────────────
STATE 2 — Right after session load command:

```
┌─────────────────────────────────────────┐
│ :lua require("beast.libs.session").load()│
│                                         │
│  13                                     │
│  14   if os.getenv("BEAST_PROFILE")…   │
│  21                                     │
│  23   require("beast").setup({         │
└─────────────────────────────────────────┘
```

The fold at line 14 is already closed, with no visible wait period.

─────────────────────────────────────────
STATE 3 — Language tooling finishes later:

```
┌─────────────────────────────────────────┐
│  LSP/analysis ready                      │
│                                         │
│  14   if os.getenv("BEAST_PROFILE")…   │
│                                         │
│  (fold state stays unchanged)            │
└─────────────────────────────────────────┘
```

---

# Scenarios

## 1 — Happy path: instant restore after reopen

```
Step 1: User closes a fold, quits, then reopens the same project.
  The file was previously showing one section collapsed.

Step 2: User runs the session load command.
  The same section is collapsed immediately, on first paint after load.

Step 3: Background language tooling attaches later.
  Fold state remains exactly as restored; no flicker to open.
```

## 2 — Edge case: multiple closed folds in one file

```
Step 1: User closes several folds across the file and saves session by quitting.
  Multiple collapse markers are visible before quit.

Step 2: User reloads session.
  All previously closed folds reappear closed immediately, not just one.

Step 3: User scrolls around.
  No delayed "re-close" behavior is noticeable.
```

## 3 — Error/cancellation path: no usable saved fold state

```
Step 1: User loads a session that has no recorded closed folds for this file.
  Session still opens files/splits as usual.

Step 2: Editor cannot restore fold closures from saved state.
  File stays in its default folded/unfolded view for that moment.

Step 3: Language tooling initializes.
  Editor remains stable; no errors or disruptive messages are shown.
```

---

# Behavior Rules

- Session load must prioritize showing the last saved closed-fold state immediately.
- Restored fold state must be independent of language-tool startup timing.
- If a fold was closed when saved, it should appear closed right after load.
- If no closed-fold data exists for a file, session load should continue normally without interruption.
- Restoring fold state must not jump the cursor or scroll position unexpectedly.

---

# Success Criteria

- [ ] After loading a session, previously closed folds are visibly closed immediately.
- [ ] The fold state seen right after load does not change when language tooling finishes attaching.
- [ ] Reopening a project no longer requires manually re-closing folds that were already closed when saved.

---

# Out of Scope

- Automatic session loading on startup (this spec only covers behavior once load is triggered).
- New session UI (pickers, popups, status indicators, or progress banners).
- Redesigning fold commands or keybindings.
