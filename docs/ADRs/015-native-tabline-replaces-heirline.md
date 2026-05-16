# ADR-015: Native `%!` Tabline Replaces Heirline

**Status:** Accepted

**Date:** 2026-05-12

**Evidence:** `lua/beast/libs/tabline/init.lua` (`render()`, `setup()`, event-driven dirty flag); `lua/beast/libs/tabline/sections/` (cell.lua, buffer_list.lua, offset.lua, tabpages.lua); commit `86adbb8` ("feat(tabline): add native tabline library"); `docs/dev-specs/tabline-library.md`; bench in commit message: cold 154µs, hot 0.09µs

## Context

Heirline.nvim previously drove both statusline and tabline. ADR-009 replaced the statusline half with a native `%!` library. The tabline half remained on heirline, meaning: heirline stayed as a dependency solely for tabline, the tabline's per-render component-tree reflection added overhead, and the two bars used different rendering models. Aligning both on native `%!` removes the heirline dependency entirely. (Note: the old heirline plugin code still exists under `lua/beast/plugins/bars/` as dead code pending removal.)

## Decision

Build `lua/beast/libs/tabline/` as a native `%!v:lua` tabline following the same conventions as the statusline library (ADR-009). The render pipeline is:

```
render() → context.build(state) → offset + buffer_list + tabpages → "%#Group#text%*" string
```

Key structures:
- `context.lua` — single-pass data gathering (buffers, names, icons, diagnostics, sidebar)
- `sections/cell.lua` — two click regions per buffer cell (body `%@GoTo@` + close `%@Close@`)
- `sections/buffer_list.lua` — anchor-based truncation with `≪`/`≫` markers
- `sections/offset.lua` — centered sidebar title
- `sections/tabpages.lua` — right-aligned `%nT` tab indicators

Loaded via `packer.lazy()` on VimEnter (deferred).

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Removes the heirline.nvim dependency — one fewer external plugin to maintain.
2. Aligns statusline and tabline on the same `%!` rendering model (consistency, per ADR-009).
3. Cold render (154µs) and hot render (0.09µs) match or beat heirline's overhead (bench in commit `86adbb8`).
4. Dev spec (`tabline-library.md`) explicitly targets "same philosophy as statusline" — this is the planned next step after ADR-009.

## Consequences

- **Positive:** Zero external dependencies for either bar. Hot render is effectively free (0.09µs cached). Click regions use native `%@Func@` — no timer-based click detection.
- **Negative:** Custom tabline loses heirline's declarative component composition. Tabline-specific features (truncation, anchor, sidebar offset) are hand-coded.
- **Risks:** Visual regressions vs heirline are possible. The bench numbers (commit `86adbb8`) are the baseline to watch.

## References

- Commit: `86adbb8`
- Dev spec: `docs/dev-specs/tabline-library.md`
- Related ADRs: follows [ADR-009](009-native-statusline-replaces-heirline.md) (same pattern, tabline half)
