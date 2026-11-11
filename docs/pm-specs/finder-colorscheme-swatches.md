---
name: finder-colorscheme-swatches
description: Theme picker shows each theme on its own row with a strip of color swatches, in a separated-row card layout
generated: 2026-11-11
---

# Summary
The theme picker (opened with `<leader>c`) lists every theme as a roomy row with a strip of ten color swatches on the right, so the user can judge a theme's palette at a glance before applying it. The prompt sits in its own small box above the list.

---

# Problem

Today the theme picker is a plain list of theme names. To know what a theme looks like the user has to move onto it and watch the whole editor repaint, one theme at a time. With dozens of themes, comparing them means a lot of arrow-key presses and remembering what the previous one looked like.

The list is also dense: names are packed line after line, with nothing to separate one entry from the next.

## Why now
The picker already applies a theme live as the cursor moves. Showing the palette next to each name lets the user skip themes that are clearly wrong (too bright, wrong hue) without stepping through them, and makes the picker feel like a deliberate theme gallery rather than a generic list.

---

# Target Behavior

STATE 1 - Picker just opened (top row selected, as today). Two borderless panels, the prompt panel slightly lighter than the list panel; `ayu_dark` is shown selected for illustration:

```
   🔍 |                                       <- prompt panel (lighter)

   aquarium           󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻   <- list panel (darker)
   - - - - - - - - - - - - - - - - - - - - -
   ashes              󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
   - - - - - - - - - - - - - - - - - - - - -
   aylin              󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
   ─────────────────────────────────────────
   ayu_dark ◀         󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
   ─────────────────────────────────────────
   ayu_light          󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
   - - - - - - - - - - - - - - - - - - - - -
   bearded-arc        󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻 󱓻
```

- No box borders. The prompt is a lighter panel with a search icon; the list is a darker panel directly below it.
- Each row: theme name on the left, ten rounded color squares on the right edge.
- Between two rows: a dashed line (`-----`) in a dim color, inset the same amount on both sides.
- The selected row has no background tint. Its name turns blue (bold) with a `◀` after it, and the lines directly above and below it are solid (`─────`) and blue instead of dashed. At the very top or bottom of the list the solid line is still drawn on the open side of the selected row.
- Every other row keeps its normal text color; squares always keep their own colors.

─────────────────────────────────────────
STATE 2 - Moving down the list: the blue text, pointer and solid lines move with the selection; the editor behind repaints in that theme right away.

─────────────────────────────────────────
STATE 3 - Typing to filter: only matching themes remain, each with its swatches; the selected one keeps the same styling. Outside the first and last remaining rows there is blank space, not dashes.

---

# Scenarios

## 1 - Browse and pick a theme

```
Step 1: Press <leader>c.
  Prompt box and theme list appear. Every row already shows its ten swatches.

Step 2: Press Down a few times.
  The highlight moves row by row. The editor behind repaints in each theme.

Step 3: Press Enter on "ayu_dark".
  The picker closes. The editor stays in ayu_dark.
```

## 2 - Cancel restores the original theme

```
Step 1: Press <leader>c while in "monokai-pro".
Step 2: Move onto "ayu_light".
  The editor turns light.
Step 3: Press Esc.
  The picker closes and the editor returns to "monokai-pro".
```

## 3 - Filter by name

```
Step 1: Open the picker and type "ay".
  Only themes whose name matches remain, each still with its swatches.
Step 2: Press Enter on the top row.
  That theme is applied.
```

## 4 - Theme whose colors cannot be read (edge case)

```
Step 1: A theme does not define some of the colors the strip needs.
  Those squares are drawn in a neutral dim grey instead of being left out,
  so the strip is always ten squares wide and rows stay aligned.
```

## 5 - Long theme name / narrow window (edge case)

```
Step 1: Open the picker in a narrow terminal, or with a very long theme name.
  The name is shortened with "..." so the swatches are never pushed off the edge
  or overlapped.
```

## 6 - Empty filter result

```
Step 1: Type "zzzz".
  The list box shows no rows. Enter does nothing.
```

---

# Behavior Rules

- The swatch strip is always ten squares, in a fixed order, so the same color position means the same role across all themes (so themes are comparable column by column).
- Proposed order: background, foreground, red, orange, yellow, green, cyan, blue, purple, grey (comment color). See Open Decisions below.
- Swatches show the theme's own colors, not the colors of the currently active theme. Opening the picker must not change the editor's theme by itself.
- Every theme appears in the list with its swatches at once, without the user having to move onto it first. Opening the picker does not feel slower than it does today.
- Live preview and restore-on-cancel behave exactly as today (Enter keeps, Esc/close restores the original).
- Order, filtering, selection keys and the starting row (top of the list) behave exactly as today; only the look of the picker changes.
- The look applies only to the theme picker. Other pickers (files, buffers, grep, help) keep their current look.
- The preview pane stays off for the theme picker.
- Dashed lines appear between rows only (never above the first or below the last); the only lines on the outer edges are the solid ones framing the selected row.
- Swatch squares keep their own colors on the selected row. The selected row is not background-tinted.

---

# Open Decisions

This is a visual change only. All picker behavior stays exactly as it is today (verified against the current picker: top row highlighted on open, live repaint while moving, Esc restores, Enter applies, no preview pane).

- **Swatch roles** - recommended: background, foreground, red, orange, yellow, green, cyan, blue, purple, grey. Alternative: the ten most frequent accent colors of the theme (varies per theme, less comparable).

---

# Success Criteria

- [ ] `<leader>c` shows a borderless prompt panel above a darker theme list panel.
- [ ] Every row shows a name on the left and ten colored squares on the right.
- [ ] A dashed line separates consecutive rows; the selected row is framed by solid blue lines, blue text and a pointer, with no background tint.
- [ ] Squares match the colors the theme actually uses.
- [ ] All rows show their squares immediately on open, with no visible delay.
- [ ] Moving the highlight still repaints the editor live in that theme.
- [ ] Enter keeps the theme; Esc restores the original.
- [ ] Filtering narrows the list and keeps the swatches.
- [ ] A theme missing some colors still shows ten squares (dim grey for missing ones).
- [ ] Long names are shortened and never collide with the swatches.
- [ ] Files, buffers, grep and help pickers look unchanged.

---

# Out of Scope

- Applying the same look to other pickers (could follow once this is approved).
- A preview pane showing sample code in the highlighted theme (live repaint already covers it).
- Editing or creating themes from the picker.
- Sorting or grouping themes (dark/light) in the list.
- Marking the currently active theme with a badge (can be added later).
