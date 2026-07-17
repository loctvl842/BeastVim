---
name: beast-palette
description: Central palette extraction for BeastVim themes
generated: 2026-07-17
---

# Summary

BeastVim should expose one shared palette object derived from the active colorscheme. Other components can read the same accent and dimmed colors instead of hardcoding their own values.

---

# Target Behavior

- The palette is available from a single module.
- Colors update when the colorscheme changes.
- Missing highlight groups fall back cleanly.
- Other BeastVim components can read the palette at any time.

---

# Scenarios

## 1 — Load a colorscheme

```
Step 1: Apply a theme.
  BeastVim extracts palette values.
Step 2: Read the palette.
  The fields are populated.
```

## 2 — Switch themes

```
Step 1: Change colorscheme.
  The palette refreshes.
Step 2: Re-read the palette.
  The values reflect the new theme.
```

## 3 — Missing theme data

```
Step 1: Use a minimal theme.
  Some highlight groups may be absent.
Step 2: Read the palette.
  Fallback colors are still available.
```

---

# Behavior Rules

- The palette should be central and reusable.
- Values should come from the active colorscheme.
- Theme changes should reapply Beast highlights cleanly.

---

# Success Criteria

- [ ] The palette returns a complete set of fields.
- [ ] Theme switching refreshes the values.
- [ ] Missing groups fall back safely.
