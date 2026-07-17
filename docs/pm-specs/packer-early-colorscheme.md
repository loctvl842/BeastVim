---
name: packer-early-colorscheme
description: Load the active colorscheme early during startup
generated: 2026-07-17
---

# Summary

The configured colorscheme should load early enough to avoid a flash of the default theme. That keeps startup visually clean while preserving the normal plugin setup path.

---

# Target Behavior

- The chosen colorscheme is applied early.
- Theme-specific highlights are available before the rest of startup completes.
- Invalid colorscheme configuration fails safely.
- The normal plugin path still loads later as needed.

---

# Scenarios

## 1 — Valid configured theme

```
Step 1: Start BeastVim.
  The configured colorscheme applies early.
Step 2: Continue loading.
  The UI avoids a default-theme flash.
```

## 2 — Missing plugin

```
Step 1: The colorscheme plugin is unavailable.
  Startup keeps going.
Step 2: The rest of the setup runs.
  No broken UI appears.
```

## 3 — Built-in theme

```
Step 1: Choose a builtin colorscheme.
  It is applied directly.
Step 2: Finish startup.
  The editor remains themed.
```

---

# Behavior Rules

- Early theme loading should be safe.
- The configured scheme should win over the default.
- Startup should not flash the fallback theme.

---

# Success Criteria

- [ ] The configured colorscheme loads early.
- [ ] The default theme does not flash.
- [ ] Invalid config fails safely.
