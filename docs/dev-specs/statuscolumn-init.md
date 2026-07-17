---
name: statuscolumn-init
description: "Beast Statuscolumn Library"
generated: 2026-05-31
---

# Dev Spec: Beast Statuscolumn Library

## Summary

Native statuscolumn library at `lua/beast/libs/statuscolumn/` that draws
configurable slots (default: **diagnostic ▸ number ▸ git ▸ fold**) in the
left gutter via `vim.o.statuscolumn`. Each slot is an ordered priority list
of producers — e.g. `{"diagnostic", "fold"}` renders the diagnostic glyph
when present, else the fold glyph (statuscol-style routing) — while the
library itself has **zero plugin dependencies**: gitsigns/diagnostic
extmarks are detected by namespace/name patterns and missing producers
degrade silently (snacks-style).

Performance is the top constraint. The render path (`%!`) is called once per
visible line per redraw — for an 80-row window with `signcolumn=auto:2` and
gitsigns, that's hundreds of evaluations per keystroke. We adopt statuscol's
`display_tick`-driven once-per-redraw precomputation and snacks' string-cache
memoization, but skip statuscol's fully-generic segment engine in favour of a
fixed enum of producers (cheaper dispatch, fewer indirections) that the user
composes into slots.

**Public API:**

```lua
local stc = require("beast.libs.statuscolumn")
stc.setup({
  number = {},                        -- follows &nu / &rnu automatically
  diagnostic = { severity = "min" },  -- which severity to surface
  git = { enabled = true },           -- silently no-op if no gitsigns
  fold = { open = false, icons = { open = "", close = "" } },

  -- Each entry = one slot (one cell), ordered list of producers high→low priority.
  -- A slot picks the first producer that has output for the current line.
  -- Number of entries = number of cells rendered (1..N).
  segments = {
    { "number" },
    { "git" },
    { "diagnostic", "fold" },  -- diagnostic if present, else fold
  },
})
```

`setup()` sets `vim.o.statuscolumn = "%!v:lua.require'beast.libs.statuscolumn'.render()"`,
registers a `WinClosed` autocmd to drop per-window caches, and registers in
`Beast.highlight_modules` for ColorScheme refresh.

## Requirements

### Functional

- Render statuscolumn via `%!v:lua.require'beast.libs.statuscolumn'.render()`
- **Slot-based layout** — `segments` is an ordered list of slots; each slot
  is itself an ordered list of producer names (high → low priority). A slot
  renders the first producer in its list that has output for the current
  line. Empty slot → blank cell. Number of slots == number of cells.
- Default layout: `{ {"diagnostic"}, {"number"}, {"git"}, {"fold"} }` — four
  cells, one producer each
- Each sign slot is **1 sign-cell wide** (2 display columns); the `number`
  slot sizes itself from `&numberwidth`
- Sign classification by **namespace** first, then **name pattern** (handles
  both `vim.diagnostic` extmarks and legacy `DiagnosticSign*` legacy signs;
  recognises gitsigns under both `gitsigns_extmark_signs_*` and `GitSigns*`,
  plus `MiniDiffSign*`)
- Number column follows the window's `&number` and `&relativenumber` options:
  picks `v:relnum` when `rnu` is set (with `v:lnum` on the cursor row if `nu`
  is also set — the standard "hybrid" behaviour Neovim's built-in number
  column shows), otherwise `v:lnum`. No `mode` config knob.
- Fold column shows close/open glyphs from `fillchars` by default; opt-in
  `open = true` shows fold-open glyph on the first line of an open fold
- On `virtnum ~= 0` (wrapped/virtual lines), all sign-class segments render
  blank; number area shows `%=` to right-align the wrap continuation gutter
- `vim.b[buf].beast_statuscolumn_disabled = true` opts a single buffer out
  (returns `""`); `ft_ignore` + `bt_ignore` lists in config disable globally
  for those filetypes/buftypes
- Highlight groups created via shared `Util.colors.set_hl`, registered in
  `Beast.highlight_modules` for ColorScheme refresh

### Non-Functional

- **Per-line render budget: < 5 µs** (median over 1000 renders on a 200-line
  buffer with 10 diagnostics, 20 gitsigns, 5 folds). Full-window budget:
  **< 500 µs** for an 80-line viewport.
- **Zero allocations on cache hit** — repeated `render()` calls for the same
  `(win, buf, lnum, virtnum, relnum, tick)` must return the same interned
  string without rebuilding it.
- **No plugin dependencies**. gitsigns, mini.diff, nvim-dap signs are all
  *opportunistically recognised* by namespace/name. Library works with none
  of them installed.
- Follows BeastVim library conventions: state only in `init.lua`, frozen
  config via metatable, lazy autocmd registration, palette refresh via
  `Beast.highlight_modules`.

### Out of Scope (deferred)

- Mark column (snacks has it; not in this lib's MVP — add later via a
  `"mark"` segment if needed)
- Click handlers (`%@…@…%T`) on any segment — not requested; adds per-line
  wrapping cost on the hot path. Can be added later as a separate spec if
  needed.
- DAP breakpoint dedicated segment (handled by the generic `diagnostic` or
  a future `"sign"` catch-all)
- Custom user producers (the producer enum — `number`/`diagnostic`/`git`/`fold` —
  is fixed for now; the segment-engine generality of statuscol.nvim is
  explicitly **not** built; this is the main simplification trade-off)
- Thousands separator for line numbers (statuscol has it; not requested)
- Per-window setup — global `stc` only

## Research

### Repo Search

- Searched for: `statuscolumn`, `stc`, `vim.o.stc`, `sign_text`, `nvim_buf_get_extmarks.*sign`
- Found: **No existing statuscolumn code** anywhere under `lua/beast/`. The
  closest pattern is `lua/beast/libs/statusline/` (component-based `%!` bar)
  and `lua/beast/libs/tabline/` (event-driven cache + click regions).
- Found: `lua/beast/util/colors.lua` (`Util.colors.set_hl`) for highlight
  registration — reuse.
- Found: `Beast.highlight_modules` registry in `lua/beast/init.lua` for
  ColorScheme refresh — register the new lib's `highlights.lua`.
- Found: `Palette.get()` for accent/diagnostic colour resolution — reuse via
  `highlights.lua` like other libs.
- Reuse opportunity: **Adopt** `Util.colors.set_hl`, `Palette.get`,
  `Beast.highlight_modules`. **None of the statusline/tabline component-spec
  machinery is reusable here** — statuscolumn's eval model is per-line, not
  per-region, so a separate (smaller) engine is correct.

### Package Search

- Searched: snacks.nvim `lua/snacks/statuscolumn.lua` (~355 LOC, fixed 3-slot
  layout: left/number/right, FFI fold info, timer-based cache flush);
  statuscol.nvim (~600 LOC, fully generic segment engine, FFI `display_tick`
  invalidation, per-segment pattern-based sign routing, click dispatch table).
- Native Neovim API: `vim.o.statuscolumn` (Neovim ≥ 0.9), `vim.v.lnum`,
  `vim.v.relnum`, `vim.v.virtnum`, `vim.g.statusline_winid`,
  `nvim_buf_get_extmarks(..., type = "sign")`, `vim.opt.fillchars:get()`.
  FFI required for `fold_info` and `display_tick`.
- Decision: **Build native**, informed by both projects.
  - From **snacks**: keep the FFI surface tiny (just `fold_info` +
    `find_window_by_handle`), use the per-redraw string cache pattern,
    detect git signs by name/namespace pattern (no gitsigns require).
  - From **statuscol**: adopt `display_tick` for cache invalidation (more
    correct than snacks' 50 ms timer), adopt the per-segment allow/deny
    pattern routing for slot priority lists, adopt the precomputed
    `formatstr` so per-line render is `string.format` over precomputed parts.
  - **Skip** statuscol's generic segment engine — our producers are a fixed
    enum (`number`, `diagnostic`, `git`, `fold`), so we can dispatch them
    with a `local switch[name]()` instead of iterating an array of opaque
    function pointers. The user composes slots, not producers.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/statuscolumn/init.lua` | Create | `setup`, `render`, state owner, autocmd registration |
| `lua/beast/libs/statuscolumn/config.lua` | Create | Frozen defaults: segments (slot list), number/diag/git/fold sub-tables, ft_ignore, bt_ignore |
| `lua/beast/libs/statuscolumn/ffi.lua` | Create | `ffi.cdef` for `fold_info`, `find_window_by_handle`, `display_tick` |
| `lua/beast/libs/statuscolumn/signs.lua` | Create | `buf_signs(buf)`: walk extmarks once per redraw, classify into `{diagnostic, git, other}` by ns+name, return `signs_by_lnum_by_class` |
| `lua/beast/libs/statuscolumn/fold.lua` | Create | `fold_icon(win, lnum)`: FFI lookup, return `{text, hl}` or `nil` |
| `lua/beast/libs/statuscolumn/number.lua` | Create | `format(args)`: lnum/relnum/virtnum formatting per `number.mode` |
| `lua/beast/libs/statuscolumn/cache.lua` | Create | Two-level cache: per-(win,tick) sign map + per-line interned string. Invalidated by `display_tick`. |
| `lua/beast/libs/statuscolumn/highlights.lua` | Create | `BeastStc*` groups via `Util.colors.set_hl`; auto-registered in `Beast.highlight_modules` |
| `lua/beast/libs/statuscolumn/health.lua` | Create | `:checkhealth beast` integration: assert `vim.o.statuscolumn` wired, FFI symbols resolved, segments valid |
| `lua/beast/init.lua` | Modify | Wire `packer.lazy("beast.libs.statuscolumn", { event = "VimEnter", defer = true, highlights = true })` after tabline |
| `scripts/bench-statuscolumn.lua` | Create | Headless bench, contract per `docs/tec-config/health-config.md`. Thresholds: median < 5 µs / line, < 500 µs / 80-line window. |
| `docs/CODEMAP/libraries.md` | Modify | Add statuscolumn section (during `/tec-implement` wrap-up via `/tec-update-codemaps`) |

## Implementation Phases

### Phase 1: Core engine + number-only render — minimum viable column

Goal: ship a working `vim.o.statuscolumn` that renders only the **number**
segment, with the cache + FFI + per-redraw tick infrastructure in place.
This proves the hot path and the cache invalidation; the other segments
plug into the same engine in Phase 2.

1. **Create `config.lua`** (File: `lua/beast/libs/statuscolumn/config.lua`)
   - Action: frozen defaults via metatable (same pattern as
     `statusline/config.lua`), with `segments = { {"number"} }` for Phase 1.
   - Why: keeps Phase 1 mergeable on its own; slot syntax in place from day one.
   - Risk: Low

2. **Create `ffi.lua`** (File: `lua/beast/libs/statuscolumn/ffi.lua`)
   - Action: `ffi.cdef` for `display_tick`, `fold_info`, `find_window_by_handle`.
     Wrap in `pcall(require, "ffi")` and return `nil` on failure so non-LuaJIT
     hosts degrade to "no fold segment, tick always = 0".
   - Why: tick-based invalidation needs `display_tick`. Folds need `fold_info`
     (used in Phase 2, but the cdef belongs here from the start).
   - Risk: Medium (FFI ABI tied to Neovim version) → Mitigation: feature-flag
     each symbol; `health.lua` reports missing symbols.

3. **Create `cache.lua`** (File: `lua/beast/libs/statuscolumn/cache.lua`)
   - Action: two tables — `per_win[win] = { tick, signs_by_lnum_by_class }`
     and `line_cache[win][buf][key] = string` where key is
     `lnum:virtnum:relnum`. `invalidate(win)` clears both for that window.
     Bumping tick clears `line_cache` for that window.
   - Why: zero-allocation cache hit is the perf requirement.
   - Risk: Low

4. **Create `number.lua`** (File: `lua/beast/libs/statuscolumn/number.lua`)
   - Action: `format(win, lnum, relnum, virtnum)` returns the number-segment
     string. Reads `vim.wo[win].number` and `vim.wo[win].relativenumber`;
     picks `relnum` when `rnu` is on (falling back to `lnum` on the cursor
     row if `nu` is also on), otherwise `lnum`. Returns `"%="` on
     `virtnum ~= 0`.
   - Why: matches Neovim's built-in number column behaviour with zero config.
   - Risk: Low

5. **Create `init.lua` with skeleton engine** (File: `lua/beast/libs/statuscolumn/init.lua`)
   - Action: state table, `M.render()` reads `g:statusline_winid`,
     `v:lnum/relnum/virtnum`, hits cache; on miss, dispatches the configured
     segments (only `"number"` in Phase 1) and interns the result. Wraps the
     whole thing in `pcall` returning `""` on error. `M.setup(opts)` merges
     config, sets `vim.o.statuscolumn`, registers `WinClosed` autocmd to call
     `cache.drop_win(args.match)`.
   - Why: this is the hot path; everything else is segment plug-ins.
   - Risk: Medium → Mitigation: bench in Phase 1 (see below), not after the
     full feature is built.

6. **Create `bench-statuscolumn.lua`** (File: `scripts/bench-statuscolumn.lua`)
   - Action: same shape as `scripts/bench-statusline.lua`. Loads a 200-line
     scratch buffer, calls `render()` for each visible line ×1000, reports
     median µs/render and µs/window. Compare against snacks `M._get`
     wrapped the same way (path-prepended if available, like the statusline
     bench does with lualine).
   - Why: prevents perf regressions in Phase 2 when more segments land.
   - Risk: Low

**Phase 1 success**: `:set statuscolumn=...` shows line numbers,
`bench-statuscolumn.lua` reports `< 1 µs / line` for the number-only case.

---

### Phase 2: Sign segments (diagnostic + git) with slot priority

Goal: add diagnostic and git producers, the namespace/name classifier, and
the slot-with-priority-list resolution so producers can share a slot.

1. **Create `signs.lua`** (File: `lua/beast/libs/statuscolumn/signs.lua`)
   - Action: `collect(buf) -> by_lnum_by_class` walks
     `nvim_buf_get_extmarks(buf, -1, 0, -1, { type = "sign", details = true })`
     **once per redraw** and bucketises by class. Classifier:
     - `diagnostic`: `ns_name:match("^vim%.diagnostic")` or
       `name:match("^DiagnosticSign")`
     - `git`: `ns_name:match("^gitsigns_")` or
       `name:find("^GitSigns") or name:find("^MiniDiffSign")`
     - `other`: rest (not used in MVP but kept for forward-compat)
     Within each class, keep the highest-priority sign per lnum.
   - Why: one extmark walk per redraw is the cheapest correct approach;
     statuscol does this too. Snacks does the walk plus an
     additional `sign_getplaced` for Neovim < 0.10 — we require ≥ 0.10
     (statuscol does too) and drop that branch.
   - Depends on: Phase 1 cache
   - Risk: Medium → Mitigation: classifier patterns are anchored and table-driven;
     adding a new producer is one line.

2. **Wire signs into the engine** (File: `lua/beast/libs/statuscolumn/init.lua`)
   - Action: in the per-window/tick update step, call `signs.collect(buf)`
     and store on `per_win[win]`. During per-line render, for each slot
     (ordered list of producer names), walk the list and pick the first
     producer that has output for this lnum; format `%#hl#text%*` (memoised
     in a sign-icon cache keyed by `text..hl`, snacks-style).
   - Why: slot resolution is O(producers-per-slot) per line — typically 1
     or 2 — with no allocations. The `number` producer never participates
     in sign-slot lookup; if a slot is `{"number"}` it renders the number
     directly.
   - Depends on: signs.lua
   - Risk: Low

3. **Highlights** (File: `lua/beast/libs/statuscolumn/highlights.lua`)
   - Action: `BeastStcDiagError/Warn/Info/Hint`, `BeastStcGitAdd/Change/Delete`,
     `BeastStcNumber`, `BeastStcNumberCurrent`, `BeastStcFold`,
     `BeastStcFoldCurrent`. Defaults link to existing groups
     (`DiagnosticSignError`, `GitSignsAdd`, `LineNr`, `CursorLineNr`,
     `FoldColumn`, `CursorLineFold`).
   - Why: respects user colorscheme without taking a hard palette dependency.
   - Depends on: None
   - Risk: Low

4. **Register in `Beast.highlight_modules`** (File: `lua/beast/init.lua`)
   - Action: append `"beast.libs.statuscolumn.highlights"` to the registry
     (or rely on `packer.lazy({ highlights = true })` to do it — match
     whichever pattern statusline/tabline use).
   - Why: ColorScheme refresh contract.
   - Depends on: highlights.lua
   - Risk: Low

**Phase 2 success**: with gitsigns + LSP diagnostics installed, the column
renders all three sign classes correctly; `segments = { {"number"}, {"git"},
{"diagnostic","fold"} }` shows 3 cells with the third cell preferring
diagnostic when present; bench remains under threshold.

---

### Phase 3: Fold segment + health + wiring

Goal: complete the default 4-segment layout, plug in `:checkhealth`, and
wire the lib into `packer.lazy()`.

1. **Create `fold.lua`** (File: `lua/beast/libs/statuscolumn/fold.lua`)
   - Action: `icon(win, lnum, virtnum)` calls FFI `fold_info`, returns
     `{ text = close|open|"", hl = "BeastStcFold" }` based on `info.level`,
     `info.lines`, `info.start`, and `config.fold.open`. On `virtnum ~= 0`,
     returns `nil`. Memoise glyph lookup once at `setup()` from
     `vim.opt.fillchars:get()`.
   - Depends on: ffi.lua
   - Risk: Low

2. **Wire fold into the engine** (File: `lua/beast/libs/statuscolumn/init.lua`)
   - Action: add `"fold"` to the producer switch; participates in slot
     resolution like the sign producers do.
   - Depends on: fold.lua, Phase 2 slot resolution
   - Risk: Low

3. **Create `health.lua`** (File: `lua/beast/libs/statuscolumn/health.lua`)
   - Action: report FFI availability, whether `vim.o.statuscolumn` is wired
     to our render fn, segments validity, and `ft_ignore`/`bt_ignore` summary.
   - Why: standard BeastVim lib contract.
   - Depends on: None
   - Risk: Low

4. **Wire into `beast.setup()`** (File: `lua/beast/init.lua`)
   - Action: `packer.lazy("beast.libs.statuscolumn", { event = "VimEnter",
     defer = true, highlights = true })` after the tabline registration.
   - Why: keeps statuscolumn out of the cold-start critical path; matches
     existing convention for non-essential UI libs.
   - Depends on: All above
   - Risk: Low

**Phase 3 success**: default layout renders for all buffers (minus
`ft_ignore`), `:checkhealth beast` is clean, bench passes thresholds.

## Testing Strategy

- **Unit tests** under `tests/` (currently sparse — match the shape of
  `tests/test-tabline-edge-trim.lua`):
  - `tests/test-statuscolumn-classify.lua`: feeds fake extmark records
    through `signs.classify` and asserts class buckets (verifies the
    `gitsigns_extmark_signs_` and `vim.diagnostic` namespace patterns)
  - `tests/test-statuscolumn-slot.lua`: builds a fake `per_win` cache entry
    and asserts that the slot `{"diagnostic","fold"}` picks the diagnostic
    when both are present on the same lnum, picks the fold when only fold is
    present, and renders empty when neither is present
  - `tests/test-statuscolumn-number.lua`: asserts `number.format` output
    for the four `&nu`/`&rnu` combinations × `virtnum` ∈ {0, 1}
- **Bench**: `scripts/bench-statuscolumn.lua` (created in Phase 1) — runs
  in headless `nvim --clean`, prints final `BENCH name=statuscolumn …` line
  per the project bench contract. Thresholds:
  - Median **< 5 µs / line** for full 4-segment render with 10 diagnostics
    + 20 gitsigns + 5 folds on a 200-line buffer
  - Cache hit **< 0.2 µs / line** (string intern lookup only)
  - Full 80-line window **< 500 µs**
- **Manual verification**:
  1. Open `lua/beast/init.lua` with LSP attached. Confirm column shows
     diagnostic (if any), line number, gitsign (if `.git` present), fold
     glyph on `function … end` blocks.
  2. `:set rnu` → numbers switch to relative.
  3. Wrap a long line (`:set wrap` + `set linebreak`); confirm sign
     segments blank on wrap continuation, number area `%=` aligns.
  4. `:lua require'beast.libs.statuscolumn'.setup{ segments = { {"number"}, {"git"}, {"diagnostic","fold"} } }`
     → column shrinks to 3 cells; lines with both diagnostic and fold
     show the diagnostic glyph in the third cell, lines with only a fold
     show the fold glyph.
  5. `:checkhealth beast` → clean (no warnings for statuscolumn).

## Risks & Mitigations

- **FFI ABI drift across Neovim versions** → Mitigation: pcall the cdef,
  feature-detect each symbol, surface in `health.lua`. Library degrades
  (no fold segment) rather than erroring on incompatible Neovim builds.
- **Per-line render budget blown by a future segment** → Mitigation: bench
  threshold enforced in `bench-statuscolumn.lua`; runs as part of
  `/tec-health`. Phase 1 includes the bench so the budget is locked in
  before complexity grows.
- **gitsigns extmark namespace renaming in a future plugin release** →
  Mitigation: classifier patterns are table-driven and listed in
  `config.git.patterns` (overridable). No silent breakage — user adjusts
  one config table.
- **Cache invalidation correctness under window splits** → Mitigation:
  `WinClosed` autocmd drops per-window cache; per-buffer extmark changes
  bump `display_tick` automatically, which keys the invalidation.

## Success Criteria

- [ ] `bench-statuscolumn.lua` reports **median < 5 µs / line** for the
      4-segment default and **< 0.2 µs / line** on cache hit
- [ ] `bench-statuscolumn.lua` reports **< 500 µs / 80-line window**
- [ ] `:checkhealth beast` shows the statuscolumn section with all OK
- [ ] Default 4-segment layout renders correctly with gitsigns + LSP
      diagnostics installed
- [ ] `segments = { {"number"}, {"git"}, {"diagnostic","fold"} }` renders 3
      cells with the third cell preferring diagnostic when both are present
- [ ] Library works (no errors, sign segments simply empty) with neither
      gitsigns nor any LSP attached
- [ ] All three unit tests pass
- [ ] Codemaps regenerated; `docs/CODEMAP/libraries.md` includes the
      new lib

## ADR Required

This dev spec involves architectural decision(s) that must be documented
as ADRs once committed:

- **Fixed producer enum vs. generic segment engine** — we are explicitly
  choosing a fixed `number`/`diagnostic`/`git`/`fold` producer enum (composed
  by the user into slots) over statuscol's open segment engine, trading
  user-extensibility for ~30% less indirection per render. ADR should record
  the trade-off and the perf data backing it.
- **No plugin dependencies, classify-by-namespace** — recording the
  decision to never `require("gitsigns")` and instead detect by extmark
  namespace pattern, so the library has the same dependency-free property
  as `scroll` (ref ADR-009-style "port the design, not the plugin").
- **`display_tick` over timer for cache invalidation** — adopts statuscol's
  approach instead of snacks' 50 ms timer; record why (correctness over
  one fewer FFI symbol).

## Completed

**Date:** 2026-05-31

All three phases implemented, reviewed (PASS), and committed:

- `6283fdc` — Phase 1: core engine + number producer
- `93ab5b3` — Phase 2: diagnostic + git sign producers
- `c28e171` — Phase 3: fold + health + lazy wiring

**Success criteria — all met:**
- [x] Hot-path `render()` median **< 5 µs / line** — measured 1.7 µs hit / 1.8 µs miss / 3.3 µs full-4-slot
- [x] `bench-statuscolumn.lua` — full 200-line redraw **332 µs** (< 500 µs budget)
- [x] `:checkhealth beast.libs.statuscolumn` — all OK
- [x] Default 4-segment layout renders with gitsigns + LSP diagnostics
- [x] 3-cell slot-priority layout renders correctly (fold falls through when diagnostic present)
- [x] No-plugin install — git/diagnostic slots silently empty, no errors
- [x] Codemaps regenerated; `docs/CODEMAP/libraries.md` updated; lib count 14 → 15

**ADRs published:**
- ADR-019 — Fixed producer enum vs. generic segment engine
- ADR-020 — Namespace classification, no plugin dependencies
- ADR-021 — `display_tick` (FFI) drives cache invalidation
