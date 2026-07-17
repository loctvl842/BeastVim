---
name: key-press-and-wait-popup
description: Leader-key popup that shows available key continuations
generated: 2026-07-17
---

# Summary

The key hint popup shows available continuations after a leader-style keypress. It helps users discover the next keys without leaving the editor or opening a separate keymap browser.

---

# Problem

When a prefix key opens many possible actions, users need a quick way to see the available continuations. Without that help, it is hard to discover keymaps and easy to forget what comes next.

## Why now

This makes keyboard navigation more discoverable while staying lightweight and in-editor.

---

# Target Behavior

```
<leader>

  f  Files
  g  Git
  p  Packer
```

```
STATE 1 — Prefix pressed:
  A small popup appears near the bottom-right of the editor.

STATE 2 — Typing more keys:
  The popup narrows to the matching next choices.

STATE 3 — Backspace or cancel:
  The popup moves back up the prefix tree or closes.

STATE 4 — Resolve:
  The chosen mapping runs and the popup disappears.
```

---

# Scenarios

## 1 — Discovering a leader key

```
Step 1: The user presses a configured prefix such as <leader>.
  A popup appears with the available continuations.

Step 2: The user presses another key.
  The list narrows to the next choices.

Step 3: The user chooses a leaf mapping.
  The mapping runs in the editor.
```

## 2 — Backing out

```
Step 1: The user opens the popup.
  A key tree is visible.

Step 2: The user presses Backspace or Esc.
  The popup moves up one level or closes.
```

## 3 — Visual-mode use

```
Step 1: The user triggers the popup from visual mode.
  The popup still shows the available continuations.

Step 2: The user confirms a choice.
  The visual selection remains usable when the action runs.
```

---

# Behavior Rules

- The popup should show only the continuations relevant to the current prefix.
- The popup should stay small and anchored near the bottom-right corner.
- The popup should disappear when a mapping is chosen or canceled.
- Visual-mode selections should keep working when a mapping runs.
- Buffer-local mappings should still appear when they apply to the current buffer.

---

# Success Criteria

- [ ] Pressing a configured prefix shows available continuations.
- [ ] The popup narrows as more keys are typed.
- [ ] Backspace and Escape back out cleanly.
- [ ] Chosen mappings still run normally.
- [ ] Buffer-local mappings appear when applicable.

---

# Out of Scope

- Operator-pending mode
- Full-screen keymap browsing
- Key icons or rich visuals
