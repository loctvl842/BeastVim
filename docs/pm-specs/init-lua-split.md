---
name: init-lua-split
description: Split beast init into focused setup modules
generated: 2026-07-17
---

# Summary

The top-level BeastVim setup should be split into focused modules so each concern is easier to maintain. The user-facing setup behavior should stay the same.

---

# Target Behavior

- Global setup is organized into smaller files.
- Highlights, globals, keymaps, and lazy registrations are separated.
- The public entry point still works the same.
- No behavior changes are introduced.

---

# Scenarios

## 1 — Start BeastVim

```
Step 1: Call setup.
  The same initialization happens.
Step 2: Inspect the structure.
  The work is split into smaller files.
```

## 2 — Change highlights

```
Step 1: Switch theme behavior.
  The highlight reload path still works.
Step 2: Use the editor.
  Nothing else changes.
```

## 3 — Update a setup concern

```
Step 1: Edit one setup area.
  Only that area needs attention.
Step 2: Keep the rest stable.
  The split makes maintenance easier.
```

---

# Behavior Rules

- The refactor should not alter startup semantics.
- Each setup concern should live in one place.
- The public setup entry should remain stable.

---

# Success Criteria

- [ ] Setup behavior stays unchanged.
- [ ] Shared concerns are split into focused files.
- [ ] The public entry point still works.
