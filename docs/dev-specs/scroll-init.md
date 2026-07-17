---
name: scroll-init
description: "Beast Scroll (Smooth Viewport Scrolling) Library"
generated: 2026-05-28
---

# Dev Spec: Beast Scroll (Smooth Viewport Scrolling) Library

## Summary

A native smooth-scroll library at `lua/beast/libs/scroll/` that animates viewport
(`topline`) transitions when the cursor pushes the window — making held `j`/`k`,
`<C-d>`/`<C-u>`, `gg`/`G`, etc. feel buttery instead of jumping a full redraw at a
time. The approach mirrors `snacks.nvim`'s `snacks.scroll`: hook `WinScrolled`,
snap the window back to its previous view, then step toward the target with
micro `<C-e>`/`<C-y>` commands driven by a `vim.uv` timer. Two animation profiles
(normal + "repeat" within ~100 ms) keep held-key scrolls from queueing up.

This is a brand new library — no equivalent exists in BeastVim today. `smoothscroll`
in `option.lua` only affects how wrapped lines render under `<C-e>`/`<C-y>`; it does
not animate. `libs/animate.lua` animates float window geometry and `winblend`, not
viewport state, so it cannot be reused.

**Public API:**

```lua
local scroll = require("beast.libs.scroll")
scroll.setup({
  animate        = { step_ms = 10, total_ms = 200, easing = "linear" },
  animate_repeat = { delay_ms = 100, step_ms = 5, total_ms = 50, easing = "linear" },
  filter         = function(buf) return vim.bo[buf].buftype ~= "terminal" end,
})
scroll.enable()  -- called by setup() unless { enabled = false }
scroll.disable()
scroll.toggle()
```

## Requirements

### Functional

- Animate viewport (`topline`) changes triggered by cursor movement:
  held `j`/`k` past `scrolloff`, `<C-d>`/`<C-u>`, `H`/`M`/`L`, `gg`/`G`, search jumps,
  `zz`/`zt`/`zb`.
- Per-window animation state — multiple splits animate independently.
- **Repeat profile**: if a new scroll starts within `animate_repeat.delay_ms` of the
  previous one, use the faster profile so holding `j` keeps up with `keyrepeat`
  without backlog.
- Skip animation when:
  - `|delta_topline| ≤ 1` (avoids per-line jitter)
  - Source is mouse wheel (`<ScrollWheelUp/Down>`) — terminals smooth this themselves
  - Buffer is filtered out (default: `buftype == "terminal"`)
  - Macro is recording/executing (`reg_recording()`, `reg_executing()`)
  - `vim.o.paste` is on
  - `scrollbind` is on and the window is not the active one
- During an animation: temporarily set `scrolloff = 0` and `virtualedit = "all"`
  on the target window, restore on stop.
- Reset state on `InsertLeave`, `TextChanged`, `TextChangedI`, edited buffer
  (`changedtick` mismatch), and `CmdlineLeave` from `/`/`?` when `incsearch` is on.
- Clean up state on `WinClosed`.
- Public toggles: `enable()`, `disable()`, `toggle()`. Buffer-local opt-out:
  `vim.b[buf].beast_scroll_disabled = true`. Global opt-out: `vim.g.beast_scroll_disabled = true`.

### Non-Functional

- Single shared `vim.uv` timer per animation (one per window). Stop and free
  on completion/cancel — no zombie timers.
- Hot path (`WinScrolled` callback) must be cheap: state lookup → delta check →
  start timer. No allocations beyond the per-window state on first scroll.
- Follow BeastVim library conventions: state only in `init.lua` module-locals,
  frozen-config metatable (§ *Config Pattern*), lazy autocmd registration on
  `enable()`, `Beast.Scroll.*` type names.
- No external plugins. Use only `vim.api.*`, `vim.fn.*`, `vim.uv.*`, `vim.on_key`.
- Default loaded via `packer.lazy()` on `VimEnter` (deferred).

### Out of Scope

- Animating cursor position separately from viewport (the cursor naturally rides
  the viewport because we drive scroll via `<C-e>`/`<C-y>` with cursor-on-screen).
- Animating horizontal scroll (`<C-h>`-style). Vertical only.
- Mouse-wheel smoothing (terminal handles it).
- A bench script — animation correctness is verified manually; there is no
  hot-path computation worth micro-benchmarking. (`scripts/bench-scroll.lua`
  intentionally omitted.)
- Wiring into `lua/beast/plugins/init.lua` and `lua/beast/init.lua` — owned by user.
- Integration with `Beast.Key.builtin` toggle keymap — separate follow-up.

## Research

### Repo Search

- Searched for: `scroll`, `smoothscroll`, `WinScrolled`, `neoscroll`, `cinnamon`,
  `<C-e>`, `<C-y>`, `animate`, in `lua/beast/**`.
- Found:
  - `lua/beast/option.lua:51` sets `vim.o.smoothscroll = true` — this is the **core
    Neovim 0.10 option** that only affects how wrapped lines render under `<C-e>` /
    `<C-y>`. It does **not** animate. Keep as-is; it composes well with this lib.
  - `lua/beast/libs/animate.lua` — animates `nvim_win_set_config` geometry fields
    (row/col/width/height) and `winblend`. Driven by `vim.defer_fn` at 30 FPS.
    **Not reusable** for scroll: it targets float window config, not `winrestview`
    + `<C-e>`/`<C-y>`. We need a separate, simpler tween loop on `vim.uv.new_timer`.
  - `lua/beast/libs/explorer/autocmds.lua` listens to `WinScrolled` for sticky
    headers — confirms `WinScrolled` is well-understood in the repo; we use the
    same autocmd group convention (`BeastScroll`).
  - `lua/beast/libs/indent/init.lua` — reference pattern for `setup() → ensure_autocmds()
    → augroup` lifecycle.
  - `lua/beast/libs/key/builtin.lua` exists — natural home for a future toggle
    keymap, but explicitly out of scope here.
- Reuse opportunity: **None for the animation engine** — `animate.lua` is the
  wrong shape (geometry, defer_fn, 30 FPS, on_done callback). **Adopt** the
  established lib skeleton (config / state owned in init / lazy autocmds).

### Package Search

- Searched: `snacks.nvim` (`~/.local/share/LazyVim/lazy/snacks.nvim/lua/snacks/scroll.lua`),
  Neovim core APIs.
- Found in `snacks.scroll` (~400 lines, MIT) — the reference implementation:
  - `WinScrolled` hook with per-window state keyed on winid
  - `winrestview` snap-back + animated `<C-e>`/`<C-y>` steps
  - **Two-profile animation** (normal 200 ms, repeat 50 ms within 100 ms) — the
    specific trick that makes held-key scrolling feel buttery
  - `vim.on_key` to detect `<ScrollWheelUp/Down>` and skip
  - `scroll_lines()` helper that accounts for folds + virtual lines via
    `vim.api.nvim_win_text_height`
- Native Neovim primitives we need:
  - `vim.api.nvim_create_autocmd("WinScrolled", ...)` — read `vim.v.event[winid].topline`
    delta per scrolled window
  - `vim.fn.winsaveview()` / `vim.fn.winrestview()` — snap and restore view
  - `vim.api.nvim_win_call(win, fn)` — run normal commands in another window safely
  - `vim.api.nvim_win_text_height(win, { start_row, end_row })` — fold-aware line
    count (Neovim ≥ 0.10)
  - `vim.uv.new_timer()` — frame loop; `vim.schedule_wrap` for the step callback
  - `vim.on_key(...)` — detect mouse-wheel keys
  - `vim.api.nvim_replace_termcodes("<C-e>", true, true, true)` — keycodes for
    `nvim_feedkeys` / `:normal!`
- Decision: **Build** — adopt the design of `snacks.scroll` (well-documented,
  battle-tested), reimplemented as a small native lib using only Neovim APIs.
  No new plugin dependency. Snacks-the-package is not pulled in; we write a
  focused ~250 LOC module that mirrors only the scroll behaviour.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/scroll/config.lua` | Create | Defaults + `setup()` merge; frozen config metatable per § *Config Pattern* |
| `lua/beast/libs/scroll/state.lua` | Create | `Beast.Scroll.State` class — per-window animation state, `:stop()`, `:wo()` option backup/restore, `:valid()` |
| `lua/beast/libs/scroll/init.lua` | Create | Public API: `setup()`, `enable()`, `disable()`, `toggle()`. Owns autocmds, mouse-key detection, and `check(win)` (the hot path). |

No changes to existing files. No new shared module under `lua/beast/util/`.
No bench script (see *Out of Scope*).

## Implementation Phases

### Phase 1: Core Scroll Library — Single-window smooth animation with autocmds

This is the only phase. The lib is small enough (< 300 LOC across 3 files) to
land in one slice. Splitting would create intermediate states that don't work.

1. **Create `config.lua`** (File: `lua/beast/libs/scroll/config.lua`)
   - Action: Define `Beast.Scroll.Config` defaults:
     ```lua
     {
       enabled        = true,
       animate        = { step_ms = 10, total_ms = 200, easing = "linear" },
       animate_repeat = { delay_ms = 100, step_ms = 5, total_ms = 50, easing = "linear" },
       filter         = function(buf) return vim.bo[buf].buftype ~= "terminal" end,
     }
     ```
     Frozen-config metatable matching `statusline/config.lua`. `setup(opts)` deep-merges.
     Easing is a string key resolved against a small `EASINGS = { linear = ..., ease_out = ... }`
     table local to the file; default `"linear"` matches snacks.
   - Why: All other modules read `config.animate.*` inline; no live config.
   - Depends on: None
   - Risk: Low

2. **Create `state.lua`** (File: `lua/beast/libs/scroll/state.lua`)
   - Action: Class `Beast.Scroll.State` (metatable-style, matching `breadcrumb`/`finder` libs):
     - Fields: `win`, `buf`, `view` (last observed `winsaveview`), `current`
       (where the animation currently sits), `target` (where animation is going to),
       `last_ns` (hrtime of last scroll, for repeat detection), `timer`
       (`vim.uv.new_timer()` or nil), `changedtick`, `_wo` (backup of `scrolloff` /
       `virtualedit`).
     - Methods:
       - `State.get(win, filter)` — returns or creates state; returns nil if filtered
         or window invalid.
       - `State:stop()` — `timer:stop():close()`, restore window options via `:wo()`
         with no args.
       - `State:wo(opts?)` — when called with a table, snapshot current `vim.wo[win]`
         values into `_wo` (only first time per key), then apply `opts`. When called
         with no args, restore from `_wo` and clear it. Mirrors snacks pattern but as
         a method.
       - `State:valid()` — `nvim_win_is_valid` + `nvim_buf_is_valid` + buf hasn't
         changed since animation started + still the buffer in this window.
       - `State:update_current()` — refresh `current` from `winsaveview()` (called
         each animation tick + on `CursorMoved`).
   - Why: Encapsulates per-window animation. Keeps `init.lua` small.
   - Depends on: Step 1
   - Risk: Low

3. **Create `init.lua`** (File: `lua/beast/libs/scroll/init.lua`)
   - Action: Module-level locals:
     - `enabled = false`
     - `states: table<integer, Beast.Scroll.State>` keyed by winid
     - `mouse_scrolling = false`
     - `augroup`
     - `SCROLL_DOWN`, `SCROLL_UP` — pre-computed termcodes for `<C-e>` / `<C-y>`
   - Public API:
     - `M.setup(opts)` → `config.setup(opts)`; if `config.enabled`, `M.enable()`.
     - `M.enable()` — sets `enabled = true`, registers autocmds + `vim.on_key`
       (see below). Idempotent.
     - `M.disable()` — clears `enabled`, deletes augroup, stops + clears all states.
     - `M.toggle()` — flip enable/disable.
   - Autocmds (group `BeastScroll`, registered in `enable()`):
     - `WinScrolled` → iterate `vim.v.event` entries; for each winid with
       `event.topline ~= 0`, call `M.check(tonumber(winid))`.
     - `CursorMoved`, `CursorMovedI` (scheduled) → for each window showing the
       changed buf, `states[win]:update_current()`.
     - `InsertLeave`, `TextChanged`, `TextChangedI` → reset states for the buffer
       (drop and let `WinScrolled` recreate on next scroll).
     - `WinClosed` → `states[win]:stop()` + `states[win] = nil`.
     - `CmdlineLeave` → if `ev.file == "/" or "?"` and `incsearch`, reset states
       for matching bufs (prevents incsearch jumps queuing a stale animation).
   - `vim.on_key` for `<ScrollWheelUp>` and `<ScrollWheelDown>` — set
     `mouse_scrolling = true`. `M.check()` consumes the flag.
   - Hot path `M.check(win)`:
     1. Bail if not `enabled`, `vim.o.paste`, `reg_executing() ~= ""`,
        `reg_recording() ~= ""`, or `vim.g.beast_scroll_disabled`.
     2. `state = State.get(win, config.filter)` → bail if nil or
        `vim.b[buf].beast_scroll_disabled`.
     3. If `mouse_scrolling`: clear flag, snap `state.current = state.view`, return.
     4. If `scrollbind` is on and `win ~= nvim_get_current_win()`, stop and return.
     5. Compute `delta = abs(state.view.topline - state.current.topline)`. If
        `delta <= 1`, snap and return.
     6. New target. `state.target = deepcopy(state.view)`. `state:stop()` any
        ongoing animation. `state:wo({ scrolloff = 0, virtualedit = "all" })`.
     7. Repeat detection: `now = uv.hrtime(); is_repeat = (now - state.last_ns)/1e6
        <= config.animate_repeat.delay_ms; state.last_ns = now`.
     8. Pick `prof = is_repeat and config.animate_repeat or config.animate`.
     9. `nvim_win_call(win, function() winrestview(state.current) end)` — snap back.
     10. Compute `scrolls` = number of lines to traverse using `nvim_win_text_height`
         when available (fold-aware), else `abs(target.topline - current.topline) +
         abs(target.topfill - current.topfill)`.
     11. Direction: `down = target.topline > current.topline`.
     12. Start `state.timer` with `vim.uv.new_timer()`, repeating every
         `prof.step_ms`. On each tick (`vim.schedule_wrap`):
         - If `not state:valid()` → `state:stop()`, return.
         - Compute `t = elapsed / prof.total_ms`, clamp to 1, apply easing.
         - `scrolled_target = floor(scrolls * eased_t)`. `scroll = scrolled_target -
           scrolled_so_far`. If `scroll > 0`, run
           `nvim_win_call(win, function() vim.cmd("keepjumps normal! " .. scroll ..
           (down and SCROLL_DOWN or SCROLL_UP)) end)`.
         - `state:update_current()`.
         - If `t >= 1`: `nvim_win_call(win, function() winrestview(state.target) end)`,
           `state:stop()`.
   - Why: Single owner for state, autocmds, and the animation step loop. Mirrors
     `indent/init.lua` shape (setup → ensure_autocmds → augroup) and the
     `breadcrumb/init.lua` ownership model.
   - Depends on: Steps 1, 2
   - Risk: Medium — correct interaction with `scrolloff`, `scrollbind`, folds,
     and macros must be verified manually (see Testing Strategy).

## Testing Strategy

- **Unit tests**: None. `tests/` is empty in this repo; introducing a test
  harness is out of scope for this spec. The animation is timer-driven and
  inherently hard to assert on without a harness — manual verification covers it.
- **Bench**: None. The lib has no hot computation worth micro-benchmarking
  (one autocmd callback per scroll event; the rest is timer ticks). If timer
  overhead ever becomes suspect, add `scripts/bench-scroll.lua` in a follow-up.
- **Manual verification** (after wiring `require("beast.libs.scroll").setup()`
  from `lua/beast/init.lua` — done by the user post-spec):
  1. Hold `j` in a 1000-line file → viewport scrolls smoothly without queueing.
     Releasing the key stops within ~200 ms.
  2. Hold `k` → same, upward.
  3. `<C-d>` and `<C-u>` → smooth half-page scrolls.
  4. `gg` then `G` → animates to top, then to bottom (no instant snap).
  5. `/foo<CR>` jumping across the buffer → animates to the match.
  6. Mouse wheel scroll → no animation (terminal-native).
  7. Macro: `qqjjjjq` then `5@q` → no animation while macro runs; cursor lands
     correctly.
  8. Open two splits in the same buffer with different `topline`s → scrolling in
     one does not animate the other.
  9. `:set scrollbind` in two splits → only the focused window animates; the
     bound window updates instantly.
  10. `vim.b.beast_scroll_disabled = true` on a buffer → no animation there;
      other buffers still animate.
  11. `:lua require'beast.libs.scroll'.disable()` → all animations stop, scrolling
      becomes instant. `enable()` restores. `toggle()` flips.
  12. Open `:terminal` and scroll → no animation (terminal filter).

## Risks & Mitigations

- **Risk**: Timer ticks fire after a window/buffer is closed, throwing on
  `nvim_win_call`.
  **Mitigation**: `state:valid()` check at the top of every tick; `WinClosed`
  autocmd stops + drops state proactively.

- **Risk**: Held `j` produces a backlog — new `WinScrolled` arrives mid-animation
  with a further target.
  **Mitigation**: `M.check` always `state:stop()`s the existing animation before
  starting a new one with the freshest `target`. Repeat-profile (50 ms) ensures
  the new animation finishes before the next keyrepeat arrives at typical rates.

- **Risk**: `scrolloff` restoration leaks if `state:stop()` is missed.
  **Mitigation**: `state:wo()` snapshots only first call, restores idempotently;
  `disable()` walks all states and stops each. `WinClosed` does the same.

- **Risk**: Folds make `topline + N` an incorrect target.
  **Mitigation**: Use `nvim_win_text_height(win, { start_row, end_row })` when
  available (Neovim ≥ 0.10) for the fold-aware line count. Fallback to raw
  topline delta otherwise.

- **Risk**: `<C-e>`/`<C-y>` with `scrolloff > 0` cause cursor jumps mid-animation.
  **Mitigation**: `state:wo({ scrolloff = 0, virtualedit = "all" })` for the
  duration of the animation; restore on stop.

- **Risk**: Search (`/`) with `incsearch` shifts `topline` per keystroke,
  triggering animations the user never sees finish.
  **Mitigation**: `CmdlineLeave` for `/` and `?` resets state so the post-search
  jump animates from the final position rather than from a stale snapshot.

## Success Criteria

- [ ] Holding `j`/`k` in a long file produces visibly smooth viewport scrolling
      (no per-line jump, no queueing after release).
- [ ] `<C-d>` / `<C-u>` / `gg` / `G` / search jumps animate.
- [ ] Mouse wheel, macros, terminal buffers, and `paste` mode skip animation.
- [ ] `:lua require'beast.libs.scroll'.toggle()` flips behavior live.
- [ ] No leaked `scrolloff` / `virtualedit` changes after `disable()` is called
      with active animations.
- [ ] Two splits scroll independently; `scrollbind` only animates the focused one.
- [ ] No new plugin dependency; only `vim.api`, `vim.fn`, `vim.uv`, `vim.on_key`.

## ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs
once committed:

- New library `beast.libs.scroll` — first library in BeastVim that animates
  *buffer/viewport state* (as opposed to `libs/animate.lua`, which animates
  float window geometry). Establishes the pattern that viewport animation is
  timer-driven (`vim.uv`) and stateful per-window, separate from the geometry
  animator. Future viewport-related effects (e.g. cursor-line animation) should
  follow this lib's shape rather than retrofitting `animate.lua`.
- Decision to **port** the snacks.scroll algorithm natively rather than vendor
  `snacks.nvim` as a dependency — consistent with the project's preference for
  native primitives (see existing ADR-009 if present). The trade-off: we own
  ~250 LOC of animation code instead of pulling a multi-thousand-LOC plugin.

## Completed

- 2026-05-28: Phase 1 implemented and verified.
  - Files created: `lua/beast/libs/scroll/{config,state,init}.lua`
  - Stylua + headless smoke test pass.
  - `tec-review` verdict: **PASS WITH WARNINGS**; nits addressed in-phase
    (dropped unused `uv` in `state.lua`; extracted `M._tick` from `M.check`).
  - ADR-018 written documenting the decision.
  - Codemaps updated (INDEX.md, libraries.md).
  - Spec drift documented in ADR-018: `State.get(win, states, filter)` carries
    the registry as an argument; `EASINGS` table lives in `init.lua` not
    `config.lua`. Both intentional, both are improvements over the spec text.
