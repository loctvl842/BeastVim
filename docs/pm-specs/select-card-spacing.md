---
name: select-card-spacing
description: Balance the vertical spacing of the select menu - one row of padding at the top and bottom of every panel, a centered heading directly above the filter line, and a padded footer row
generated: 2026-11-12
---

# Summary
The select menu keeps its card look, but its vertical rhythm is rebalanced: the prompt panel has one row of padding above and below its content (heading directly above the filter line), and the footer hints sit close under the options with the same padding above and below.

---

# Problem

In the current select menu the spacing feels off:
- The heading ("Code actions") sits directly on top of the filter line, so the two feel glued together.
- Above the heading there is a band of empty space, so the top of the prompt panel looks empty while its content is cramped.
- At the bottom, the footer hints ("Confirm enter   Cancel esc") sit on the very last line of the card with no padding below them, after a tall empty strip under the last option. The card looks bottom-heavy and the footer looks lost.

## Why now
The card look is approved; this polishes the proportions so the menu looks deliberate rather than accidental.

---

# Target Behavior

STATE 1 - Opened (first option selected). Blank rows shown as `·` for review only (they are invisible on screen):

```
 (prompt panel - lighter)
   ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄  <- half-height top edge
                       Code actions                       <- heading, centered
     |                                                <- filter line
   ·                                                  <- one row of padding

 (list panel - darker)
     ───────────────────────────────────────────────
     Disable diagnostics in the workspace  ◀
     ───────────────────────────────────────────────
     Disable diagnostics on this line
     - - - - - - - - - - - - - - - - - - - - - - - -
     Disable diagnostics in this file
   ·                                                  <- one blank row
                                 Confirm enter   Cancel esc
   ·                                                  <- one blank row (matches the one above)
```

- The heading is centered horizontally in the prompt panel (the filter line stays left-aligned).
- Prompt panel: four rows - a half-height top edge (a thin strip, not a full blank row), the heading, the filter line, one blank row.
- The top edge is drawn so the card's upper half-row blends into the dimmed backdrop; it keeps working if the backdrop strength is changed. Padding above and below is the same, matching the footer's one-row padding.
- List panel: the footer hints have exactly one blank row above them (below the last option) and exactly one blank row below them, so they float evenly inside the card instead of sitting on its bottom edge.
- Nothing else changes: separators, the framed selection, the pointer, colours and widths stay as they are.

─────────────────────────────────────────
STATE 2 - Few options (one option):

```
   ·
     Code actions
     |
   ·
     ───────────────────────────────────────────────
     Disable diagnostics in this file  ◀
     ───────────────────────────────────────────────
   ·
                                 Confirm enter   Cancel esc
   ·
```

─────────────────────────────────────────
STATE 3 - No matches:

```
   ·
     Select colorscheme
     zzz|
   ·

                    No matching items
   ·
                                 Confirm enter   Cancel esc
   ·
```

The footer keeps its padding above and below here as well.

---

# Scenarios

## 1 - Opening any select menu (happy path)

```
Step 1: Trigger a code action.
  The prompt panel shows a blank row, the heading, the filter line and a
  blank row: the padding above and below is equal.

Step 2: Look at the bottom of the card.
  The footer hints have one blank row above and one below; they no longer
  sit on the last line of the card.
```

## 2 - Filtering down to few results

```
Step 1: Type a query that leaves one option.
  The list shrinks; the footer still has one blank row above and below it.
```

## 3 - Many options (edge)

```
Step 1: Open a menu with more options than fit.
  The list scrolls as before; the footer padding is unchanged and the whole
  card, including the bottom padding row, stays on screen.
```

## 4 - Short terminal (edge)

```
Step 1: Open a menu in a short terminal window.
  The card shows fewer options if needed, but the heading, filter line and
  footer keep their padding and nothing is cut off at the bottom.
```

---

# Behavior Rules

- The prompt panel is exactly: blank, heading, filter line, blank (no gap between heading and filter).
- The footer has one blank row above it and one blank row below it, always (also in the empty state).
- Only vertical spacing changes. Behavior, colours, widths, separators and selection styling stay exactly as they are.
- The card never extends past the bottom of the screen.

---

# Success Criteria

- [ ] Padding above the heading equals padding below the filter line (one row each).
- [ ] The footer hints have one blank row above and one below them.
- [ ] The empty state and single-option menus keep the same padding.
- [ ] Tall lists and short terminals still fit on screen.
- [ ] Filtering, selecting and cancelling behave exactly as before.

---

# Out of Scope

- Any change to colours, widths, separators, pointer or footer wording.
- Restyling other menus.
