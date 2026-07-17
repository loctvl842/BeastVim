---
name: finder-matcher-performance
description: Improve finder matcher throughput
generated: 2026-07-17
---

# Summary

The matcher should avoid rescoring and resorting everything on every keystroke. Better filtering and bounded result management keep the file picker responsive on large projects.

---

# Target Behavior

- Narrowing a query only touches the necessary items.
- The best matches are kept without sorting the full list.
- Only visible rows need rendering and highlighting.
- Empty queries show items immediately.

---

# Scenarios

## 1 — Type a longer query

```
Step 1: Enter a short query.
  Items are matched.
Step 2: Add another character.
  Only the surviving items need work.
```

## 2 — Large result set

```
Step 1: Search a huge project.
  The top matches are kept bounded.
Step 2: Scroll the list.
  Only visible rows are drawn.
```

## 3 — Clear the query

```
Step 1: Remove the text.
  Matching is skipped.
Step 2: The list resets.
  Items appear in their original order.
```

---

# Behavior Rules

- Query narrowing should reuse prior results.
- Bounded top results should replace full-list sorting.
- Rendering should stay visible-only.

---

# Success Criteria

- [ ] Typing stays responsive on large file sets.
- [ ] Matching work is reduced as the query narrows.
- [ ] The list stays smooth with bounded top results.
