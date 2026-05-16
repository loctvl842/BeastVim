# ADR-016: Tabline 3-State Buffer Highlights with Event-Driven Cache

**Status:** Accepted

**Date:** 2026-05-13

**Evidence:** `lua/beast/libs/tabline/highlights.lua` (BeastTlSelected, BeastTlVisible, BeastTlNormal groups); `lua/beast/libs/tabline/context.lua` (`effective_active`, `visible_bufs` set); `lua/beast/libs/tabline/init.lua` (dirty-flag + autocmd invalidation); commit `f7d0d92` ("feat(tabline): add 3-state buffer highlights and event-driven cache"); `docs/dev-specs/tabline-library.md`

## Context

The initial tabline (commit `86adbb8`) had two visual states: active buffer and inactive buffer. This didn't distinguish between buffers visible in a split (but not focused) and buffers not shown in any window. Users with multiple splits couldn't tell which buffers were on screen vs merely listed. Additionally, when the explorer sidebar had focus, the previously-active buffer still showed as "selected" even though no code buffer was focused.

## Decision

Adopt a 3-state highlight model for buffer cells:

| State | Condition | Visual |
|-------|-----------|--------|
| Selected | `bufnr == effective_active` | accent fg, active bg, underline |
| Visible | buffer in a window, not active | dimmed fg, active bg |
| Normal | listed, not in any window | dimmed fg, darker bg |

When a sidebar filetype has focus, `effective_active = -1` so no buffer shows as Selected — all code buffers appear as Visible or Normal.

The render pipeline uses event-driven caching: full rebuild only on state-change events (`BufAdd`, `BufDelete`, `WinEnter`, `DiagnosticChanged`, etc.), cached redraws return in <0.1µs between events.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. 3-state model matches user mental model: "which buffers am I looking at right now?" — Selected (focused), Visible (on screen), Normal (background).
2. `effective_active = -1` when sidebar has focus prevents the misleading "selected code buffer" highlight (commit `f7d0d92` message explicitly calls this out).
3. Event-driven dirty flag avoids redundant rebuilds — hot render stays at 0.09µs (bench in commit `86adbb8`).

## Consequences

- **Positive:** Users can visually distinguish on-screen vs background buffers at a glance. Sidebar focus no longer causes a confusing "selected" highlight on a code buffer.
- **Negative:** Three highlight states means more highlight groups to maintain (`BeastTlSelected*`, `BeastTlVisible*`, `BeastTlNormal*`).
- **Risks:** If new window types (e.g. floating pickers) aren't added to the sidebar detection, `effective_active` could misfire. The `visible_bufs` set in `context.lua` is the place to audit.

## References

- Commit: `f7d0d92`
- Dev spec: `docs/dev-specs/tabline-library.md`
- Related ADRs: depends on [ADR-015](015-native-tabline-replaces-heirline.md)
