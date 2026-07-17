---
name: confirm-init
description: Confirm dialog that replaces vim.fn.confirm
generated: 2026-07-17
---

# Summary

Confirm shows a centered modal choice dialog inside Neovim. It gives users a clearer, themed prompt than the default command-line confirm flow while keeping the same return values and behavior expectations.

---

# Problem

Important yes/no prompts are easy to miss when they appear in the command line. Users need a dialog that is easier to read, easier to choose from, and still behaves like the built-in confirm function.

## Why now

This makes destructive or important prompts more visible and less awkward without changing the underlying confirm contract.

---

# Target Behavior

```
┌─────────────────────────────────────────────┐
│             Delete this file?               │
│                                             │
│      [ Yes ]   [ No ]   [ Cancel ]         │
└─────────────────────────────────────────────┘
```

```
STATE 1 — Open dialog:
  A centered modal appears with the message and buttons.

STATE 2 — Keyboard choice:
  The hotkey or arrow movement selects a button.

STATE 3 — Dismiss:
  Esc or cancel closes the dialog without a selection.

STATE 4 — Headless fallback:
  When no UI is available, the built-in confirm behavior is used instead.
```

---

# Scenarios

## 1 — Choosing a button

```
Step 1: The user triggers a confirm prompt.
  A dialog appears with the message and labeled buttons.

Step 2: The user selects a choice.
  The highlighted button changes.

Step 3: The user confirms.
  The prompt closes and returns the selected choice number.
```

## 2 — Using the default choice

```
Step 1: The user opens the dialog and presses Enter immediately.
  The default button is chosen.

Step 2: The dialog closes.
  The caller receives the default result.
```

## 3 — Dismissing the dialog

```
Step 1: The user opens the dialog.
  The modal blocks the editor until a choice is made.

Step 2: The user presses Esc or cancels.
  The dialog closes without a selection.

Step 3: The caller receives the dismissed result.
  The return value indicates no button was chosen.
```

---

# Behavior Rules

- The dialog should keep the same choice numbering as the built-in confirm flow.
- The default choice should be obvious.
- Button labels should be centered and readable.
- The dialog should fall back to the built-in confirm behavior when no UI is available.
- The prompt should use the BeastVim theme and modal overlay style.

---

# Success Criteria

- [ ] Users can answer prompts from a centered modal dialog.
- [ ] The returned choice matches the expected confirm number.
- [ ] Esc or cancel dismisses the dialog without choosing a button.
- [ ] Headless use still falls back to built-in confirm behavior.

---

# Out of Scope

- Custom button animations
- Multi-step wizard dialogs
- Persistent prompt history
