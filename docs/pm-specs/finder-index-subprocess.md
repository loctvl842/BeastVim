---
name: finder-index-subprocess
description: Build the finder index in a separate process
generated: 2026-07-17
---

# Summary

The finder's content index should be built in a separate headless process instead of the Neovim main loop. That keeps the editor responsive while the index is serialized and loaded.

---

# Target Behavior

- The index builder runs outside the main editor process.
- The built index is written atomically and loaded safely.
- If the build fails, the finder falls back cleanly.
- The existing freshness overlay still works.

---

# Scenarios

## 1 — Build the index

```
Step 1: Start the build.
  A subprocess scans the repo.
Step 2: Load the result.
  The main process uses the finished index.
```

## 2 — Bad build output

```
Step 1: The build fails.
  The file is not trusted.
Step 2: Search anyway.
  The finder falls back safely.
```

## 3 — Update files later

```
Step 1: Change files on disk.
  The freshness overlay still tracks changes.
Step 2: Search again.
  The index remains usable.
```

---

# Behavior Rules

- The main loop should not block on index building.
- Loaded data should be validated before use.
- The builder should be best-effort.

---

# Success Criteria

- [ ] The index builds in a separate process.
- [ ] The main editor stays responsive.
- [ ] Failed builds fall back safely.
