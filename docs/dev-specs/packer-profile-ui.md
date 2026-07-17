---
name: packer-profile-ui
description: "Packer Profile UI"
generated: 2026-05-13
---

# Dev Spec: Packer Profile UI

## Baseline Checkpoint

**Commit `24c0f83` (`feat(packer): early apply colorscheme`)** is the known-good
baseline before this work begins. At this point the packer library has:

- Working setup pipeline with classification (eager/lazy/manual)
- Early colorscheme apply
- Per-plugin profiling (`packadd_ms`, `config_ms`, `total_ms`, `loaded_at`,
  `reason`)
- Phase profiling (`pack_add`, `early_cs`)
- A minimal profile UI page that lists plugin names + total time
- All success criteria from `packer-phase-profiling.md` met

If anything in this spec goes sideways during implementation,
`git reset --hard 24c0f83` returns the lib to a fully working state without
losing any user-visible feature. Tag this as `packer-baseline-2026-05-04` if
desired.

## Summary

Replace the current barebones profile page in `packer/ui.lua` with a
table-style layout inspired by Neovim's built-in profile views. The page will have
three sections:

1. **Startup timeline** — lifecycle checkpoints with deltas and a cumulative bar
2. **Plugins table** — sortable, filterable, optionally grouped by load reason
3. **Not-loaded table** — installed-but-not-loaded and not-installed plugins

Phase 1 ships the UI using **only existing data** (`profile.profiles`,
`profile.phases`). Phase 2 adds the missing measurements (init/config split,
lifecycle markers) so the timeline section becomes real instead of hypothetical.

## Requirements

### Phase 1 (UI rebuild, no schema change)

- Table renderer with column-aligned output. Columns: `#`, `NAME`, `TOTAL`,
  `PACKADD`, `INIT`, `CONFIG`, `%`, `REASON` (+ optional `DETAIL` in grouped
  mode).
- `INIT` column shows `0.00` until Phase 2 lands — accepts current data shape
  but is wired so Phase 2 just populates the field.
- Three keymaps inside the profile view:
  - `S` — cycles sort: `total → packadd → config → name → chrono`
  - `F` — cycles filter threshold: `0 → 1 → 5 → 10 → 50 ms`
  - `G` — toggles group-by-reason mode
- Sort, filter, and group state are stored on `Beast.Packer.UI.Main`.
- Timeline section renders **whatever phase data is present** — Phase 1 shows
  just `early_cs` and `pack_add`; Phase 2 fills in `setup_start`, `setup_done`,
  `VimEnter`, `UIEnter` automatically.
- Not-loaded section shows installed status (`installed` / `not installed`)
  and the plugin's declared trigger (manual / event / cmd / etc.).
- Existing single-line list view (the current profile page) is removed —
  replaced entirely.

### Phase 2 (measurement additions)

- Split `init_ms` and `config_ms` as separate fields on `Beast.Packer.LoadProfile`
  (today both are recorded as `config_ms`, lumped together, which is wrong).
- Add a lifecycle marker map to `beast.libs.packer.profile`:
  - `setup_start` — captured at top of `M.setup`
  - `setup_done` — captured at bottom of `M.setup`
  - `VimEnter` — captured by an autocmd registered during setup
  - `UIEnter` — captured by an autocmd registered during setup
- Each marker stores `{ at_ms = <ms since setup_start>, ts = <hrtime ns> }`.
- Expose markers via `profile.markers` (read-only, parallel to `profile.phases`).
- Compute `setup_total_ms` = `markers.setup_done.at_ms` — surface in the
  Summary section header.

## Out of scope

- Per-import time (`import.expand_imports` still recorded as a single phase).
- Per-`plugin/*.lua` sourcing time (deferred — `--startuptime` already shows it).
- `triggers_setup_ms` and `eager_config_ms` phases (deferred to a future spec).
- CPU-time-till-UIEnter (deferred — wall time is sufficient for our health
  checks).
- Dependency tree visualization (parent → child indenting). Reason-based
  grouping is enough for now; a tree view is a future spec.
- Mouse interactions / collapse-expand for groups. `G` is binary on/off only.
- Persistence of sort/filter/group state across UI open/close cycles.

## Research

### Repo Search

- Searched: `apply_segments`, `view_mode`, `sort_mode`, `_render_profile`,
  `Beast.Packer.UI.Segment`, `Main:extend`.
- Found:
  - `lua/beast/libs/packer/ui.lua:134` — `apply_segments(main, lines_segments)`
    is the standard render path. Each line is an array of `{ text, hl }`
    segments. Reuse this verbatim for the new table renderer.
  - `lua/beast/libs/packer/ui.lua:27-33` — `Beast.Packer.UI.Main` already
    carries `sort_mode` and `view_mode`. New fields (`filter_threshold`,
    `group_by_reason`, `sort_mode` extension) drop into the same View
    subclass.
  - `lua/beast/libs/packer/ui.lua:463-494` — `Main._render_profile(main)` is
    the function to replace.
  - `lua/beast/libs/packer/ui.lua:674-679` — `_actions_handler.sort` is
    where `S` cycling lives. The `name <-> time` toggle becomes a 5-way
    cycle.
  - `lua/beast/libs/packer/config.lua:42-72` — UI actions are config-driven.
    New `F` and `G` keys must be added to `defaults.ui.actions`.
  - `lua/beast/libs/view.lua` — base View class. Already used. No change.
- Reuse opportunity: **Adopt** — every renderer, every state field, every
  keybinding plug fits the existing `apply_segments` + `Main` View subclass
  pattern. No new abstractions.

### Package Search

- Searched: native Neovim API for autocmd-based lifecycle hooks.
- Found:
  - `vim.api.nvim_create_autocmd("VimEnter", ...)` — fires after `init.lua`
    finishes and before the first redraw.
  - `vim.api.nvim_create_autocmd("UIEnter", ...)` — fires once per UI
    attach. Lazy uses this as their primary "startup-done" marker.
  - `vim.uv.hrtime()` (already wrapped as `Util.hrtime`) — nanosecond clock.
- Decision: **Use native** — no new dependencies. Lifecycle markers piggyback
  on existing autocmd primitives.

## Architecture Changes

| File | Action | Purpose |
|---|---|---|
| `lua/beast/libs/packer/ui.lua` | Modify | Replace `_render_profile` with the new table renderer; add timeline + not-loaded sections; wire `S`/`F`/`G` actions. |
| `lua/beast/libs/packer/config.lua` | Modify | Add `F` (Filter) and `G` (Group) entries to `defaults.ui.actions`. Update `Beast.Packer.UI.Main` annotation in ui.lua to include new fields. |
| `lua/beast/libs/packer/profile.lua` | Modify (Phase 2 only) | Add `markers` table + helpers `set_marker`, `markers_iter`. Split `init_ms` from `config_ms` in `Beast.Packer.LoadProfile`. |
| `lua/beast/libs/packer/init.lua` | Modify (Phase 2 only) | Capture `setup_start` / `setup_done` markers; register `VimEnter` / `UIEnter` autocmds for their markers. Change Step 2 init loop to record `init_ms` instead of `config_ms`. |
| `lua/beast/libs/packer/state.lua` | Modify (Phase 2 only) | If a plugin's `init` is invoked from `state.load` for any reason, record into `init_ms` not `config_ms`. (Audit needed — currently all `state.load` paths use `config_ms`.) |
| `lua/beast/libs/packer/highlights.lua` | Modify | Add highlight groups for new UI elements: `BeastPackerTableHeader`, `BeastPackerBar`, `BeastPackerBarDim`, `BeastPackerSectionDivider`, `BeastPackerCheckpoint`, `BeastPackerSummaryLabel`. |

## Implementation Phases

### Phase 1 — Table-style profile UI (uses existing data)

**Goal**: Land the new layout end-to-end on top of today's per-plugin and
phase data. Timeline section will look sparse (only 2 markers) until Phase 2
populates the rest. Page is fully usable as-is.

1. **Extend `Beast.Packer.UI.Main` with profile-view state**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Update the `---@class` annotation to add:
     ```
     ---@field profile_sort? "total"|"packadd"|"config"|"name"|"chrono"
     ---@field profile_filter_ms? number
     ---@field profile_group_by_reason? boolean
     ```
   - Update the `MainView:extend(...)` constructor to accept and default
     these (`"total"`, `0`, `false`).
   - Why: Sort/filter/group state must persist across re-renders within an
     open UI session. Storing on the View subclass matches `sort_mode` and
     `view_mode` precedent.
   - Depends on: None
   - Risk: Low — additive

2. **Add `F` and `G` actions to UI config**
   (File: `lua/beast/libs/packer/config.lua`)
   - Action: Append two entries to `defaults.ui.actions`:
     ```lua
     { keys = { "F" }, label = "Filter", on_press = "filter_cycle",
       key_hl = "DiagnosticHint", label_hl = "Comment" },
     { keys = { "G" }, label = "Group",  on_press = "group_toggle",
       key_hl = "DiagnosticHint", label_hl = "Comment" },
     ```
   - Why: Config-driven actions keep the keybinding model uniform with `S`,
     `P`, `?`, `q`.
   - Depends on: Step 1
   - Risk: Low

3. **Implement the three new action handlers**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Add `_actions_handler.filter_cycle` (cycles
     `0 → 1 → 5 → 10 → 50 → 0`) and `_actions_handler.group_toggle` (flips
     `profile_group_by_reason`). Modify `_actions_handler.sort` to cycle
     5-way only when `view_mode == "profile"`; otherwise keep
     today's `name <-> time` toggle for the main view.
   - Why: One state-mutator per action, calls `render_state()`. Same idiom
     as today's handlers.
   - Depends on: Steps 1, 2
   - Risk: Low

4. **Add highlight groups for the new UI elements**
   (File: `lua/beast/libs/packer/highlights.lua`)
   - Action: Define `BeastPackerTableHeader`, `BeastPackerBar`,
     `BeastPackerBarDim`, `BeastPackerSectionDivider`, `BeastPackerCheckpoint`,
     `BeastPackerSummaryLabel`. Link to existing palette tokens (e.g.
     `BeastPackerComment` for muted, `DiagnosticInfo` for accent).
   - Why: `apply_segments` consumes `{ text, hl }`. Without these groups the
     new sections render unstyled.
   - Depends on: None
   - Risk: Low

5. **Write helper: render a section divider**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Local `function render_divider(title, right_text)` returning a
     `Beast.Packer.UI.Segment[]` line shaped like `─── TITLE ──── right ─`,
     padded to window width.
   - Why: Reused 4 times in the new layout (timeline / plugins / not-loaded /
     groups). Extract to keep the renderer DRY.
   - Depends on: Step 4
   - Risk: Low

6. **Write helper: render a bar**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Local `function render_bar(value, max, width)` returning a
     20-char string using `█▉▊▋▌▍▎▏░` for sub-cell precision. Returns
     segments tagged `BeastPackerBar` (filled) and `BeastPackerBarDim`
     (empty).
   - Why: Reused for timeline cumulative bar and per-plugin `%` column.
   - Depends on: Step 4
   - Risk: Low

7. **Write helper: render the timeline section**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Local `function render_timeline(profile_data)` produces:
     - Section divider
     - Header row: `MARK / DELTA / CUMUL / BAR`
     - One row per known phase or marker, sorted by `at_ms` if available
       (Phase 2) or by name (Phase 1 fallback).
     - Phase 1 input: only `pack_add` and `early_cs` from `profile.phases`.
       Render them as if they were checkpoints at unknown `at_ms` (use
       column `—` for cumulative); cumulative becomes real in Phase 2.
   - Why: Section is forward-compatible — fills in automatically as Phase 2
     adds markers.
   - Depends on: Steps 5, 6
   - Risk: Medium — column alignment is tricky; use `string.format` widths
     fixed to terminal width minus the legend column.

8. **Write helper: render the plugins table**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Local `function render_plugins_table(main, profiles_list, total_ms)`:
     - Header row: `# / NAME / TOTAL / PACKADD / INIT / CONFIG / % / REASON`.
     - One row per plugin, applying `main.profile_filter_ms` skip and
       `main.profile_sort` ordering (with `total` as default).
     - `%` column is `(plugin.total_ms / total_ms) * 100` with a 5-cell bar.
     - `REASON` cell uses the icons defined in `config.ui.icons` (e.g.
       `eager`, `󰆧 module`, `󰒲 manual`).
     - `INIT` column shows `0.00` for Phase 1 (no separate init data yet).
     - Footer row: `Σ / N plugins / column sums / 100%`.
   - Why: This is the centerpiece of the new layout.
   - Depends on: Steps 5, 6
   - Risk: Medium — alignment + sort comparator + filter must compose cleanly.

9. **Write helper: render the not-loaded table**
   (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Local `function render_not_loaded_table(specs, installed_set)`:
     - Section divider with count.
     - Header row: `# / NAME / STATE / TRIGGER`.
     - State = `installed` if `installed_set[name]` else `not installed`.
     - Trigger = first declared lazy trigger (`event` / `cmd` / `keys` /
       `module` / `filetype` / `path`) or `manual`.
   - Why: Audit signal — "I declared this plugin but it's never loaded;
     should it be removed?"
   - Depends on: Step 5
   - Risk: Low

10. **Write helper: render groups by reason**
    (File: `lua/beast/libs/packer/ui.lua`)
    - Action: Local `function render_grouped_plugins(main, profiles_list, total_ms)`:
      - Bucket plugins into `eager`, `lazy:event`, `lazy:cmd`, `lazy:keys`,
        `lazy:module`, `lazy:filetype`, `lazy:path`, `dependency`, `manual`.
      - Each non-empty bucket gets its own divider + table.
      - Empty buckets render only as a one-line collapsed header
        (`▶ DEPENDENCY  0 plugins`) — no table.
    - Why: Lazy-style grouping when `G` is on. Matches the mockup.
    - Depends on: Step 8
    - Risk: Low — pure data partitioning before delegating to the existing
      table renderer.

11. **Replace `Main._render_profile` with the new orchestrator**
    (File: `lua/beast/libs/packer/ui.lua`)
    - Action: Replace the entire body of `Main._render_profile(main)`:
      ```lua
      function Main._render_profile(main)
          if not main:is_valid() then return end
          local lines = {}
          render_summary_into(main, lines)            -- summary header
          render_timeline_into(main, lines)
          if main.profile_group_by_reason then
              render_grouped_plugins_into(main, lines)
          else
              render_plugins_table_into(main, lines)
          end
          render_not_loaded_table_into(main, lines)
          apply_segments(main, lines)
      end
      ```
    - Why: Glue. All the work is in the helpers from Steps 5–10.
    - Depends on: Steps 5–10
    - Risk: Low — the orchestrator is a thin shim.

12. **Verify Phase 1 end-to-end**
    - Action: Open the packer UI, press `P` to enter profile view. Press
      `S`/`F`/`G` and confirm each cycles state. Confirm `?, H, q, <Esc>`
      still work (no regression on existing actions).
    - Why: Manual smoke before declaring Phase 1 done.
    - Depends on: Steps 1–11
    - Risk: Low

### Phase 2 — Real measurements behind the timeline

**Goal**: Populate the timeline section with real `setup_start`,
`setup_done`, `VimEnter`, `UIEnter` markers and split `init_ms` from
`config_ms`.

13. **Add `Beast.Packer.Marker` type and `markers` table to lib-internal profile**
    (File: `lua/beast/libs/packer/profile.lua`)
    - Action: Add:
      ```lua
      ---@class Beast.Packer.Marker
      ---@field at_ms number   ms since setup_start
      ---@field ts    integer  hrtime() ns at capture time

      local markers = {} ---@type table<string, Beast.Packer.Marker>
      ```
    - Add `methods.set_marker(name)` that records `vim.uv.hrtime()` and
      computes `at_ms` relative to `markers.setup_start.ts` (if absent,
      `at_ms = 0` and the marker becomes the anchor).
    - Expose `markers` via the metatable `__index` (alongside `phases`).
    - Why: Markers are different from phases (timestamps, not durations).
      Separate map keeps semantics clean.
    - Depends on: None
    - Risk: Low — additive

14. **Capture `setup_start` and `setup_done` markers in `M.setup`**
    (File: `lua/beast/libs/packer/init.lua`)
    - Action: First line of `M.setup` after `config.setup(opts)`:
      `profile.set_marker("setup_start")`. Last line of `M.setup` (after the
      module-loader install): `profile.set_marker("setup_done")`.
    - Why: Anchors the timeline. `setup_done.at_ms` is the headline number.
    - Depends on: Step 13
    - Risk: Low

15. **Capture `VimEnter` and `UIEnter` markers via autocmds**
    (File: `lua/beast/libs/packer/init.lua`)
    - Action: Inside `M.setup`, register two `once = true` autocmds:
      ```lua
      vim.api.nvim_create_autocmd("VimEnter", {
          once = true,
          callback = function() profile.set_marker("VimEnter") end,
      })
      vim.api.nvim_create_autocmd("UIEnter", {
          once = true,
          callback = function() profile.set_marker("UIEnter") end,
      })
      ```
    - Why: These are the canonical post-setup checkpoints. Lazy uses them
      for the same reason.
    - Caveat: Headless mode never fires `UIEnter` — that marker will be
      absent. Timeline rendering must tolerate missing markers (already
      designed in Phase 1 Step 7).
    - Depends on: Step 14
    - Risk: Low

16. **Split `init_ms` from `config_ms` in `LoadProfile`**
    (File: `lua/beast/libs/packer/profile.lua`)
    - Action:
      - Update `Beast.Packer.LoadProfile` to add `init_ms` field.
      - In `methods.add_time`, accept `field == "init_ms"` and update
        `total_ms` formula: `total_ms = packadd_ms + init_ms + config_ms`.
      - In `methods.measure`, accept `field == "init_ms"` (already routes
        through `add_time`).
    - Why: Today the Step 2 init loop (`profile.measure(spec.name, "config_ms",
      spec.init)`) lumps init time into config time. The UI table has a
      separate column for init; it can only be honest if the data is split.
    - Depends on: None (independent of Steps 13–15)
    - Risk: Low

17. **Switch Step 2 init loop to record `init_ms`**
    (File: `lua/beast/libs/packer/init.lua`)
    - Action: Change line ~223 from `profile.measure(spec.name, "config_ms", spec.init)`
      to `profile.measure(spec.name, "init_ms", spec.init)`.
    - Why: Closes the bug introduced in Step 16.
    - Depends on: Step 16
    - Risk: Low

18. **Audit `state.load` for stray `config_ms` of init code**
    (File: `lua/beast/libs/packer/state.lua`)
    - Action: Review `state.load`. Confirm `config_ms` is only recorded for
      `spec.config`, never `spec.init`. Per the current code, init is only
      called from `M.setup` Step 2 — but verify.
    - Why: Defensive — if an unknown caller passes init through `state.load`,
      it silently goes into `config_ms`.
    - Depends on: Step 17
    - Risk: Low — likely a no-op finding.

19. **Surface `setup_total_ms` in the Summary header**
    (File: `lua/beast/libs/packer/ui.lua`)
    - Action: In `render_summary_into`, read
      `profile.markers.setup_done.at_ms` (or fallback to
      `profile["packer.setup"].self` if `beast.profile` is recording, else
      `n/a`). Show as the top line of the Summary section.
    - Why: Headline number for the page. Lazy puts this prominently at the
      top.
    - Depends on: Step 14
    - Risk: Low

20. **Verify Phase 2 end-to-end**
    - Action: Open packer UI, profile view. Confirm timeline shows 4
      ordered markers with realistic `at_ms` values (in normal nvim) and 3
      markers in headless mode (no `UIEnter`). Confirm INIT column is
      non-zero for plugins that have an `init` function. Confirm summary
      header shows `setup_total_ms`. Re-run 10× cold-start bench — mean
      must stay within ±15% of the Phase 1 baseline.
    - Why: Manual smoke + regression check.
    - Depends on: Steps 13–19
    - Risk: Low

## Testing Strategy

- **Unit tests**: `tests/` is still empty. Adding tests for this UI is out
  of scope; standing process gap remains.
- **Bench**: No new bench script. The startup bench from
  `health-config.md` is sufficient — Phase 1 must not regress, Phase 2 must
  not regress beyond the cost of 4 extra `vim.uv.hrtime()` calls + 2 extra
  autocmd registrations (sub-microsecond each).
- **Manual verification**:
  - Phase 1: open UI → press `P` → see new table layout. Press `S` 5×, `F`
    5×, `G` 1×, confirm each visibly cycles. Press `q`, reopen, confirm
    state did not persist (per spec — out of scope to persist).
  - Phase 2 (real `nvim`):
    ```bash
    NVIM_APPNAME=BeastVim nvim \
      -c 'lua require("beast.libs.packer.profile").markers' \
      -c 'lua print(vim.inspect(require("beast.libs.packer.profile").markers))' \
      -c 'qa!'
    ```
    Expect 4 markers populated.
  - Phase 2 (headless): expect 3 markers (`UIEnter` absent — should not throw).

## Risks & Mitigations

- **Risk**: Column alignment breaks on narrow windows. → **Mitigation**: The
  packer UI window has fixed dimensions (`config.ui.width = 0.7`,
  `config.ui.height = 0.7` — typically 100+ chars wide on a 1920×1080
  terminal). If width < 80, fall back to a compact form (drop `INIT` and
  `%` columns). Detect via `vim.api.nvim_win_get_width(win)` in the
  renderer.
- **Risk**: Highlight groups link to palette tokens that don't exist on a
  fresh install (before colorscheme loads). → **Mitigation**: Use `default`
  in `nvim_set_hl` so user/colorscheme overrides win, and link to
  `Comment` / `DiagnosticInfo` etc. which are guaranteed present.
- **Risk**: `setup_start` marker is captured but `setup_done` never runs
  because of an unhandled error mid-setup. → **Mitigation**: `setup_done` is
  the last line of `M.setup` — if setup fails, `setup_done` is absent. The
  timeline renderer must handle absent markers (specified in Phase 1 Step 7).
- **Risk**: Persisting filter/group state across UI close+reopen is
  out-of-scope, but a user might expect it. → **Mitigation**: Documented
  in *Out of scope*. If users complain, a future spec adds it via a small
  shim in `state_data` (which already survives close/reopen).
- **Risk**: 5-way sort cycle is harder to discover than a button per sort.
  → **Mitigation**: The Help page (`?`) gets a new line documenting the
  cycle order. Sort indicator (`▼` next to current sort key in the header
  row) is rendered on every redraw.

## Success Criteria

### Phase 1 — UI rebuild

- [ ] `:lua require("beast.libs.packer").open(); vim.cmd("normal P")` opens
      the new profile page.
- [ ] Timeline section shows at least the `early_cs` and `pack_add`
      checkpoints (from existing data).
- [ ] Plugins table renders with header row + sum footer + correctly aligned
      columns at default UI width.
- [ ] `S` cycles `total → packadd → config → name → chrono → total` —
      visible by re-ordering of the rows.
- [ ] `F` cycles `0 → 1 → 5 → 10 → 50 → 0` — visible by rows hiding/showing.
- [ ] `G` toggles grouped layout — visible by section dividers per reason.
- [ ] Not-loaded section shows installed status correctly.
- [ ] `?, H` Help page lists the new keys.
- [ ] No regression in main view (`P` still toggles back).

### Phase 2 — Real measurements

- [ ] `profile.markers.setup_start.at_ms == 0`.
- [ ] `profile.markers.setup_done.at_ms > 0` and equals
      `profile["packer.setup"].self` ± 1 ms (cross-check against
      `beast.profile`).
- [ ] `profile.markers.VimEnter` is populated in interactive mode.
- [ ] `profile.markers.UIEnter` is **absent** in `--headless` mode without
      throwing — timeline section gracefully renders 3 markers.
- [ ] `profiles[<plugin-with-init>].init_ms > 0`,
      `profiles[<plugin-with-init>].config_ms` reflects only `spec.config`.
- [ ] `total_ms == packadd_ms + init_ms + config_ms` for every plugin.
- [ ] Summary header shows `setup_total_ms`.
- [ ] 10× cold-start bench mean within ±15% of Phase 1 baseline.

### Wrap-up

- [ ] Codemap (`docs/CODEMAP/libraries.md` § packer) updated to mention
      `markers`, `init_ms`, table-style profile UI.
- [ ] Spec marked complete with a `## Completed` block.
