---
name: fast-highlight-reload
description: Fast colorscheme changes without stale UI colors
generated: 2026-07-17
---

# Summary

Changing the colorscheme should update BeastVim's UI colors quickly and consistently. The user should not see stale highlight colors hanging around after a theme switch.

---

# Problem

Theme changes can leave parts of the UI lagging behind or briefly inconsistent if every highlight group has to be rebuilt in a slow, scattered way. Users need the whole interface to pick up the new palette together.

## Why now

This keeps theme switching feeling instant and prevents mismatched colors across the editor chrome.

---

# Target Behavior

```
Before: dark theme colors
After: light theme colors

The editor chrome updates together when the colorscheme changes.
```

```
STATE 1 — Existing theme:
  UI colors match the current colorscheme.

STATE 2 — Theme switch:
  The new colors appear across all BeastVim UI surfaces together.

STATE 3 — Theme refresh:
  No stale highlight colors remain visible after the switch.
```

---

# Scenarios

## 1 — Switching themes

```
Step 1: The user changes the colorscheme.
  The editor redraws its UI colors.

Step 2: BeastVim surfaces update.
  Panels, bars, and prompts match the new palette.
```

## 2 — Reloading the same theme

```
Step 1: The user reapplies the active colorscheme.
  The UI refreshes cleanly.

Step 2: The interface stays consistent.
  No stale colors remain from the earlier state.
```

## 3 — Loading BeastVim UI after a theme switch

```
Step 1: The user opens a BeastVim panel after changing themes.
  The panel uses the active palette.

Step 2: The UI looks consistent with the rest of the editor.
  The new colors are visible immediately.
```

---

# Behavior Rules

- Theme changes should update the whole BeastVim UI together.
- Highlight colors should stay consistent after a colorscheme switch.
- Loading a UI surface after a theme change should use the current palette.
- The experience should feel quick enough that the user does not notice stale colors.

---

# Success Criteria

- [ ] Changing the colorscheme updates BeastVim UI colors together.
- [ ] Stale highlight colors do not linger after a theme switch.
- [ ] New BeastVim UI surfaces use the active palette immediately.

---

# Out of Scope

- Changing the colorscheme itself
- Per-feature theme customization
- Highlight editing tools
