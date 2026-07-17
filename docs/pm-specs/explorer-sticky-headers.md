---
name: explorer-sticky-headers
description: Keep ancestor directories pinned in the explorer
generated: 2026-07-17
---

# Summary

The explorer should pin ancestor directories above the visible tree when the user scrolls past them. That keeps orientation obvious without adding a separate navigation mode.

---

# Target Behavior

- Ancestor directories stay visible at the top of the explorer.
- The pinned stack grows and shrinks with scrolling.
- The sticky overlay closes when nothing is pinned.
- The overlay stays non-focusable and follows window size changes.

---

# Scenarios

## 1 — Scroll down

```
Step 1: Scroll the explorer.
  Parent directories pin at the top.
Step 2: Keep scrolling.
  The pinned stack updates.
```

## 2 — Return to the top

```
Step 1: Scroll back to the root.
  The sticky stack clears.
Step 2: Keep browsing.
  The overlay stays closed.
```

## 3 — Resize the window

```
Step 1: Change the explorer width.
  The sticky overlay follows it.
Step 2: Scroll again.
  The overlay remains aligned.
```

---

# Behavior Rules

- Sticky ancestors should be visual only.
- The overlay should never take focus.
- Window resizes should keep it aligned.

---

# Success Criteria

- [ ] Parent directories stay pinned while scrolled out of view.
- [ ] The overlay disappears when no ancestors are pinned.
- [ ] The sticky view tracks size changes cleanly.
