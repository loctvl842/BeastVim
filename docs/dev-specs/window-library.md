# Dev Spec: Beast Window (Autowidth + Maximize) Library

## Summary

A native window-management library at `lua/beast/libs/window/` that ports the two
features I rely on from `anuvyklack/windows.nvim`:

1. **Autowidth** — the focused split is auto-grown to fit its content (`textwidth + winwidth`,
   filetype-aware), while sibling splits shrink toward `winminwidth`.
2. **Maximize / restore** — `:WindowsMaximize` equivalent that snapshots the current
   layout, grows the focused window to fill its row and column, and restores on the
   second invocation (or when focus leaves a non-floating window).

Approach mirrors `windows.nvim`'s architecture (`Frame` layout tree from
`vim.fn.winlayout()` + per-window resize data) but drops both upstream dependencies
(`middleclass`, `animation.nvim`). Plain Lua tables replace `middleclass`; the
existing `lua/beast/libs/animate.lua` is extended with a generic `M.tween(duration,
on_frame, on_done, opts)` primitive so split-resize animation reuses the same easing
and frame-loop core as the float animator.

**Public API:**

```lua
local window = require("beast.libs.window")
window.setup({
  autowidth = {
    enable = true,
    winwidth = 5,                          -- padding beyond textwidth (or fraction)
    filetype = { help = 2, qf = 0 },       -- per-ft override
  },
  animation = {
    enable   = true,
    duration = 150,                        -- ms
    easing   = "ease_in_out",              -- linear | ease_in | ease_out | ease_in_out
  },
  ignore = {
    buftype  = { "quickfix", "nofile", "prompt" },
    filetype = { "beast-explorer", "beast-finder-list", "beast-key", "beast-toast" },
  },
})
window.maximize()                -- toggle full-screen current window
window.maximize_vertically()     -- :res only
window.maximize_horizontally()   -- :vert res only
window.equalize()                -- <C-w>=
window.enable() / disable() / toggle()  -- autowidth toggles
```

## Requirements

### Functional

- **Autowidth**: on `BufWinEnter`, `WinEnter`, `WinNew`, `VimResized`, recompute
  widths so the focused window gets its "wanted width" (filetype-aware):
  - `wanted = textwidth + cfg.winwidth` (with `textwidth=0` defaulting to 80).
  - `0 < w < 1` → `floor(w * vim.o.columns)`; `1 < w < 2` → `floor(w * textwidth)`; else `textwidth + w`.
  - Per-filetype overrides (`autowidth.filetype.help = 2`).
- **Maximize**: snapshot every window's `{width, height}` into per-tab cache; grow
  current leaf to fill row & column. Second call restores from cache.
- **Maximize axis variants**: `maximize_vertically` and `maximize_horizontally` toggle
  one axis only (cache is two-sided so axes are independent).
- **Equalize**: `<C-w>=` equivalent, animated.
- **Guard autocmd while maximized**: `WinEnter` on another non-floating window
  triggers restore-or-equalize (matches windows.nvim). `WinClosed` invalidates cache.
- **Skip rules** (both autowidth and maximize): floating windows, `winfixwidth`/
  `winfixheight` for the relevant axis, command-line window (`win_gettype() == 'command'`),
  configured `buftype`/`filetype` in `ignore`.
- **Animation** (opt-in via `animation.enable`): tween width/height from current
  values to targets over `duration` ms using the chosen easing. Single-flight: a new
  request mid-animation rebases (current widths become new initials) instead of
  aborting visually.
- **Cursor anchoring**: during animation, preserve the cursor's visual column even
  if the window narrows below it — temporarily set `virtualedit=all`, feed `<col>|`
  via `nvim_feedkeys`, restore on finish (port the windows.nvim trick).
- **Public toggles**: `enable()`, `disable()`, `toggle()` (autowidth only — maximize
  is always available). Buffer-local opt-out: `vim.b[buf].beast_window_disabled = true`.
  Global opt-out: `vim.g.beast_window_disabled = true`.
- **User commands**: `:BeastWindowMaximize`, `:BeastWindowMaximizeVertically`,
  `:BeastWindowMaximizeHorizontally`, `:BeastWindowEqualize`,
  `:BeastWindowEnableAutowidth`, `:BeastWindowDisableAutowidth`,
  `:BeastWindowToggleAutowidth`.

### Non-Functional

- Zero third-party deps. Use `vim.fn.winlayout`, `vim.api.nvim_win_*`, `vim.uv.new_timer`.
- One generic tween primitive shared with the float animator (no duplicate frame loop).
- Frame tree rebuilt on each request (cheap — sub-µs even for deep splits; matches
  windows.nvim behavior).
- Multi-tab safe: cache keyed by `tabpage_id`; maximize state does not leak across tabs.
- Lazy-loaded via `packer.lazy()` on `WinNew` event and `<leader>z` keymap.

### Out of Scope

- Height-aware autowidth (windows.nvim doesn't really do this either — only width
  is content-driven; height stays equal).
- Per-window aspect-ratio configs beyond the existing `filetype` map.
- Replacing or extending `lua/beast/libs/animate.lua`'s float surface (only adding
  `M.tween`; existing `M.run` keeps working unchanged).
- Saving/restoring layouts across sessions.
- Highlights — this lib has no UI surface, so no `highlights.lua`.

## Research

### Repo Search

- Searched for: `winlayout`, `nvim_win_set_width`, `nvim_win_set_height`,
  `winwidth`, `winminwidth`, `WinNew`, `BufWinEnter` in `lua/beast/`.
- Found:
  - `lua/beast/libs/animate.lua` — frame-loop animator for **float** windows via
    `nvim_win_set_config()` (`M.run(win, from, to, duration, on_done, opts)`). Has
    the timing core (`FPS=30`, `defer_fn(step, FRAME_MS)`, ease tables) that we want
    to reuse, but the per-frame action is hard-coded to floats. **Extract first**:
    pull a generic `M.tween(duration, on_frame, on_done, opts)` primitive out of
    `M.run`, then rewrite `M.run` as a thin wrapper.
  - `lua/beast/libs/scroll/init.lua` — uses `vim.uv.new_timer()` for its own tween
    loop with the same easings table (`linear`, `ease_in`, `ease_out`, `ease_in_out`).
    Confirms the easing vocabulary and timer pattern used elsewhere in the project.
    **Not reusable directly** (scroll's loop knows about `topline`/`<C-e>`/`<C-y>`).
  - `lua/beast/option.lua` already has the old config's `vim.o.winwidth = 30` /
    `winminwidth = 30` / `equalalways = true` candidates — confirm and move there
    if not present.
  - No existing window-resize/layout code. Greenfield lib.
- Reuse opportunity: **Extract first** — `animate.tween` becomes Phase 1.

### Package Search

- Searched: Neovim core for split-resize animation; `vim.api.nvim_win_set_width/height`,
  `vim.fn.winlayout`, `vim.fn.win_gettype`, `vim.fn.winsaveview`, `vim.fn.getwininfo`.
- Found: All primitives needed are in core. `vim.fn.winlayout()` returns the
  recursive `{type, children|winid}` tree; `nvim_win_set_width/height` apply per-window
  values; `vim.fn.getwininfo()[1].textoff` gives the gutter offset for cursor math.
- Looked at `anuvyklack/windows.nvim` source (`~/.local/share/nvim/lazy/windows.nvim`)
  as the reference implementation — port the `Frame` layout algorithm (1063 LOC →
  expect ~400 LOC after dropping `middleclass` and merging trivial method wrappers).
- Decision: **Use native + port** — no plugin pulled in; port the layout math from
  windows.nvim (permissive MIT), drop both its dependencies, reuse the extracted
  `animate.tween` for the timing loop.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/animate.lua` | Modify | Extract `M.tween(duration, on_frame, on_done, opts)`; rewrite `M.run` as wrapper |
| `lua/beast/libs/window/init.lua` | Create | Public API (`setup`, `maximize*`, `equalize`, `enable/disable/toggle`), state owner, user commands |
| `lua/beast/libs/window/config.lua` | Create | Readonly config singleton with `setup(opts)` merge (autowidth, animation, ignore) |
| `lua/beast/libs/window/state.lua` | Create | Per-tab cache (cursor_virtcol, maximized snapshot), augroup handle |
| `lua/beast/libs/window/frame.lua` | Create | Layout tree from `vim.fn.winlayout()` — plain Lua table, methods on metatable |
| `lua/beast/libs/window/layout.lua` | Create | `autowidth(curwin)`, `maximize_win(win, do_w, do_h)`, `equalize_wins(do_w, do_h)` — returns `WinResizeData[]` |
| `lua/beast/libs/window/resize.lua` | Create | `apply(data)` and `merge(width_data, height_data)` |
| `lua/beast/libs/window/animate.lua` | Create | Split-resize tween built on `animate.tween`; cursor-anchor virtualedit dance |
| `lua/beast/libs/window/autocmds.lua` | Create | Register/teardown autocmds (BufWinEnter/WinEnter/WinNew/VimResized/WinClosed/TabLeave) |
| `lua/beast/libs/window/health.lua` | Create | `:checkhealth beast.libs.window` — config, augroup, frame walk |
| `lua/beast/init.lua` | Modify | `packer.lazy("beast.libs.window", { event = "WinNew", keys = {...} })` |
| `lua/beast/option.lua` | Modify | Ensure `winwidth = 30`, `winminwidth = 30`, `equalalways = true` (the old `init` callback) |
| `docs/CODEMAPS/libraries.md` | Modify | Add new lib section after `## scroll` |
| `docs/CODEMAPS/INDEX.md` | Modify | Bump `Libraries: 16` → `17`, refresh date |

## Implementation Phases

### Phase 1: Extract `animate.tween` Primitive — Unblock both float and split animation

1. **Refactor `animate.lua`** (File: `lua/beast/libs/animate.lua`)
   - Action: Add `M.tween(duration, on_frame, on_done, opts)` that runs the existing
     frame loop (`vim.defer_fn(step, FRAME_MS)`, `total_frames = math.max(1, floor(duration/FRAME_MS))`)
     and calls `on_frame(t_eased, t_raw)` each tick. Accept `opts.ease` as either a
     function or a string key (`linear|ease_in|ease_out|ease_in_out`) — add the
     `ease_in_out` entry so it matches the `scroll` lib's vocabulary.
   - Rewrite `M.run(win, from, to, duration, on_done, opts)` as a thin wrapper that
     computes its per-frame `nvim_win_set_config` call inside an `on_frame` closure
     passed to `M.tween`. Preserve the existing `blend_delay` / split ease semantics
     for `pos` / `size` / `blend` axes.
   - Why: Single timing core; consumers add their own per-frame action. Required by
     `beast.libs.window/animate.lua` and keeps the codebase DRY.
   - Depends on: None.
   - Risk: Medium — `M.run` is used by `notify/ui.lua` and `toast/ui.lua`; behavior
     must be byte-for-byte equivalent. Mitigation: keep the wrapper's public
     signature identical; manually verify a notification fade still looks right.

2. **Manual smoke test** (no file change)
   - Action: `:lua vim.notify("hi", vim.log.levels.INFO)` and watch fade-out — confirm
     no regression in slide-in or alpha animation. Open the toast stack from any
     existing trigger and confirm same.
   - Depends on: Step 1.
   - Risk: Low.

### Phase 2: Frame Layout Engine — The math, no autocmds yet

1. **Create `frame.lua`** (File: `lua/beast/libs/window/frame.lua`)
   - Action: Port `windows.nvim/lua/windows/lib/frame.lua` to a plain Lua table
     with metatable methods. Required surface: `Frame.new(layout?, id?, parent?)`,
     `:autowidth(curwinLeaf)`, `:maximize_window(leaf, do_w, do_h)`,
     `:equalize_windows(do_w, do_h)`, `:get_data_for_width_resizing()`,
     `:get_data_for_height_resizing()`, `:find_window(win)`, `:get_min_width(tarwin, tarwin_width)`,
     `:get_min_height(tarwin, tarwin_height)`, internal `_mark_fixed_width/height`,
     `get_longest_row*` / `get_longest_column*`.
   - Drop `middleclass`. Drop the in-lib `Window` wrapper — use bare `winid` + helper
     functions (`win.lua` module with `get_wanted_width(winid, cfg)`, `is_floating(winid)`,
     `is_ignored(winid, cfg)`, `get_text_offset(winid)`). This avoids re-implementing OO.
   - Why: Layout decisions (which window grows, which shrinks, by how much) are the
     non-trivial core. Keep separate from autocmds so it is unit-testable.
   - Depends on: None.
   - Risk: High — 1063 LOC of recursive layout math. Mitigation: port file-by-file
     with the original open in a buffer; add a `tests/window/frame_spec.lua` that
     reproduces 3 hand-built layouts (single split, nested col-in-row, deep tree)
     and asserts the expected `WinResizeData[]` for each.

2. **Create `layout.lua`** (File: `lua/beast/libs/window/layout.lua`)
   - Action: Port `windows.nvim/lua/windows/calculate-layout.lua` (88 LOC). Three
     functions: `autowidth(curwin)`, `maximize_win(win, do_w, do_h)`,
     `equalize_wins(do_w, do_h)`. Returns `WinResizeData[]` lists.
   - Why: Thin orchestrator around `Frame`. Keep separate so `init.lua` does not
     reach into `frame.lua` directly.
   - Depends on: Step 1.
   - Risk: Low.

3. **Create `resize.lua`** (File: `lua/beast/libs/window/resize.lua`)
   - Action: Port `resize-windows.lua` — `apply(data)` (per-entry
     `nvim_win_set_width/height` with `pcall`) and `merge(width_data, height_data)`.
   - Why: Tiny, but used by both immediate and animated paths.
   - Depends on: None.
   - Risk: Low.

### Phase 3: Public API + State + Commands — Shippable without animation or autowidth

1. **Create `config.lua`** (File: `lua/beast/libs/window/config.lua`)
   - Action: Readonly metatable pattern matching `scroll/config.lua`. Defaults per
     the API table above. Single `setup(opts)` merge converting `ignore.buftype` /
     `ignore.filetype` arrays into sets.
   - Depends on: None.
   - Risk: Low.

2. **Create `state.lua`** (File: `lua/beast/libs/window/state.lua`)
   - Action: Per-tab `{maximized = {width=[], height=[]}, cursor_virtcol = {}}` table,
     keyed by `nvim_get_current_tabpage()`. Augroup handle owned here.
   - Depends on: None.
   - Risk: Low.

3. **Create `init.lua`** (File: `lua/beast/libs/window/init.lua`)
   - Action: `setup(opts)`, public `maximize/maximize_vertically/maximize_horizontally/equalize/enable/disable/toggle`,
     register user commands. Maximize logic: snapshot widths/heights into
     `state.maximized[tab]` BEFORE applying new sizes; if already maximized, restore
     from snapshot and clear cache. Apply via `resize.apply()` (animation hook added in Phase 4).
   - Why: Lands the maximize feature behind `<leader>z` immediately without
     animation — shippable Phase 3.
   - Depends on: Phase 2.
   - Risk: Medium — the WinEnter guard autocmd that auto-restores when leaving a
     maximized window is fiddly. Mitigation: copy windows.nvim's pattern verbatim
     (`setup_autocmds()` in `commands.lua`), clear via `nvim_clear_autocmds({group=})`.

### Phase 4: Autowidth Engine — The headline feature

1. **Create `autocmds.lua`** (File: `lua/beast/libs/window/autocmds.lua`)
   - Action: Port `windows.nvim/lua/windows/autowidth.lua`. Hook BufWinEnter, WinEnter,
     WinNew, VimResized, WinLeave (for cursor_virtcol cache), WinClosed, TabLeave.
     Debounce identical via `M.resizing_request` flag + `vim.defer_fn(setup_layout, 10)`.
     Respect `vim.b.beast_window_disabled` and `vim.g.beast_window_disabled`.
   - Why: This is the feature.
   - Depends on: Phase 3.
   - Risk: High — autocmd recursion is the classic foot-gun in window resize code.
     Mitigation: single-flight via `resizing_request` flag; never call `nvim_win_set_width`
     inside an autocmd that itself fires `BufWinEnter` (windows.nvim's deferred
     scheduling pattern handles this — port unchanged).

2. **Wire `enable/disable/toggle`** (File: `lua/beast/libs/window/init.lua`)
   - Action: `enable()` calls `autocmds.register()`; `disable()` clears the augroup;
     `toggle()` flips. Maximize-guard autocmd lives in its own sub-group so it
     can be cleared independently.
   - Depends on: Step 1.
   - Risk: Low.

### Phase 5: Animation — Polish

1. **Create `animate.lua`** (File: `lua/beast/libs/window/animate.lua`)
   - Action: `run(winsdata, on_done)` that captures `{win, w0, h0, dw, dh}` snapshots,
     temporarily sets `virtualedit=all` on `curwin` if needed for cursor anchoring,
     then calls `animate.tween(cfg.animation.duration, on_frame, finish, {ease=cfg.easing})`.
     On each frame: `nvim_win_set_width(win, w0 + round(t*dw))` per entry, feed
     `<col>|` to keep cursor visible if `cursor_virtcol` was cached. On finish:
     restore `virtualedit`, clear snapshot.
   - Single-flight: track `running` flag + active snapshot; new `run()` calls while
     running rebase initials to current sizes and replace target deltas instead of
     hard-cancelling.
   - Depends on: Phase 1 (`animate.tween`), Phase 3.
   - Risk: Medium — cursor anchoring during shrink phases is the trickiest part.
     Mitigation: port windows.nvim's exact `nvim_feedkeys(col..'|', 'nx', false)`
     dance from `resize-windows-animated.lua`.

2. **Wire animation in `init.lua` and `autocmds.lua`** (Files: same)
   - Action: Replace direct `resize.apply()` calls with: `if cfg.animation.enable
     then animate.run(data, finish) else resize.apply(data) end`.
   - Depends on: Step 1.
   - Risk: Low.

### Phase 6: Health + Integration + Codemap — Ship

1. **Create `health.lua`** (File: `lua/beast/libs/window/health.lua`)
   - Action: `M.check()` reports: config dump, autowidth-enabled flag, augroup id,
     active tab's maximized cache state, frame tree summary for current tab
     (count by type). Match the depth of `git/health.lua` or `statuscolumn/health.lua`.
   - Depends on: All earlier phases.
   - Risk: Low.

2. **Wire into setup** (File: `lua/beast/init.lua`)
   - Action: Add `packer.lazy("beast.libs.window", { event = "WinNew", defer = true,
     keys = { {"<leader>z", ...}, {"<leader>z=", ...} }, setup = function(w)
     w.setup(cfg.window or {}) end })`. Add `window?: Beast.Window.Config` to
     `Beast.Config` annotation.
   - Depends on: Phase 5.
   - Risk: Low.

3. **Move `init` callback options into `option.lua`** (File: `lua/beast/option.lua`)
   - Action: Add `vim.o.winwidth = 30`, `vim.o.winminwidth = 30`, `vim.o.equalalways = true`
     if not already present.
   - Depends on: None.
   - Risk: Low — these are inert without autowidth, so safe to set eagerly.

4. **Update codemaps** (Files: `docs/CODEMAPS/libraries.md`, `docs/CODEMAPS/INDEX.md`)
   - Action: Append `## window — Window Layout (autowidth + maximize)` section to
     `libraries.md`. Bump `Libraries: 16 (...)` to `17 (..., window)` in `INDEX.md`.
     Update generated dates.
   - Depends on: All earlier phases.
   - Risk: Low.

## Testing Strategy

### Unit tests

- `tests/window/frame_spec.lua` (new): three hand-built `vim.fn.winlayout()`-shaped
  tables fed into `Frame.new` → assert `:get_data_for_width_resizing()` produces the
  expected list. Cases: (a) single vertical split, (b) nested `col` inside `row`,
  (c) three-deep tree mixing col/row.
- `tests/window/layout_spec.lua` (new): drive `layout.autowidth(curwin)` and
  `layout.maximize_win(curwin, true, true)` against the same fixtures.
- `tests/window/animate_spec.lua` (new): mock the timer, assert that `animate.tween`
  produces N frames with t monotonically increasing 0→1 and calls `on_done` exactly
  once.
- Note: `tests/` currently exists; check `tests/init.lua` or test runner for the
  expected pattern (likely `mini.test` or similar — match what `tests/key/` or
  `tests/explorer/` use).

### Bench

- Not a hot path — autowidth fires on `WinEnter`, max a few times per second under
  normal use. Skip a dedicated bench script.

### Manual verification

1. Open `nvim init.lua`, run `:vsplit DEVELOPMENT.md` — the focused split should
   animate to ~80 cols width (textwidth=80 + winwidth=5 = 85 → grows toward fit).
   Switch focus with `<C-w>w` — width should swap.
2. Hit `<leader>z` — current split should fill the editor. Hit `<leader>z` again —
   restore to previous widths.
3. With three vertical splits, hit `<leader>z` on the middle, then `<C-w>w` to focus
   another — auto-restore (or equalize) per the guard autocmd.
4. `:BeastWindowToggleAutowidth` then `<C-w>w` — no resize should happen.
5. Set `vim.b.beast_window_disabled = true` in a buffer, focus it — no resize.
6. `:checkhealth beast.libs.window` — clean output, autogroup id present.

## Risks & Mitigations

- **Risk**: Autocmd recursion / infinite resize loop. → **Mitigation**: port
  windows.nvim's `resizing_request` single-flight flag and `vim.defer_fn(setup_layout, 10)`
  pattern verbatim; gate every autocmd entry on `is_floating()` / `is_ignored()`.
- **Risk**: Conflict with other libs that resize windows (e.g. `explorer` opens a
  fixed-width split). → **Mitigation**: explorer's filetype `beast-explorer` is in
  the default `ignore.filetype` list; verify explorer also sets `winfixwidth` so
  autowidth's "wanted width" calculation skips it (already done in `explorer/ui.lua`).
- **Risk**: `animate.tween` extraction breaks `notify`/`toast` fade. → **Mitigation**:
  keep `M.run`'s signature identical; manual smoke before moving on from Phase 1.
- **Risk**: Cursor jumps to wrong column when the focused window shrinks during
  animation. → **Mitigation**: port the `virtualedit=all` + `nvim_feedkeys(col..'|')`
  trick from `resize-windows-animated.lua`; restore `virtualedit` on finish.
- **Risk**: Frame tree port introduces subtle off-by-one bugs vs upstream. →
  **Mitigation**: unit-test the three fixture layouts in Phase 2 before wiring
  autocmds. If a layout regression appears, diff against
  `~/.local/share/nvim/lazy/windows.nvim/lua/windows/lib/frame.lua`.
- **Risk**: Multi-tab state leakage (maximize on tab 1 affects tab 2). →
  **Mitigation**: key `state.maximized` by `nvim_get_current_tabpage()`; clear on
  `TabClosed`.

## Success Criteria

- [ ] `<leader>z` zooms and un-zooms the current split, with the documented animation.
- [ ] Focusing any window grows it to fit (textwidth-aware), with sibling windows
      visibly shrinking but never below `winminwidth`.
- [ ] `:checkhealth beast.libs.window` is clean (no errors/warnings).
- [ ] `tests/window/*_spec.lua` pass.
- [ ] No regression in `vim.notify`/`Toast` fade animation (Phase 1 refactor safety).
- [ ] Codemaps (`INDEX.md` + `libraries.md`) updated and the date stamp refreshed.
- [ ] Startup time delta within ±2 ms of baseline (lib is `WinNew`-lazy so should
      be ~0).

## ADR Required

This dev spec introduces architectural decisions worth recording once committed:

- **Extracting `animate.tween` as a shared timing primitive** — establishes a new
  shared module surface (alongside `Beast.View`, `Util.colors`, `Palette.get`).
  Future animated libs (e.g. a future `dimmer`, `flash`) should consume `animate.tween`
  rather than rolling their own `defer_fn` loops. Worth an ADR to lock that contract in.
- **Native port of `windows.nvim` instead of vendoring** — mirrors the precedent of
  `scroll` (native port of `snacks.scroll`) and `git` (native vs `gitsigns.nvim`).
  Reinforces the "zero plugin deps for editor-level UX" rule.
