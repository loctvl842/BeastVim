---
name: starter-init
description: Show the startup dashboard and intro screen
generated: 2026-07-17
---

# Summary

The starter screen should replace the default intro with a BeastVim dashboard. It presents the editor version, help hints, and configured key actions when the initial buffer is empty.

---

# Target Behavior

- The intro appears only when the startup buffer is still empty.
- The screen includes the native welcome text and BeastVim key rows.
- The overlay disappears as soon as the buffer becomes non-empty.
- The startup screen re-renders cleanly after redraws or resizes.

---

# Scenarios

## 1 — Fresh startup

```
Step 1: Open Neovim on an empty buffer.
  The starter screen appears.
Step 2: The user presses a key or types text.
  The screen disappears.
```

## 2 — Start with configured shortcuts

```
Step 1: Configure starter key hints.
  The screen includes the custom rows.
Step 2: Open Neovim again.
  The hints are centered with the intro text.
```

## 3 — Buffer changes

```
Step 1: The buffer gains content.
  The overlay clears.
Step 2: The user returns to an empty startup buffer.
  The screen can be shown again.
```

---

# Behavior Rules

- The starter should not edit the buffer text.
- It should behave like an overlay, not a plugin page.
- The default intro layout should remain recognizable.
- The feature should stay hidden once real content exists.

---

# Success Criteria

- [ ] Empty startup buffers show the intro overlay.
- [ ] Custom key hints appear in the screen.
- [ ] Typing or loading a file removes the overlay.
- [ ] Redraws keep the layout stable.
