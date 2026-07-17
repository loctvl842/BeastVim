---
name: tabline-edge-fill
description: Maximize visible buffers in the tabline
generated: 2026-07-17
---

# Summary

The tabline should fit as many whole buffer cells as possible before trimming the edges for overflow markers. That shows more buffers than the old fixed-reserve truncation approach.

---

# Target Behavior

- The tabline fits the maximum visible buffers first.
- Hidden edges use exact-width overflow markers.
- Edge cells are trimmed instead of leaving wasted space.
- Clickable behavior stays intact.

---

# Scenarios

## 1 — Many open buffers

```
Step 1: Open a wide buffer list.
  More buffers fit in the visible area.
Step 2: Look at the edges.
  The overflow markers are tight.
```

## 2 — Resize the window

```
Step 1: Make the editor narrower.
  The visible set shrinks.
Step 2: Widen it again.
  More cells become visible.
```

## 3 — Anchor near an edge

```
Step 1: Keep the active buffer near the start or end.
  Only one side may need trimming.
Step 2: Continue switching buffers.
  The tabline stays readable.
```

---

# Behavior Rules

- The algorithm should prefer whole cells.
- Overflow markers should use exact widths.
- Edge cells should remain clickable.

---

# Success Criteria

- [ ] More buffers fit than before.
- [ ] Overflow markers do not waste space.
- [ ] Click behavior still works.
