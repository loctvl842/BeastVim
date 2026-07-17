---
name: scroll-init
description: Smooth viewport scrolling inside Neovim
generated: 2026-07-17
---

# Summary

Scroll makes vertical movement feel smoother when the cursor pushes the window. It animates the viewport so large jumps and repeated scrolling feel less abrupt without changing how the editor works.

---

# Problem

Fast scrolling can feel jumpy, especially when a user holds movement keys or jumps through a file. Users need a smoother viewport motion that still keeps up with repeated input.

## Why now

This makes normal navigation feel calmer and more polished without changing the underlying movement keys.

---

# Target Behavior

```
┌────────────────────────────────────────────┐
│  The viewport glides instead of jumping    │
│  when the cursor moves a long distance.    │
└────────────────────────────────────────────┘
```

```
STATE 1 — Single jump:
  A large movement animates smoothly toward the new screen position.

STATE 2 — Repeated movement:
  Holding the same movement key uses a faster animation so the editor keeps up.

STATE 3 — Special cases:
  Mouse wheel movement, macros, paste mode, and filtered buffers skip the animation.

STATE 4 — Idle:
  When no scroll is happening, the editor behaves normally.
```

---

# Scenarios

## 1 — Jumping through a file

```
Step 1: The user presses a movement key that scrolls the viewport.
  The window starts animating toward the new position.

Step 2: The movement ends.
  The viewport settles at the new location.
```

## 2 — Holding a key

```
Step 1: The user holds a movement key.
  Repeated scrolls happen quickly.

Step 2: The scroll repeats.
  The animation switches to the faster repeat profile.

Step 3: The user stops.
  The viewport catches up and stops animating.
```

## 3 — Skipping animation

```
Step 1: The user scrolls with the mouse wheel or in a filtered buffer.
  The window does not animate.

Step 2: The user records or plays back a macro, or paste mode is on.
  The window stays still and follows the normal editor behavior.
```

---

# Behavior Rules

- Smooth scroll should animate only the viewport, not the text itself.
- Repeated scrolling should stay responsive.
- Small scroll changes should not jitter.
- Mouse wheel, macros, paste mode, and filtered buffers should skip animation.
- Closed windows should not keep any scroll state around.

---

# Success Criteria

- [ ] Large vertical jumps animate smoothly.
- [ ] Repeated scrolling uses a faster repeat profile.
- [ ] Mouse wheel, macros, paste mode, and filtered buffers skip animation.
- [ ] The editor still behaves normally when no animation should run.

---

# Out of Scope

- Horizontal scrolling
- Cursor-only animations
- Scrollbar-style UI
