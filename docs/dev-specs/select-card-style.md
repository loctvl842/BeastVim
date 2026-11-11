---
name: select-card-style
description: Restyle the select menu as a padded prompt panel over a list panel with dashed separator slots and a solid-framed selection
generated: 2026-11-12
---

> PM Spec: [docs/pm-specs/select-card-style.md](../pm-specs/select-card-style.md)

# Summary
The select lib's list window renders a separator "slot" row above every option and below the last (dashed between options, solid blue around the selected one, blank at the edges), draws the selected option in blue bold with a `◀` pointer, and puts the footer hints in a blank bottom border row. The prompt becomes a lighter, padded panel made of a backing "header" window (blank row, heading, filter row, blank row) with the input window overlaid on its filter row. All windows are borderless; behavior (filtering, original indices, tags, footer hints, empty state, headless fallback) is unchanged.

---

# Context

## Problem
`select/ui.lua` builds a bordered input window (title cut into the border, `├─┤` join to the list) and `select/list.lua` shows one row per item with an inline bullet and a cursorline tint; the footer is the list border's native footer between box-drawing lines. None of this matches the theme picker's card look.

### Solution
`list.lua` adopts the finder's slot-row scheme (`2n + 1` rows, capacity `(h-1)//2`), moves selection styling to extmarks (selected text group, pointer), and reuses a blank bottom border row for the footer. `ui.lua` composes the prompt panel from a header window plus a borderless input window. `highlights.lua` swaps bullet/cursorline/border groups for panel, selection and separator groups.

---

# Research

### Repo Search
- Searched for: `BeastSelect*`, `footer`, `select` list code, finder's separator machinery, `select` references outside the lib, `tests/test-select-*`.
- Found:
  - `select/list.lua` is a small virtualized view (`_offset`, `clamp_offset`, `resize_to_fit`, tags as `right_align` extmarks, empty state).
  - `finder/ui/list.lua` already implements the exact slot scheme (`separated_capacity`, `slot()`, selected-text override, pointer extmark) and `finder/highlights.lua` has the matching groups (`ListSeparator`, `ListSelected`, `ListSelectedLine`, `ListPointer`).
  - The `BeastSelect*` groups are used only inside the select lib; `hl_reload` already re-applies `beast.libs.select.highlights`.
  - Native float `footer` needs a border; `ui.lua` uses `footer_pos = "right"`.
  - Only `tests/test-select-filter.lua` exists (filter matcher).
- Reuse opportunity: Yes - the finder slot logic is the reference, but the two lists differ (select has no grouping, no match highlights, dynamic window height), so the select list gets its own small version instead of a cross-lib dependency.

### Built-in / Existing Lib Check
- Checked: float `border` with blank cells, `footer`/`footer_pos`, extmark `virt_text` (inline, right_align, eol), overlapping floats via `zindex`, `winhl`.
- Found: a border of spaces with `FloatBorder` highlighted as the panel colour gives padding; a blank bottom border row can host the native footer; floats stack by `zindex` so an input window can sit on a backing header window.
- Decision: **Use** native float footer and blank borders; **Reuse** the finder slot design by copying the approach; **Build** the header window.

---

# Architecture Changes
- Modified `lua/beast/libs/select/highlights.lua` - new groups: `Normal` (list panel, darker), `InputNormal` (prompt panel, lighter), `InputTitle`, `ListSelected`, `ListSelectedLine`, `ListPointer`, `ListSeparator`, `ListTag`, `ListEmpty`, `Footer`; keep `Border` (blank border cells in the panel colour); drop `ListCursorLine`, `ListBullet`.
- Modified `lua/beast/libs/select/list.lua` - slot rows, selected styling, pointer, window height in rows (`2n + 1`), empty state, footer via blank bottom border.
- Modified `lua/beast/libs/select/ui.lua` - header window + borderless input, new geometry and top placement, list gets the footer, `close()` closes the header window.
- Modified `lua/beast/libs/select/health.lua` - expected-group list follows the new groups.
- New `tests/test-select-list.lua` - slot rows, selection frame, scrolling, empty state, tags.
- Modified `docs/CODEMAP/libraries.md` (select section).

## Implementation Phases

## Phase 1: List panel - dashed slots, framed selection, footer row
1. **Highlight groups** (File: `lua/beast/libs/select/highlights.lua`)
   - Action: define the groups above from the palette (list panel `dark2`, prompt panel `dark1`, selection `accent5`, separator `dimmed4`).
   - Why: panels differ in shade like the theme picker; selection needs its own groups.
   - Depends on: None
   - Risk: Low
2. **Slot rows and selection styling** (File: `lua/beast/libs/select/list.lua`)
   - Action: render a slot row above each visible option and below the last (solid `─` when next to the cursor, dashed `-` between options, blank at the edges); selected option text in `ListSelected` plus an eol `◀` pointer; inline pad of 2 on every row; capacity `(rows-1)//2`; window height `2*min(n, max_items)+1` (1 for empty); empty state row; list border = side pads + blank bottom row carrying the footer.
   - Why: PM rules for separators, frame, pointer, no tint.
   - Depends on: Step 1
   - Risk: Medium - cursor/offset math with 2-row items; `cursorline` off.
3. **Wire list geometry** (File: `lua/beast/libs/select/ui.lua`)
   - Action: pass max rows and footer to `list.create`; compute `total_h` from list rows; keep the old input for now.
   - Depends on: Step 2
   - Risk: Low
4. **Test** (File: `tests/test-select-list.lua`)
   - Action: headless floats; assert row layout, solid frame beside selection, dashes elsewhere, edge blanks, scrolling to the last item, wrap-around, empty state, tag extmark.
   - Depends on: Steps 1-2
   - Risk: Low

## Phase 2: Prompt panel - roomy header + filter line
1. **Header window and borderless input** (File: `lua/beast/libs/select/ui.lua`)
   - Action: replace the bordered input with (a) a non-focusable backing window, 4 rows tall, prompt-panel colour, containing blank / heading / filter row / blank, and (b) a 1-row borderless input window overlaid on row 3 with a 2-col side margin; placement `top` unchanged, list starts directly below the header; `close()` closes the header window too; the filter line shows no "Search" label (empty prompt text).
   - Why: heading + filter line in one lighter, bigger panel without borders.
   - Depends on: Phase 1
   - Risk: Medium - three stacked floats must open/close together and resize cleanly; BufLeave cancel must still work.
2. **Remove dead pieces** (File: `lua/beast/libs/select/ui.lua`)
   - Action: delete `format_title` border formatting and the old border table; keep the heading text.
   - Depends on: Step 1
   - Risk: Low

# Testing Strategy
- Headless: `nvim --clean --headless -l tests/test-select-list.lua`, `tests/test-select-filter.lua`.
- Bench: no hot-path lib touched.
- Manual (`NVIM_APPNAME=BeastVim`, tmux): trigger an LSP code action and a `vim.ui.select` with tags/footer hints (e.g. a Lua call); PM scenarios 1-6: navigation frame at top/bottom, filter, empty state, Esc, long labels, narrow terminal; compare exact panel colours (prompt lighter than list).

# Success Criteria
- [x] Lighter padded prompt panel over a darker list panel; no borders or divider.
- [x] Dashed lines between options; selected option framed by solid blue lines, blue bold text, `◀`, no tint.
- [x] Footer dim, right-aligned, including caller hints.
- [x] Tags right-aligned; long labels shortened, no overlap.
- [x] Empty state shown; Enter does nothing.
- [x] Selecting, filtering, cancelling and headless fallback unchanged (original index still returned).
- [x] New and existing select tests pass; stylua clean.

---

## Completed

2026-11-12 - Phase 1: list panel (slot rows, framed selection, pointer, footer row, label truncation). Phase 2: prompt panel (header window + overlaid borderless input).

- `d42ecf2` feat(select): dashed slots, framed selection and footer row in the list panel
- `3a97c0b` feat(select): roomy prompt panel with heading over a borderless filter line

Verification: `tests/test-select-list.lua` 27/27, `tests/test-select-filter.lua` 10/10; stylua clean; tmux E2E: prompt panel `34;31;34` lighter than list panel `25;24;26`, filtering, Enter returns the original index (2), Esc returns nil, window count unchanged after close, long label shortened so the pointer stays visible. `bench-ux.sh` not run (no hot-path lib touched).
