# ADR-021: `display_tick` (FFI) Drives Statuscolumn Cache Invalidation

**Status:** Accepted

**Date:** 2026-05-31

**Evidence:** Dev spec `docs/dev-specs/statuscolumn-library.md`; files `lua/beast/libs/statuscolumn/{ffi,cache,init}.lua`

## Context

The statuscolumn library caches two things between renders:

- **Per `(win, tick, buf)`** — the bucketised sign map produced by walking `nvim_buf_get_extmarks` (one walk amortised across all visible lines).
- **Per line `(lnum, virtnum, relnum)`** — the interned result string for that line.

Both must invalidate exactly when the underlying state changes (extmarks update, fold structure changes, cursor moves under `&rnu`, etc.) and **never** invalidate between two reads of the same redraw — otherwise the cache is useless.

`snacks.nvim`'s statuscolumn uses a `vim.uv.new_timer()` that flushes the sign cache every 50 ms. This is simple — no FFI symbols needed — but it has two failure modes:

1. **Staleness** — between 0 and 50 ms after a buffer modification, the cache can serve stale signs.
2. **Wasted work** — when nothing changes, the cache flush happens anyway and the next render reruns the extmark walk.

`statuscol.nvim` uses an FFI-exposed Neovim global: `uint64_t display_tick;`. This counter is incremented by Neovim's core every time the screen is redrawn (it's the same tick the kernel uses internally to skip no-op redraws). It's the *exact* invalidation signal we want.

## Decision

Use the FFI-exposed `display_tick` as the cache invalidation key:

```c
ffi.cdef[[
  uint64_t display_tick;
  // ... fold_info, find_window_by_handle as before
]]
```

The cache key for per-window state is `(win, display_tick, buf)`. When `bump_window(win, tick, buf)` is called by the render path:

- If `(tick, buf)` match the cached entry → return `invalidated = false`. Signs map is reused.
- If the tick advanced or the buffer changed → return `invalidated = true`. The caller re-runs `signs.collect(buf)` and re-creates the per-line cache for that `(win, buf)`.

The `ffi.lua` module is pcall-guarded. On non-LuaJIT hosts or FFI ABI drift, `ffi.tick()` returns `0` (constant), and the cache effectively never auto-invalidates on tick alone — it still invalidates on explicit `drop_win` (WinClosed) and `drop_buf` (BufWipeout/BufDelete). This is a graceful degradation, not an error.

## Alternatives Considered

1. **Snacks-style 50 ms `vim.uv.new_timer()` flush.** Simple, no FFI. Rejected — produces both staleness (window where the cache is wrong) *and* wasted invalidations (when nothing changed). The dev spec calls correctness out as the deciding factor.

2. **Autocmd-based invalidation (`TextChanged`, `DiagnosticChanged`, `User GitSignsUpdate`, …).** Theoretically zero overhead per render. Rejected — we'd need to enumerate every event that could change a sign, fold, or relnum source; missing one causes silent bugs. The display_tick is *the* signal Neovim already uses to gate its own redraws — riding on it is correct by construction.

3. **`vim.api.nvim_get_option_value('statuscolumn', { win = win })` re-evaluation count as proxy.** Not exposed. Would need a counter incremented in render() itself — but that counts re-renders, not redraws (the wrong direction).

4. **No cache; recompute every line.** Simplest. Rejected — `signs.collect` is the most expensive single thing the lib does, and dropping the cache turns it from once-per-redraw into once-per-line (×80 for a typical viewport). Blows the 500 µs/window budget by an order of magnitude.

## Rationale

1. **`display_tick` is the canonical signal.** Neovim bumps it exactly when a redraw cycle starts. Our cache invalidation policy is "valid for one redraw", so the keys align 1:1 with what we want.
2. **Zero false positives, zero false negatives.** Unlike a timer (false positives during idle, false negatives during burst edits) or an autocmd list (false negatives for events we forgot), the tick is by construction correct.
3. **One extra FFI symbol over what we'd need anyway.** `fold_info` already requires LuaJIT + FFI for the fold producer. Adding `display_tick` to the same cdef block is a single line, single symbol.
4. **Graceful degradation.** Non-LuaJIT hosts or ABI drift produce `tick = 0`. The library still works; it just relies on explicit invalidation (`WinClosed`, `BufWipeout`) and re-renders unchanged-but-uncached lines a bit more often. No error path.

## Consequences

- **Positive:** Cache invalidation is correct by construction — never serves a sign map older than the current redraw cycle, never re-walks extmarks within a redraw cycle.
- **Positive:** No `vim.uv.new_timer()` to leak, no background work when the editor is idle.
- **Positive:** Bench numbers reflect realistic load: full-redraw of 200 lines ≈ 332 µs (signs.collect once + 200 line renders ≈ 1.7 µs/line). On a 50 ms timer model, the same load would either re-run signs.collect mid-redraw (worse) or serve stale data (also worse).
- **Negative:** Couples the lib to a Neovim internal symbol name (`display_tick`). The name is stable across all Neovim versions in scope (≥ 0.10), but a future rename would break our cache without us noticing — mitigated by `:checkhealth beast.libs.statuscolumn`, which reports the symbol's presence individually.
- **Negative:** Requires LuaJIT for the tick path. Standard Neovim ships with LuaJIT, but a non-LuaJIT Nvim (rare, niche distros) loses tick-based auto-invalidation and falls back to explicit-only invalidation.
- **Risks:** A future Neovim that bumps `display_tick` for ephemeral overlays (not actual buffer redraws) would invalidate our cache more aggressively than necessary. Surfaceable via the bench's `FullRedraw` scenario.
