# ADR-018: Native Smooth Scroll Library (Viewport Animation)

**Status:** Accepted

**Date:** 2026-05-28

**Evidence:** Dev spec `docs/dev-specs/scroll-library.md`; files `lua/beast/libs/scroll/{config,state,init}.lua`

## Context

Holding `j`/`k` in BeastVim produces an instant per-line redraw — visually choppy in long files. LazyVim feels noticeably smoother because `snacks.nvim`'s `snacks.scroll` animates viewport (`topline`) transitions via a timer-driven `<C-e>`/`<C-y>` tween. BeastVim already sets `vim.o.smoothscroll = true`, but that core option only affects how wrapped lines render under existing scroll commands; it does not animate.

The existing shared `lua/beast/libs/animate.lua` animates float-window *geometry* (`row`/`col`/`width`/`height`/`winblend`) via `vim.defer_fn` at 30 FPS with `nvim_win_set_config`. It is the wrong shape for viewport animation: viewport state is `winsaveview`/`winrestview` + `<C-e>`/`<C-y>` step commands inside `nvim_win_call`, with per-window state and `WinScrolled`-driven entry — none of which fits the `animate.lua` engine.

## Decision

Build a new library `lua/beast/libs/scroll/` that animates viewport scrolling natively, by porting the algorithm of `snacks.scroll` rather than vendoring `snacks.nvim`. Use a `vim.uv.new_timer()` per active animation, per-window state, and a two-profile animation (normal 200 ms / repeat 50 ms within 100 ms) to keep held-key scrolling fluid.

Three files: `config.lua` (frozen-config metatable), `state.lua` (`Beast.Scroll.State` class — per-window view/current/target/timer/option-backup), `init.lua` (public API, autocmds, hot path `M.check`, extracted timer body `M._tick`).

## Alternatives Considered

1. **Vendor `snacks.nvim` and enable only its `scroll` module.**
   Pulls in a multi-thousand-LOC plugin and its `snacks.animate` dependency for one focused behavior. Rejected — BeastVim's conventions prefer native primitives over plugins (see ADR-009, ADR-015), and we already maintain bespoke equivalents of every other snacks module we use.

2. **Use `karb94/neoscroll.nvim`.**
   Smaller, but it animates only step-fixed commands (`<C-d>`, `<C-u>`, `gg`, `G`) via keymap remaps. It does not hook `WinScrolled`, so held `j`/`k` past `scrolloff` (the most common case) is unaffected. Rejected — does not solve the user-reported smoothness gap.

3. **Extend `lua/beast/libs/animate.lua` to handle viewport state.**
   Would require adding `winsaveview`/`winrestview`/`<C-e>`/`<C-y>` plumbing, a per-window registry, `WinScrolled` integration, mouse-wheel detection, and macro/paste/scrollbind guards — none of which belong in a geometry tweener. Would dilute the engine's single responsibility (animating float-window properties — ADR-004). Rejected — extraction-by-third-need (ADR-004 rationale) doesn't apply; this is a different *kind* of animation.

4. **Use `vim.defer_fn` like `animate.lua`.**
   `defer_fn` reschedules per frame and is fine at 30 FPS for geometry, but scroll wants 100–200 Hz tick rates (5–10 ms steps) for visually smooth `<C-e>` micro-batches. `vim.uv.new_timer()` with `start(step_ms, step_ms, ...)` is the precise primitive for that. Adopted.

## Rationale

1. **Different domain than `animate.lua`** — viewport animation is fundamentally about *commands sent to a window* (`<C-e>` / `<C-y>`) not *properties set on a float* (`nvim_win_set_config`). Forcing both into one engine would couple unrelated concerns.
2. **Two-profile animation is the smoothness trick** — a single duration either lags on slow profile (held key produces visible backlog) or feels jumpy on fast profile (single jumps look snappy-not-smooth). The 100 ms repeat-window detection (`uv.hrtime`) gives the best of both: 200 ms for one-shot jumps, 50 ms for held-key sequences.
3. **Per-window state** — each split has independent `current`/`target`/`timer`, so scrolling one split never interferes with another (verified for `scrollbind` too: only the focused window animates).
4. **Native primitives only** — `vim.api.*`, `vim.fn.winsaveview`/`winrestview`, `vim.api.nvim_win_call`, `vim.uv.new_timer`, `vim.on_key`. No new dependency, ~300 LOC owned in-repo, easy to audit and tune.
5. **State-owned-by-init** matches the convention established by `indent`, `breadcrumb`, `notify` (ADR-001 lineage) — `setup → ensure_autocmds → augroup`, module-local `states` table, idempotent `enable`/`disable`.
6. **Frozen-config metatable** (ADR-003) carries over verbatim — no live-reconfigure path.

## Consequences

- **Positive:** Held `j`/`k`, `<C-d>`/`<C-u>`, `gg`/`G`, search jumps all animate. No plugin dependency added. Macros, paste mode, terminal buffers, and `scrollbind` non-focused sides correctly skip animation.
- **Positive:** Window options (`scrolloff`, `virtualedit`) are snapshotted-then-restored per animation via `State:wo()`; `disable()` walks all states and restores idempotently. `WinClosed` cleans state proactively.
- **Negative:** ~300 LOC of timer-and-state code to maintain. Tunables (profile durations, repeat window) are sensitive — bad values feel laggy or jumpy.
- **Negative:** Animation is timer-driven; behavior is hard to assert in headless tests. Verification is manual (12-step checklist in the dev spec). `tests/` remains empty for now (out of scope).
- **Risks:** Timer leaks if `state:stop()` is missed — mitigated by guards in `disable()`, `WinClosed`, and tick-time `state:valid()` checks. `nvim_win_text_height` (Neovim ≥ 0.10) is required for fold-aware line counting; a coarser fallback ships for older versions.
- **Architectural precedent:** Establishes that *viewport / buffer-state* animation is timer-driven (`vim.uv`) and stateful per-window, distinct from *float geometry* animation (`animate.lua`, ADR-004). Future cursor-line or scroll-effect work should follow this lib's shape, not retrofit `animate.lua`.

## Review Notes

`tec-review` verdict: **PASS WITH WARNINGS**. Non-blocking nits addressed in the same phase: dropped unused `local uv` in `state.lua`; extracted the timer body from `M.check` into `M._tick` to keep the hot path under 50 LOC. One spec drift documented here: `State.get(win, states, filter)` takes the registry as an argument so it can live in `init.lua` (spec wrote `State.get(win, filter)`); registry-as-argument keeps `state.lua` pure. `EASINGS` table lives in `init.lua` not `config.lua` — semantically right since `init.lua` is the only consumer.

## References

- Dev spec: `docs/dev-specs/scroll-library.md`
- Snacks reference: `~/.local/share/LazyVim/lazy/snacks.nvim/lua/snacks/scroll.lua`
- Related: ADR-003 (Read-Only Config Metatable), ADR-004 (Shared Animate Module — separate domain)
- Files: `lua/beast/libs/scroll/{config,state,init}.lua`
