---
name: toast-lsp-progress
description: Show LSP progress as live toast notifications
generated: 2026-07-17
---

# Summary

LSP progress should appear as a small live toast that updates in place as work continues. It should show the client, task title, spinner, progress bar, and completion state without needing a separate plugin.

---

# Target Behavior

- A new progress task opens one sticky toast.
- Progress updates replace the same toast instead of creating a new one.
- Completed tasks briefly show a finished state, then dismiss themselves.
- Progress notifications stay out of the way and use the same toast styling as other messages.

---

# Scenarios

## 1 — Task begins

```
Step 1: An LSP starts a background task.
  A toast appears with the client name and task title.
Step 2: The task continues.
  The toast stays open.
```

## 2 — Task updates

```
Step 1: The server sends progress reports.
  The toast updates in place.
Step 2: The message changes.
  The visible line grows or shrinks with the content.
```

## 3 — Task ends

```
Step 1: The server reports completion.
  The toast shows a finished state.
Step 2: The linger timer expires.
  The toast dismisses itself.
```

---

# Behavior Rules

- One progress token maps to one toast.
- Hidden implementation details should not leak into the user experience.
- The feature should be optional through toast configuration.
- The toast must stay responsive even when updates are frequent.

---

# Success Criteria

- [ ] Progress creates a sticky toast on first update.
- [ ] Report updates replace the existing toast.
- [ ] Completion shows a brief done state.
- [ ] The toast dismisses itself after completion.
- [ ] Users can disable the feature in config.
