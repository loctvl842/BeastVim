# Dev Spec: Tabline Edge-Trim Truncation

## Summary

Replace the current fixed-reserve truncation in the tabline buffer list with an
edge-trim algorithm. Today, a fixed `truncation_marker_reserve` (8 cols) is
subtracted from each side *before* fitting, which wastes space and shows fewer
buffers. The new approach fits the **maximum** number of whole cells first (no
reserve), then trims the outermost visible cells to make room for truncation
markers.

Conceptually, markers **overlay** the edge cells. Since a tabline is a flat
string (no layering), we achieve this by shortening the edge cells' names — the
leftmost cell gets a leading-ellipsis name, the rightmost gets a trailing-
ellipsis name — freeing exactly enough columns for the markers.

## Example Behavior

All examples assume:
- 20 open buffers, each with a cell width of 18 columns
- Terminal width where the tabfill area (columns − sidebar − tabpages) = 180
- Buffer 10 is the anchor (active buffer)

### Current behavior (fixed-reserve, wasted space)

```
Available = 180
Reserve per side = 8 → effective available = 180 − 16 = 164
Cells that fit: floor(164 / 18) = 9 cells
Visible width: 9 × 18 = 162
Wasted: 164 − 162 = 2 cols (gap between last cell and marker on each side)
```

```
                                      180 cols
├────────────────────────────────────────────────────────────────────────────────┤
 6 …  ··  buf7 ▕  buf8 ▕  buf9 ▕ >buf10<▕  buf11 ▕  buf12 ▕  buf13 ▕  buf14 ▕  buf15 ▕ ·· … 5
      ^^gap                                                                       ^^gap
```

Only **9 buffers** visible. The fixed 8-col reserves are wider than the actual
markers, and the fractional leftover between the last cell and the marker is
blank.

### After: edge-trim with marker overlay

```
Available = 180
First pass: fit without reserve → 10 cells (10 × 18 = 180), 5 hidden left, 5 hidden right
Marker widths: " 5 … " = 5 cols (left), " … 5 " = 5 cols (right) → total 10 cols
Space to free: 10 − (180 − 180) = 10 cols
Trim: right edge cell loses 5 cols → width 13; left edge cell loses 5 cols → width 13
Final: 5 + 13 + (8 × 18) + 13 + 5 = 180 ✓
```

```
                                      180 cols
├────────────────────────────────────────────────────────────────────────────────┤
 5 …  …uf6 ▕  buf7 ▕  buf8 ▕  buf9 ▕ >buf10<▕  buf11 ▕  buf12 ▕  buf13 ▕  bu…▕ … 5
```

Key differences:
- **10 buffers** visible (vs 9 before) — one more buffer shown.
- **Left edge**: `…uf6` is `buf6` rendered as a full cell with leading ellipsis —
  icon, padding, close slot, and separator are all present, only the name is
  shortened. The `5 …` marker sits flush to the left.
- **Right edge**: `bu…` is `buf14` rendered with trailing ellipsis — same full
  cell chrome. The `… 5` marker sits flush to the right.
- **No wasted space**: every column is occupied.

### The algorithm step by step

Given: `listed[]` (all buffers), `anchor` (active buffer), `available` (width)

1. **Pre-calculate cell widths** — for each buffer, compute full cell width
   (pad + icon + name + status + close + separator), clamped between
   `min_cell_width` and the natural width with `max_name_width`.

2. **Fit around anchor** — using `fit_around_anchor()` with the full
   `available` width (no reserve subtracted). Returns `visible[]`,
   `left_hidden`, `right_hidden`, `total_width`.

3. **No truncation?** → if `left_hidden == 0 && right_hidden == 0`, render
   normally — done.

4. **Compute exact marker widths**:
   - `left_marker_w = 1 + #tostring(left_hidden) + 3` → e.g. `" 6 … "` = 5
   - `right_marker_w = 1 + #tostring(right_hidden) + 3` → e.g. `" … 4 "` = 5
   - `total_markers_w = left_marker_w + right_marker_w`

5. **Compute space to free**:
   - `gap = available - total_width` (leftover from step 2, often 0)
   - `need_to_trim = total_markers_w - gap`
   - If `need_to_trim ≤ 0`: markers fit in the existing gap — just place them.

6. **Trim right edge cell** (if `right_hidden > 0`):
   - `rightmost = visible[#visible]`
   - `overhead = cell_overhead(rightmost)` (pad + icon + status + close + sep)
   - `max_trimmable = est_width(rightmost) - overhead - 1` (keep ≥ 1 char for `…`)
   - If `need_to_trim ≤ max_trimmable`:
     - Shorten name by `need_to_trim` cols → trailing ellipsis (`name_mod.truncate_text_end`)
     - `need_to_trim = 0`
   - Else (can't trim enough — cell too narrow):
     - Drop this cell entirely → `right_hidden += 1`, recalculate `right_marker_w`
     - Freed cols = full cell width; recalculate `need_to_trim`

7. **Trim left edge cell** (if `left_hidden > 0`): mirror of step 6 with
   leading ellipsis (`name_mod.truncate_text`).

8. **Iterate if needed** — if both edges were trimmed and `need_to_trim` is
   still > 0 (extremely rare: only when markers grow due to digit-count
   increase after dropping a cell), repeat steps 6–7.

9. **Render**: `left_marker + visible cells (edge cells with shortened names via ctx.names_by_buf override) + right_marker`

### Edge cases

**Edge cell drops below minimum** — if trimming would leave fewer columns than
`cell_overhead + 1` (no room for even one character + ellipsis), the edge cell
is dropped entirely. Its buffer moves to the hidden count, the marker count
increments, and the marker may widen by one digit. In the worst case this
cascades one level (the next cell becomes the edge and is trimmed instead).

**All buffers fit** — no markers, no trimming, no change from current behavior:

```
  init.lua  ▕  config.lua  ▕  buffer_list.lua 󰅖▕  cell.lua  ▕
```

**Single-side truncation** — when only one side has hidden buffers (anchor is
near the start or end of the list), only that side gets a marker and only that
edge cell is trimmed. The other side renders normally.

**Anchor alone exceeds available** — the existing anchor-overflow fallback
(shrink anchor name) runs before this algorithm and is unchanged.

## Requirements

- **R1**: First pass fits the **maximum** number of whole cells around the
  anchor using the full available width (no reserve subtracted). This maximises
  the number of visible buffers.
- **R2**: When truncation is needed, the outermost visible cells are **trimmed**
  to make room for truncation markers. The right-edge cell name uses **trailing
  ellipsis** (`highlig…`). The left-edge cell name uses **leading ellipsis**
  (`…t.lua`). Trimmed cells keep full cell chrome (pad, icon, close, sep).
- **R3**: An edge cell must not shrink below `cell_overhead + 1` (room for at
  least one character + ellipsis). If it cannot, the cell is **dropped** — its
  buffer joins the hidden count, and the next cell becomes the edge.
- **R4**: Truncation markers use **exact widths** based on hidden count
  (`" N … "` = 1 + digits + 3), not the fixed 8-column `truncation_marker_reserve`.
- **R5**: Edge cells remain clickable (same `%@…@` click region as normal cells)
  and are included in the `visible_buffers` return for public API consumers.

### Out of scope

- Changing `cell.render()` internals — edge cells reuse it via name override.
- Multi-column partial cells (showing 2+ partial buffers on one edge).
- Config options for this behaviour — it is always-on.

## Research

### Repo Search
- Searched for: `truncat`, `marker_reserve`, `cell_overhead`, `fit_around_anchor`
- Found:
  - `truncate.lua:46` — `fit_around_anchor()` does the anchor-centered fitting
  - `truncate.lua:20` — `estimate_cell_width()` computes full cell width with
    hardcoded `icon_w=2`, `sep_w=1`
  - `truncate.lua:123` — `cell_overhead()` computes non-name width (also hardcoded)
  - `buffer_list.lua:63-75` — two-pass truncation with fixed `truncation_marker_reserve`
  - `cell.lua:66` — `cell.render()` already reads `ctx.names_by_buf[bufnr]` for the
    display name, then truncates to `max_name_width`
  - `name.lua:84` — `truncate_text()` does leading-ellipsis truncation
- Reuse opportunity: **Adopt** — edge cells reuse `cell.render()` by overriding
  `ctx.names_by_buf[bufnr]` before the render call. Only `name.lua` needs a new
  `truncate_text_end()` for trailing-ellipsis (right edge).

### Package Search
- Searched: Neovim native API
- Found: `vim.fn.strdisplaywidth`, `vim.fn.strcharpart`, `vim.fn.strchars` —
  already used in `name.lua` for multibyte-safe truncation.
- Decision: **Use native** — no new dependencies.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/tabline/name.lua` | Modify | Add `truncate_text_end()` for trailing-ellipsis |
| `lua/beast/libs/tabline/truncate.lua` | Modify | `fit_around_anchor()` returns `total_width`; remove `truncation_marker_reserve` dependency |
| `lua/beast/libs/tabline/sections/buffer_list.lua` | Modify | Replace fixed-reserve two-pass with fit-then-trim edge algorithm |
| `lua/beast/libs/tabline/config.lua` | No change | `truncation_marker_reserve` kept for backward compat but no longer used by buffer_list |

## Implementation Phases

### Phase 1: Add trailing-ellipsis helper — `name.truncate_text_end()`

1. **Add `truncate_text_end(text, max_width)`** (File: `lua/beast/libs/tabline/name.lua`)
   - Action: New function below `truncate_text()`. Mirrors its structure but keeps
     the beginning of the string and appends `…`. Fast ASCII path + slow multibyte path.
   - Why: R2 — right-edge cells need trailing ellipsis.
   - Depends on: None
   - Risk: Low — pure string function, no side effects.

### Phase 2: Return total_width from fit_around_anchor

1. **Modify `fit_around_anchor()` return** (File: `lua/beast/libs/tabline/truncate.lua`)
   - Action: Add 4th return value `total_width` (the accumulated width of all
     visible cells). Already tracked as a local — just return it.
   - Why: R1 — `buffer_list.lua` needs the exact consumed width to compute
     how much space to free for markers.
   - Depends on: None
   - Risk: Low — additive change, existing callers can ignore the 4th return.

### Phase 3: Edge-trim algorithm in buffer_list.render()

1. **Replace two-pass fixed-reserve with fit-then-trim algorithm**
   (File: `lua/beast/libs/tabline/sections/buffer_list.lua`)
   - Action: Rewrite the truncation section of `M.render()`:

     **Step A — Fit max cells**: Call `fit_around_anchor()` with the full
     `available` width (no reserve). Get `visible[]`, `left_hidden`,
     `right_hidden`, `total_width`.

     **Step B — No truncation fast path**: If `left_hidden == 0` and
     `right_hidden == 0`, skip to rendering.

     **Step C — Exact marker widths**: Compute
     `left_marker_w = left_hidden > 0 and (1 + #tostring(left_hidden) + 3) or 0`
     and same for right. `total_markers_w = left_marker_w + right_marker_w`.

     **Step D — Space to free**: `gap = available - total_width`,
     `need_to_trim = total_markers_w - gap`. If ≤ 0, markers fit in
     existing gap — skip trimming.

     **Step E — Trim right edge**: If `right_hidden > 0` and `need_to_trim > 0`,
     compute `overhead = cell_overhead(rightmost)` and
     `max_trimmable = est_fn(rightmost) - overhead - 1`. If
     `need_to_trim ≤ max_trimmable`, shorten the name to
     `original_name_w - need_to_trim` via `truncate_text_end()` and override
     `ctx.names_by_buf[rightmost]`. Else drop the cell: move it to
     `right_hidden`, re-add its full width to `gap`, recalculate marker width.

     **Step F — Trim left edge**: Mirror of Step E using `truncate_text()`
     (leading ellipsis).

     **Step G — Render**: Left marker string + `cell.render()` loop over
     `visible` (edge cells pick up shortened names from `ctx.names_by_buf`) +
     right marker string.

   - Why: R1 (max cells first), R2 (edge trim with ellipsis), R3 (drop if
     too narrow), R4 (exact markers), R5 (clickable edge cells).
   - Depends on: Phase 1 (truncate_text_end), Phase 2 (total_width return)
   - Risk: Medium — core render logic change. Mitigated by keeping the same
     `cell.render()` path (edge cells are just normal cells with shorter names).

   **Key detail**: Edge cells use `cell_overhead()` (which includes close_w and
   status_w) to compute available name space. This means edge cells render with
   full cell structure — the name just gets shorter. The `cell.render()` call
   reads the pre-truncated name from `ctx.names_by_buf[bufnr]` and applies its
   own `truncate_text(name, max_name_width)` — since we already truncated to
   `name_w ≤ max_name_width`, this is a no-op pass-through.

## Testing Strategy

- **Unit tests**: None currently exist for tabline. Not adding in this spec
  (tracked separately).
- **Bench**: The existing `scripts/bench-tabline.lua` (if present) should show
  no regression. The extra work is O(1) per render (at most 2 edge-cell
  overhead calculations).
- **Manual verification**:
  1. Open 8+ buffers with varying name lengths.
  2. Shrink terminal width until truncation kicks in.
  3. Verify: right-edge cell shows `name…▕` filling space before `N …` marker.
  4. Verify: left-edge cell shows `…name▕` filling space after `N …` marker.
  5. Verify: no wasted gap between the last visible cell and the marker.
  6. Verify: when all buffers fit, no markers appear (no regression).
  7. Verify: clicking edge cells switches to that buffer.
  8. Verify: tabline string length ≤ `vim.o.columns` (no overflow).

## Risks & Mitigations

- **Risk**: Width estimation mismatch between `cell_overhead()` / `estimate_cell_width()`
  (which hardcode `icon_w=2`, `sep_w=1`) and actual rendered widths (Nerd Font
  icons can be 2 display columns, separator `▕` is 1 column).
  → **Mitigation**: For this spec, keep the existing hardcoded estimates — they
  are conservative (overcount by ~0-1 col), which means edge cells leave a
  tiny gap rather than overflow. A follow-up spec can switch to actual
  `displaywidth()` calls in `cell_overhead()` if the gap is noticeable.

- **Risk**: Edge cell name override mutates `ctx.names_by_buf` (shared state).
  → **Mitigation**: `ctx` is rebuilt fresh every render, never reused across
  frames. Mutation within a single render is safe.

## Success Criteria

- [ ] Right-edge buffer fills remaining space with `name…▕` (trailing ellipsis)
- [ ] Left-edge buffer fills remaining space with `…name▕` (leading ellipsis)
- [ ] Truncation marker always flush to the edge — no visible gap
- [ ] Tabline output string display width ≤ `vim.o.columns` (verified via
      `:lua print(vim.fn.strdisplaywidth(require("beast.libs.tabline").render()))`)
- [ ] Clicking an edge cell switches to that buffer
- [ ] No truncation markers when all buffers fit (no regression)
- [ ] Codemap regenerated and committed alongside
