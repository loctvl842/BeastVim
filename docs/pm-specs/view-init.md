---
name: view-init
description: Provide shared buffer and window helpers
generated: 2026-07-17
---

# Summary

View is the shared wrapper toolkit used by multiple BeastVim libraries. It should provide the common buffer and window helpers and a simple instance abstraction for subclasses.

---

# Target Behavior

- Shared helpers are available under `Beast.View`.
- Instances can be created and extended consistently.
- Buffer and window helpers are accessed through the wrapper.
- Other libraries can subclass the view instance safely.

---

# Scenarios

## 1 — Create a view instance

```
Step 1: Build a buffer/window pair.
  A view instance is returned.
Step 2: Subclass the instance.
  Extra state can be attached cleanly.
```

## 2 — Use helper modules

```
Step 1: Access `View.buf` or `View.win`.
  The helper module loads on demand.
Step 2: Use the helper methods.
  The call works through the shared wrapper.
```

## 3 — Close a view

```
Step 1: Close the window.
  The instance becomes invalid.
Step 2: Check it later.
  The wrapper reports it as closed.
```

---

# Behavior Rules

- The wrapper should be lightweight.
- Shared helpers should load lazily.
- Instances should behave predictably for subclasses.

---

# Success Criteria

- [ ] Instances can be created from a buffer/window pair.
- [ ] Instances can be extended for subclasses.
- [ ] Helper modules are available through `Beast.View`.
- [ ] Closed instances report as invalid.
