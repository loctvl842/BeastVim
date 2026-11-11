---
name: select-card-style
description: Restyle the select menu like the theme picker - a roomy prompt panel over a list panel with dashed separators and a solid-framed selected row
generated: 2026-11-11
---

# Summary
The select menu (code actions, plugin choice lists, anything that asks the user to pick from a list) takes on the same look as the theme picker: a roomy prompt panel on top (heading plus filter line), a darker list panel below with dashed lines between options, and the selected option framed by solid lines. Behavior stays exactly the same.

---

# Problem

The current select menu is a bordered box: the title is cut into the top border, a "Search" label sits inside, a horizontal divider separates the footer, and a bullet marks the selected row. It reads as heavy and busy, and it does not look like the theme picker, which has a calmer, more spacious design.

## Why now
The theme picker now has a calm panel look. The select menu is the most frequently seen list menu (every code action), so it should match that quality.

---

# Target Behavior

STATE 1 - Opened (first option selected). Two borderless panels: a lighter, taller prompt panel above a darker list panel.

```
   (prompt panel - lighter, padded)
     Code actions                                   <- heading, warm accent colour
     |                                              <- filter line, cursor only when empty

   (list panel - darker)
     ───────────────────────────────────────────────  <- solid, blue (frames the selected option)
     Disable diagnostics in the workspace  ◀           <- selected: blue bold text, pointer
     ───────────────────────────────────────────────  <- solid, blue
     Disable diagnostics on this line
     - - - - - - - - - - - - - - - - - - - - - - - -  <- dashed, dim
     Disable diagnostics in this file
                               Confirm enter   Cancel esc   <- dim, right-aligned
```

- No box borders and no divider before the footer. The prompt panel has generous padding above and below its two lines, so it looks bigger than the old search row.
- Options are separated by dashed lines (`-------`). The selected option has no background tint; instead the lines directly above and below it are solid and blue, its text turns blue and bold, and a `◀` pointer follows it. At the top or bottom of the list the solid line still frames the selected option.
- The footer hints sit dim and right-aligned on the last line of the list panel.

─────────────────────────────────────────
STATE 2 - Filtering by typing:

```
     Select colorscheme
     drac|

     ───────────────────────────────────────
     dracula  ◀
     ───────────────────────────────────────
     dracula-soft
                         Confirm enter   Cancel esc
```

The list narrows live; the frame and pointer sit on the first match.

─────────────────────────────────────────
STATE 3 - Options with a right-aligned tag:

```
     Select branch
     |

     ───────────────────────────────────────────
     main  ◀                              current
     ───────────────────────────────────────────
     feature/login-redesign               ahead 2
     - - - - - - - - - - - - - - - - - - - - - -
     feature/payment-retry               behind 1
                         Confirm enter   Cancel esc
```

Tags stay dim and right-aligned.

─────────────────────────────────────────
STATE 4 - Extra footer hints from the caller:

```
                Confirm enter   Cancel esc   Delete ctrl+d
```

─────────────────────────────────────────
STATE 5 - No matches:

```
     Select colorscheme
     zzz|

                    No matching items
                         Confirm enter   Cancel esc
```

---

# Scenarios

## 1 - Choosing a code action (happy path)

```
Step 1: Trigger a code action.
  The prompt panel shows the heading "Code actions" and an empty filter line;
  the list panel shows the actions with the first one framed by solid lines.

Step 2: Press Down.
  The solid frame, blue text and pointer move to the next option.

Step 3: Press Enter.
  The panel closes and the chosen action runs, as before.
```

## 2 - Filtering a long list

```
Step 1: Open a select with many items, type "drac".
  The list narrows to matches; the frame and pointer sit on the first match.

Step 2: Delete the letters.
  The full list returns.
```

## 3 - Tags and extra footer hints

```
Step 1: Open a menu whose items carry tags and extra hints (e.g. branches).
  Tags are dim and right-aligned in each row; the footer lists the extra
  hint after Confirm and Cancel.
```

## 4 - No matches (edge)

```
Step 1: Type a query that matches nothing.
  "No matching items" is shown in the list area, centered; Enter does nothing.
```

## 5 - Cancel

```
Step 1: Press Esc.
  The panel closes; the caller receives no selection, as before.
```

## 6 - Long labels and narrow terminals (edge)

```
Step 1: Open a menu with a label longer than the panel, or in a narrow terminal.
  The label is shortened with "..." before the tag/edge; the pointer
  and footer never overlap text.
```

---

# Behavior Rules

- Only the look changes. Choosing, filtering, cancelling, tags, custom footer hints and the empty state behave exactly as today, and every existing caller works unchanged.
- Same visual language as the theme picker: borderless panels, the prompt panel lighter than the list panel, dashed separators between options, solid blue frame lines around the selected option, blue bold text plus a `◀` pointer on it, no background tint.
- The heading uses a warm accent colour and is shown only when the caller provided a prompt; the filter line shows only a cursor when empty (no "Search" label).
- Footer hints are dim and right-aligned on the last line of the list panel.
- Position, width and the dimmed backdrop behind the panels stay as they are today.

---

# Success Criteria

- [ ] The menu shows a lighter, padded prompt panel (heading + filter line) above a darker list panel, with no border lines and no divider.
- [ ] Options are separated by dashed lines.
- [ ] The selected option is framed by solid blue lines, has blue bold text and a pointer, and has no background tint.
- [ ] Footer hints are dim and right-aligned, including caller-added hints.
- [ ] Tags stay right-aligned and dim; long labels are shortened without overlap.
- [ ] The empty state is shown when filtering finds nothing.
- [ ] Selecting, filtering, cancelling and headless fallback behave exactly as before.

---

# Out of Scope

- Changing the confirm dialog, input box or other menus (can follow once this look is approved).
- New features (groups, multi-select, previews).
- Changing where the panel appears or how wide it is.

---

# Revision (2026-11-12): thick selection block

The selected option is no longer framed by solid blue lines. Instead it is drawn as a thick block: a tinted background behind the option, with a half-height tinted strip above it (`▄`) and below it (`▀`). The blue bold text and the `◀` pointer stay. Dashed lines between the other options are unchanged. This supersedes the "solid blue lines" and "no background tint" rules above for the select menu.
