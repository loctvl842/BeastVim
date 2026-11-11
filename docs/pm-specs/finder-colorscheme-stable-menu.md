---
name: finder-colorscheme-stable-menu
description: Theme picker keeps its own colors fixed while previewing themes, and opens without the dimming backdrop
generated: 2026-11-11
---

# Summary
While browsing themes, the picker menu stays in the colors of the theme you started with. Only the editor behind it previews the highlighted theme. The picker also opens without the dimming overlay, so the preview is seen at full brightness.

---

# Problem

Today every step down the list repaints the whole screen in the highlighted theme, including the picker itself. The menu's background, text, selected-row color and swatch frame all change with each step. It is hard to tell what the menu "normally" looks like, and it is confusing to judge a theme while the thing you are navigating keeps changing shape and color. The dimming overlay behind the picker also darkens the very editor you are trying to preview.

## Why now
The picker now has a designed look (panels, swatches, framed selection). That look should stay readable and predictable no matter which theme is previewed.

---

# Target Behavior

STATE 1 - Current theme is monokai-pro, picker just opened:

```
 (editor in monokai-pro, full brightness, no dimming)
        ┌ prompt panel: monokai-pro colors ─┐
        └───────────────────────────────────┘
        ┌ list panel: monokai-pro colors ───┐
          monokai-pro ◀      󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
          ───────────────────────────────────
          ayu_light          󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
        └───────────────────────────────────┘
```

─────────────────────────────────────────
STATE 2 - Navigated to ayu_light (a light theme):

```
 (editor behind is now fully ayu_light - light background, light text)
        ┌ prompt panel: STILL monokai-pro colors ─┐
        └─────────────────────────────────────────┘
        ┌ list panel: STILL monokai-pro colors ───┐
          monokai-pro        󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
          ───────────────────────────────────
          ayu_light ◀        󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
        └─────────────────────────────────────────┘
```

The menu (panel backgrounds, text, dashed and solid lines, blue selection color, pointer) keeps monokai-pro's colors. Swatch squares keep each theme's own colors as always.

─────────────────────────────────────────
STATE 3 - After pressing Enter on ayu_light, then opening the picker again:

```
        ┌ prompt panel: ayu_light colors ───┐
        └───────────────────────────────────┘
        ┌ list panel: ayu_light colors ─────┐
          ayu_light ◀        󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
        └───────────────────────────────────┘
```

The menu takes on the new theme's colors the next time it opens.

---

# Scenarios

## 1 - Browse themes, menu stays put

```
Step 1: In monokai-pro, press <leader>c.
  Menu appears in monokai-pro colors. No dimming overlay over the editor.

Step 2: Press Down several times, through light and dark themes.
  The editor behind repaints in each highlighted theme.
  The menu keeps its monokai-pro colors the whole time.
```

## 2 - Confirm a theme

```
Step 1: Navigate to ayu_dark and press Enter.
  Menu closes. The editor is in ayu_dark.

Step 2: Press <leader>c again.
  The menu now uses ayu_dark's colors.
```

## 3 - Cancel restores the original theme

```
Step 1: Navigate through several themes.
Step 2: Press Esc.
  Menu closes. The editor returns to the theme it had when the picker opened.
```

## 4 - Filtering and scrolling (edge)

```
Step 1: Type "mono" and scroll a long list.
  Match highlights, selected row, separators and swatches keep their
  monokai-pro menu colors; only the editor behind changes.
```

## 5 - Resizing while open (edge)

```
Step 1: Resize the terminal with the picker open on a previewed theme.
  The menu re-lays out and still shows the original theme's colors.
```

---

# Behavior Rules

- The menu's colors are fixed at the moment the picker opens and do not change until it is closed and reopened.
- Everything outside the menu (editor, statusline, tabline, etc.) previews the highlighted theme as today.
- Swatch squares always show the colors of the theme in their row.
- Fuzzy-match highlights inside the menu keep the menu's colors.
- Live preview, Esc-to-restore and Enter-to-apply behave as today.
- The theme picker opens without the dimming overlay. Other pickers (files, buffers, grep, help) keep theirs and their colors are unchanged.

---

# Success Criteria

- [ ] While navigating between a dark and a light theme, the menu's background, text, lines, pointer and selection color do not change.
- [ ] The editor behind still previews the highlighted theme at full brightness (no dimming overlay).
- [ ] After Enter, reopening the picker shows the menu in the newly applied theme's colors.
- [ ] Esc restores the original theme and closes the menu.
- [ ] Filter highlights, selection and swatches look correct while a different theme is previewed.
- [ ] Other pickers look and behave unchanged, including their dimming overlay.

---

# Out of Scope

- Making the other pickers immune to theme changes (they never change the theme).
- A sample-code preview pane (the live editor repaint already covers it).
- Changing the menu design itself (panels, separators, swatches stay as they are).
