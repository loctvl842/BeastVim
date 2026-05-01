# ADR-004: Extract Shared Animation Module

**Status:** Accepted

**Date:** 2026-04-21

**Evidence:** Commit `bb4a83c`; file move `lua/beast/libs/{notify => }/animate.lua`

## Context

The notification library included an animation engine (`animate.lua`) that drives frame-by-frame window property transitions using `vim.defer_fn`. The engine is pure math — it takes `(win, from, to, duration, on_done, opts)` with no knowledge of notifications, records, or config. Other libraries (e.g. toast) may need animation.

## Decision

Move `animate.lua` from `lua/beast/libs/notify/animate.lua` to `lua/beast/libs/animate.lua` — making it a shared top-level module available to any library. The API stays unchanged.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. The animation engine has zero domain coupling — it only needs a window handle and numeric start/end values
2. Keeping it inside notify would force other libraries to reach into notify's internals
3. Extraction followed the project convention: extract on third-library need (anticipated by toast/packer)

## Consequences

- **Positive:** Any library can animate without depending on notify
- **Negative:** One more top-level file in `libs/`
- **Risks:** Minimal — the module is pure, stateless, and has a stable API

## References

- Commit: `bb4a83c` — refactor(notify): split animate
- File: `lua/beast/libs/animate.lua`
