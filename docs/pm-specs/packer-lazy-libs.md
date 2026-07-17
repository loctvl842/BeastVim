---
name: packer-lazy-libs
description: Lazy-load Beast libraries on demand
generated: 2026-07-17
---

# Summary

Packer can load Beast libraries only when they are needed instead of pulling every library into startup. That keeps the editor faster at launch while still letting each library initialize normally when it is first used.

---

# Problem

Some editor features are not needed during startup, but loading them anyway adds delay. Users need a way to defer those libraries until a trigger actually needs them.

## Why now

This keeps startup lighter while preserving the same behavior once a library is used.

---

# Target Behavior

```
Startup
  → only core pieces load
  → optional libraries load later on first use
```

```
STATE 1 — Idle startup:
  Unused libraries do not load yet.

STATE 2 — First use:
  The library loads when the trigger fires.

STATE 3 — Later use:
  The library stays loaded and behaves normally.
```

---

# Scenarios

## 1 — Opening the editor

```
Step 1: The editor starts.
  Only the required startup pieces load.

Step 2: Optional libraries wait.
  They do not cost time yet.
```

## 2 — Using a deferred feature

```
Step 1: The user triggers a deferred library.
  The library loads on demand.

Step 2: The feature runs.
  The result matches a normal eager load.
```

## 3 — Using the feature again

```
Step 1: The user triggers the same feature later.
  The library is already available.

Step 2: The feature responds immediately.
  No second startup penalty is paid.
```

---

# Behavior Rules

- Deferred libraries should still initialize normally when loaded.
- The user should not need to know whether a library was eager or lazy.
- Core startup features should remain available immediately.
- A lazy load should not change the behavior of the library itself.

---

# Success Criteria

- [ ] Deferred libraries do not load during startup.
- [ ] The library loads automatically on first use.
- [ ] The library behaves normally after it loads.
- [ ] Core startup features still work immediately.

---

# Out of Scope

- Plugin installation
- Loading commands and file patterns beyond existing triggers
- Startup profiling tools
