---
name: finder-query-split
description: Split finder query responsibilities into smaller modules
generated: 2026-07-17
---

# Summary

The finder query logic should be split into focused modules instead of one large file. That makes the pipelines easier to reason about while keeping the user behavior unchanged.

---

# Target Behavior

- Match and stream paths own their own state.
- Shared rendering lives in a separate module.
- Query remains the thin coordinator.
- Existing finder behavior stays the same.

---

# Scenarios

## 1 — Search files

```
Step 1: Open the file picker.
  Query orchestration works as before.
Step 2: Type a query.
  The split modules behave the same.
```

## 2 — Use live sources

```
Step 1: Search a streaming source.
  The live path still works.
Step 2: Keep typing.
  The stream pipeline remains separate.
```

## 3 — Render the UI

```
Step 1: Update the query.
  The shared renderer is called.
Step 2: Move around.
  The interface behaves unchanged.
```

---

# Behavior Rules

- Refactoring should not change UX.
- Each pipeline should own its own state.
- Shared rendering should be reusable.

---

# Success Criteria

- [ ] Finder behavior remains unchanged.
- [ ] Match and stream paths are separated.
- [ ] Query is thinner and easier to maintain.
