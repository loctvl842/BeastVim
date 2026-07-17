---
name: explorer-highlights-palette
description: Theme the explorer with shared palette colors
generated: 2026-07-17
---

# Summary

The explorer should use the shared palette for its sidebar colors, separators, and status accents. That keeps the file tree visually consistent with the rest of BeastVim.

---

# Target Behavior

- The sidebar has its own background.
- Files, directories, and hidden entries use distinct palette colors.
- Git state and separators are easy to read.
- Theme switching re-applies the explorer highlights.

---

# Scenarios

## 1 — Open the explorer

```
Step 1: Show the file tree.
  The sidebar uses themed colors.
Step 2: Move around.
  The highlight groups remain readable.
```

## 2 — Change themes

```
Step 1: Switch colorscheme.
  The explorer colors update.
Step 2: Re-open the explorer.
  The palette is reflected everywhere.
```

## 3 — Show git state

```
Step 1: Browse modified files.
  Git colors stand out.
Step 2: Browse hidden or root entries.
  Their styling stays distinct.
```

---

# Behavior Rules

- The explorer should use palette-derived colors.
- Theme changes should refresh highlight groups.
- Existing explorer rendering should remain intact.

---

# Success Criteria

- [ ] The explorer has a distinct sidebar theme.
- [ ] Git and file states use readable accent colors.
- [ ] Colors update on theme change.
