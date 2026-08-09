---
name: select-init
description: Themed floating replacement for vim.ui.select, with search filtering and optional per-item tags
generated: 2026-08-09
---

# Summary

Select replaces Neovim's plain `vim.ui.select` prompt with a themed floating box: a search field to filter items by typing, a bulleted marker on the highlighted row, and a footer of keybinding hints. The call contract (items, prompt, format_item, kind, on_choice) stays identical to the native API, so every existing caller keeps working unchanged.

---

# Problem

Today, anything that calls `vim.ui.select` - choosing an LSP code action, picking a git action, selecting from any plugin-provided list - shows Neovim's built-in picker: a plain, unstyled floating list (or a numbered command-line prompt on older setups). It can't be filtered by typing, shows no visual link to BeastVim's theme, and looks inconsistent with the editor's other floating dialogs.

## Why now

Confirm dialogs and the input prompt already got a themed, bordered redesign. `vim.ui.select` is the last of the three native `vim.ui.*`/prompt primitives still showing the stock Neovim UI, and it's triggered constantly (code actions, refactor choices, plugin menus) - so it's the most visible remaining gap in BeastVim's UI consistency.

---

# Target Behavior

```
STATE 1 — Default flat list (e.g. choosing an LSP code action):

           ╭─ Code actions ────────────────────────╮
           │ Search                                 │
           │                                         │
           │ ● Extract to function                  │
           │   Extract to variable                  │
           │   Organize imports                     │
           │   Add missing import                   │
           ├─────────────────────────────────────────┤
           │ Confirm enter   Cancel esc              │
           ╰─────────────────────────────────────────╯

    (centered, upper-middle of the screen - not tied to a specific
     buffer location, since selections usually aren't cursor-relative)
```

```
STATE 2 — Filtering by typing:

           ╭─ Select colorscheme ──────────────────╮
           │ drac█                                  │
           │                                         │
           │ ● dracula                               │
           │   dracula-soft                          │
           ├─────────────────────────────────────────┤
           │ Confirm enter   Cancel esc              │
           ╰─────────────────────────────────────────╯

  (list narrows live as the user types; matches on the displayed
   label text)
```

```
STATE 3 — Items with a right-aligned tag:

           ╭─ Select branch ────────────────────────╮
           │ Search                                 │
           │                                         │
           │ ● main                          current │
           │   feature/login-redesign         ahead 2│
           │   feature/payment-retry         behind 1│
           ├─────────────────────────────────────────┤
           │ Confirm enter   Cancel esc              │
           ╰─────────────────────────────────────────╯

  (tag text is dim/muted, right-aligned, separate from the label)
```

```
STATE 4 — Custom footer hints (caller adds extra actions):

           ╭─ Select branch ────────────────────────╮
           │ Search                                 │
           │                                         │
           │ ● main                          current │
           │   feature/login-redesign         ahead 2│
           ├─────────────────────────────────────────┤
           │ Confirm enter  Cancel esc  Delete ctrl+d │
           ╰─────────────────────────────────────────╯
```

```
STATE 5 — No matches after filtering:

           ╭─ Select colorscheme ──────────────────╮
           │ zzz█                                   │
           │                                         │
           │          No matching items              │
           ├─────────────────────────────────────────┤
           │ Confirm enter   Cancel esc              │
           ╰─────────────────────────────────────────╯
```

---

# Scenarios

## 1 — Choosing an LSP code action (happy path)

```
Step 1: The user triggers a code action on a diagnostic or selection.
  A bordered picker appears centered near the top of the screen,
  titled with the action prompt, listing each available action.
  The first item is highlighted with a bullet marker.

Step 2: The user presses down to move to a different action.
  The bullet marker and highlight move to that row.

Step 3: The user presses Enter.
  The box closes and the chosen action (and its index) is returned
  to the caller, exactly as native vim.ui.select would.
```

## 2 — Filtering a long list (e.g. colorscheme picker)

```
Step 1: The user opens a select prompt with many items (for example,
a plugin offering dozens of colorschemes).
  The picker appears with an empty search field and the full list
  visible below it.

Step 2: The user types a few letters.
  The list narrows immediately to items whose label matches, and
  the bullet marker moves to the new first match.

Step 3: The user presses Enter on a filtered result.
  That item is returned to the caller, same as Scenario 1.
```

## 3 — An item with a tag (e.g. branch picker built by a BeastVim lib)

```
Step 1: The user opens a select prompt where the caller has attached
a tag to each item (for example, "current" or "ahead 2" next to a
branch name).
  Each row shows its label on the left and its tag right-aligned in
  dim, muted text.

Step 2: The user picks a row as usual.
  Only the label (not the tag) is returned to the caller, matching
  what the caller originally passed in as that item's value.
```

## 4 — A picker with custom footer hints

```
Step 1: The user opens a select prompt where the caller supplied an
extra action hint (for example, a "Delete" action bound to ctrl+d).
  The footer shows the default Confirm/Cancel hints plus the extra
  hint the caller added.

Step 2: The user presses the extra action's key instead of Enter.
  The corresponding caller-defined behavior runs (this is scoped to
  BeastVim-internal callers that opt into the extension - see
  Behavior Rules).
```

## 5 — Filtering to zero results

```
Step 1: The user types a query that matches nothing in the list.
  The list area shows an empty-state message instead of a blank
  or confusing empty box.

Step 2: The user deletes characters to widen the query.
  Matching items reappear as soon as the query matches again.
```

## 6 — Cancelling the picker

```
Step 1: The user opens any select prompt.
  The box appears as described in the relevant state above.

Step 2: The user presses Esc.
  The box closes immediately and the caller receives no selection
  (nil), exactly matching native vim.ui.select cancellation behavior.
```

---

# Behavior Rules

- The call contract is unchanged for plain callers: items, `prompt`, `format_item`, `kind`, and `on_choice` all behave exactly as documented for native `vim.ui.select` - only the visual presentation changes. Every existing caller works with zero code changes.
- No section/group headers in v1 - all items render as a single flat, filtered list in the caller's original order (filtering only re-orders by match, never introduces headers).
- The search field filters live as the user types, matching against each item's displayed label text (not any hidden/internal value).
- The currently-highlighted row is marked with a bullet in the left margin; pressing Enter chooses that row.
- A right-aligned, dim/muted tag per item is optional - it's a BeastVim-specific extension. Third-party plugins using only the native contract simply don't produce a tag, and rows show label text only.
- The footer always shows the default Confirm/Cancel hints. Callers can optionally add extra hint entries next to them - this is also a BeastVim-specific extension available to BeastVim's own callers, not something arbitrary third-party plugins can hook into just by calling native `vim.ui.select`.
- When filtering produces zero matches, an empty-state message is shown instead of an empty list area.
- The picker appears as a centered overlay in the upper-middle of the screen (not cursor-anchored) - selections aren't generally tied to a specific piece of buffer text, unlike `input`'s rename use case.
- Visual chrome (rounded border, title, BeastVim theme colors, dim/muted text) matches the existing confirm dialog, input box, and finder search box for consistency.
- Esc (or leaving the window) cancels the prompt and returns nil to the caller, matching native cancellation semantics.
- When no UI is attached (headless), select falls back to native `vim.ui.select` behavior, consistent with how `input` and `confirm` already handle headless mode.

---

# Success Criteria

- [ ] Any plugin calling `vim.ui.select` (LSP code actions, git integrations, etc.) automatically gets the new themed picker with no caller-side code changes.
- [ ] Typing in the search field narrows the list live, matching against item labels.
- [ ] The highlighted row shows a bullet marker, and pressing Enter returns that item (and its index) to `on_choice`, matching native behavior.
- [ ] Items with a caller-supplied tag show it right-aligned in dim text, separate from the label.
- [ ] Callers that supply extra footer hints see them alongside the default Confirm/Cancel hints.
- [ ] Filtering to zero results shows an empty-state message, not a blank list.
- [ ] Esc cancels and returns nil, matching native `vim.ui.select`.
- [ ] Visual style (border, colors, title, bullet marker) matches BeastVim's existing confirm dialog, input box, and finder search box.

---

# Out of Scope

- Section/group headers (e.g. opencode's "Recent" / provider groupings) - explicitly deferred per user decision; the grouped version is "more complicated" and can be a follow-up spec if ever needed.
- A "currently active/default" marker distinct from the cursor-highlighted row - native `vim.ui.select` has no concept of a pre-selected default value.
- Multi-select (native `vim.ui.select` is single-choice only).
- Fuzzy-match scoring/ranking beyond simple substring filtering (finder's matcher could inform a later iteration, but isn't pulled in for v1).
