---
name: notify-stack
description: Show persistent notification history
generated: 2026-07-17
---

# Summary

Notification messages should appear in a stacked floating UI instead of disappearing immediately. The stack keeps history visible and behaves like the editor's notification surface.

---

# Target Behavior

- Notifications show in a reusable toast-like stack.
- New messages are added on top of older ones.
- Dismissing the stack clears all visible notifications.
- `vim.notify` routes through the notification surface.

---

# Scenarios

## 1 — Send a notification

```
Step 1: A message is notified.
  It appears in the stack.
Step 2: Another message arrives.
  The newer one appears above the older one.
```

## 2 — Fast events

```
Step 1: A notification comes from a fast event.
  It is scheduled safely.
Step 2: The stack still renders normally.
  No textlock error appears.
```

## 3 — Clear history

```
Step 1: Dismiss the stack.
  All visible notifications close.
Step 2: New notifications still work.
  The stack can be rebuilt.
```

---

# Behavior Rules

- Messages should respect log level filtering.
- The stack should work from regular and fast-event contexts.
- Notifications should use the editor's notification API shape.

---

# Success Criteria

- [ ] Notifications appear in a visible stack.
- [ ] New notifications preserve older history.
- [ ] Fast-event notifications are safe.
- [ ] `vim.notify` routes through the new surface.
