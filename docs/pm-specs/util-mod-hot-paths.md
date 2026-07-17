---
name: util-mod-hot-paths
description: Reduce hot-path module overhead in util
generated: 2026-07-17
---

# Summary

The utility modules should avoid expensive work on hot paths. That keeps startup and frequent editor actions from paying unnecessary module-loading costs.

---

# Target Behavior

- Hot-path utility modules load cheaply.
- Expensive setup moves out of frequently called code.
- Common editor actions stay fast.
- Existing utility behavior does not change.

---

# Scenarios

## 1 — Startup

```
Step 1: Load BeastVim.
  Utility hot paths stay light.
Step 2: Continue startup.
  Less work happens up front.
```

## 2 — Frequent editor use

```
Step 1: Trigger a common utility call.
  It avoids avoidable overhead.
Step 2: Repeat the action.
  The path stays efficient.
```

## 3 — Reload or theme change

```
Step 1: Refresh the editor state.
  Hot-path modules stay sane.
Step 2: Keep using the UI.
  Behavior stays the same.
```

---

# Behavior Rules

- Utility modules should be cheap to require.
- Hot paths should avoid unnecessary imports.
- User-facing behavior should remain unchanged.

---

# Success Criteria

- [ ] Hot-path utility loading is cheaper.
- [ ] Common actions avoid extra overhead.
- [ ] Existing utility behavior stays intact.
