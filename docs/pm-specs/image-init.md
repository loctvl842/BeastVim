---
name: image-init
description: Render inline images inside Neovim windows
generated: 2026-07-17
---

# Summary

Image files can be previewed directly inside the editor when the terminal supports inline graphics. When the protocol is unavailable, the feature should fail cleanly so callers can fall back to text.

---

# Target Behavior

- Supported terminals show the image in the target window.
- The image fits inside the window and stays centered.
- Re-rendering after resize replaces the previous placement.
- Clearing removes the inline image from the terminal.

---

# Scenarios

## 1 — Preview a supported image

```
Step 1: Open an image file.
  The image renders in the current window.
Step 2: Resize the window.
  The image can be rendered again to match the new space.
```

## 2 — Unsupported terminal

```
Step 1: Use a terminal without inline image support.
  The render call returns false.
Step 2: The caller falls back to text.
  No broken image artifact appears.
```

## 3 — Clear the preview

```
Step 1: Remove the preview or close the window.
  The inline image is erased.
Step 2: The terminal grid is restored.
  No stale placement remains.
```

---

# Behavior Rules

- Only known image files should be treated as image candidates.
- Large or missing files should not be rendered.
- The image must stay clipped to the owning window.
- Unsupported protocols should never break the editor UI.

---

# Success Criteria

- [ ] Supported terminals can render an image inline.
- [ ] Rendering respects the window bounds.
- [ ] Clearing removes the previous placement.
- [ ] Unsupported terminals return false so callers can fall back.
