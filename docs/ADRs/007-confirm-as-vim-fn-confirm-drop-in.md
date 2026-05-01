# ADR-007: Confirm UI as vim.fn.confirm Drop-In Replacement

**Status:** Accepted

**Date:** 2026-04-30

**Evidence:** Commits `d6fe8a3`, `0a06357`; file `lua/beast/libs/confirm/`

## Context

The explorer library needed confirmation dialogs (delete, overwrite). Initially, `confirm` had a custom boolean API. This meant callers couldn't switch between the built-in `vim.fn.confirm` and the Beast UI without changing their code. The explorer's usage (`refactor(explorer): callback in confirm`) highlighted the friction.

## Decision

Rewrite `beast.libs.confirm` to match `vim.fn.confirm`'s signature exactly:
- Same positional args: `confirm(msg, choices, default, type)`
- Choices use `"&Yes\n&No"` format with `&` hotkey markers
- Returns 1-based integer (0 = dismissed)
- Hotkey press immediately selects (case-insensitive)
- Supports N buttons (not limited to 2)

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Drop-in compatibility means existing `vim.fn.confirm` calls can be replaced by simply changing the function reference
2. Hotkey support makes the UI faster than mouse-based or arrow-key selection
3. 1-based integer return matches Vim conventions — no surprise for Vim users
4. N-button support handles future use cases without API changes

## Consequences

- **Positive:** Any code using `vim.fn.confirm` semantics works unchanged; explorer confirm simplified
- **Negative:** The `&` parsing adds complexity to the implementation
- **Risks:** Subtle behavioral differences from `vim.fn.confirm` (async vs sync) must be documented

## References

- Commit: `d6fe8a3` — refactor(confirm): make API a drop-in replacement for vim.fn.confirm
- Commit: `0a06357` — refactor(explorer): callback in confirm (motivation)
- File: `lua/beast/libs/confirm/`
