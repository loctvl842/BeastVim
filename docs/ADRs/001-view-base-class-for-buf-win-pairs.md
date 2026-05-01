# ADR-001: View Base Class for Buffer+Window Pairs

**Status:** Accepted

**Date:** 2026-03-23

**Evidence:** Commit `7108ef8` (init notify), `9d47930` (fix view child method), file `lua/beast/libs/view.lua`

## Context

Multiple UI libraries (notify, explorer, key, confirm) each need to manage a floating window paired with a buffer. Without a shared abstraction, each library reimplements validity checks, close logic, and state cleanup independently — leading to inconsistent behavior and duplicated code.

## Decision

Introduce `Beast.View` as a base class at `lua/beast/libs/view.lua` that wraps a `buf`+`win` pair. All libraries subclass it via `:extend(init)` to add domain-specific fields. The base provides `is_valid()`, `close()`, and constructor logic.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Centralizes validity checking (`nvim_buf_is_valid` + `nvim_win_is_valid`) in one place
2. Guarantees consistent cleanup (nil-ing `buf`/`win` on close)
3. Allows libraries to extend without reimplementing boilerplate
4. Supports the `__call` metamethod pattern for constructor ergonomics

## Consequences

- **Positive:** All libraries get free validity/close logic; new libraries only need `View:extend(init)`
- **Negative:** Libraries are coupled to View's API shape
- **Risks:** If View's contract changes, all subclasses break simultaneously

## References

- Commit: `7108ef8` — initial notify library introduced View
- Commit: `9d47930` — fixed child method resolution in View
- File: `lua/beast/libs/view.lua`
