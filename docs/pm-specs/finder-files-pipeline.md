---
name: finder-files-pipeline
description: Speed up file picker streaming and scoring
generated: 2026-07-17
---

# Summary

The file picker should stream results without blocking and rank them with a faster fuzzy scorer. The goal is to keep large file lists responsive while preserving existing behavior.

---

# Target Behavior

- Results start appearing quickly while files are still streaming.
- Scoring uses the best available match position.
- Only the visible portion of the list needs to be rendered.
- Existing file picker behavior stays intact.

---

# Scenarios

## 1 — Type in a large project

```
Step 1: Start the file picker.
  Results begin streaming.
Step 2: Keep typing.
  Matching stays responsive.
```

## 2 — Re-rank results

```
Step 1: Enter a query.
  The best matches rise to the top.
Step 2: Narrow the query.
  Only relevant items stay active.
```

## 3 — Scroll the list

```
Step 1: Move through results.
  Only visible rows need work.
Step 2: Keep navigating.
  The list remains smooth.
```

---

# Behavior Rules

- Streaming should not block the UI.
- Scoring should prefer better match positions.
- Rendering should avoid unnecessary work.

---

# Success Criteria

- [ ] File results stream quickly.
- [ ] Ranking quality improves.
- [ ] Visible-only rendering keeps the list smooth.
