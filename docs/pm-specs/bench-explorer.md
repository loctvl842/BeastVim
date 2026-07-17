---
name: bench-explorer
description: Benchmark explorer render performance
generated: 2026-07-17
---

# Summary

The explorer should have a standalone benchmark that measures render performance in realistic directory shapes. It helps catch regressions in the file tree, rendering, and sticky header path.

---

# Target Behavior

- The benchmark creates real temporary directory trees.
- It measures the explorer render path under multiple shapes.
- It reports a primary mixed-case metric and supporting sub-metrics.
- It exits with a failure code when the threshold is exceeded.

---

# Scenarios

## 1 — Mixed project shape

```
Step 1: Benchmark a realistic tree.
  The full render time is measured.
Step 2: Compare against the threshold.
  The bench passes or fails.
```

## 2 — Wide or deep trees

```
Step 1: Benchmark broad or nested directories.
  The same render path is exercised.
Step 2: Inspect the breakdown.
  Specific stages can be blamed.
```

## 3 — Regression check

```
Step 1: Re-run the bench after changes.
  The numbers are comparable.
Step 2: Look at the output.
  Regressions are easy to spot.
```

---

# Behavior Rules

- The benchmark should use real filesystem data.
- The output should include a clear pass/fail metric.
- Sub-metrics should help attribute regressions.

---

# Success Criteria

- [ ] The bench runs in headless Neovim.
- [ ] It reports a primary explorer render metric.
- [ ] It covers realistic directory shapes.
- [ ] It fails when the threshold is exceeded.
