---
name: packer-phase-profiling
description: Profile packer setup phases
generated: 2026-07-17
---

# Summary

The packer setup path should be profiled by phase so startup costs can be attributed to the right step. That makes it easier to spot regressions in plugin loading and config work.

---

# Target Behavior

- Each setup phase is measured separately.
- The profile output names the phase and cost.
- The profiling data is useful for startup regressions.
- Existing packer behavior stays the same.

---

# Scenarios

## 1 — Start BeastVim

```
Step 1: Run setup.
  Phase timings are collected.
Step 2: Inspect the profile.
  Costs are split by phase.
```

## 2 — Change setup work

```
Step 1: Add more initialization.
  The phase cost changes.
Step 2: Compare profiles.
  The regression is visible.
```

## 3 — Remove a phase bottleneck

```
Step 1: Optimize one phase.
  Its measured cost drops.
Step 2: Re-run setup.
  The improvement is obvious.
```

---

# Behavior Rules

- Profiling should be phase-aware.
- Output should be useful for regression tracking.
- The packer flow itself should not change.

---

# Success Criteria

- [ ] Setup phases are measured separately.
- [ ] Profile output names the phase cost.
- [ ] Startup regressions are easier to spot.
