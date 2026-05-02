# ADR-011: file_bound Provider Wrapper for Transient UI Buffers

**Status:** Accepted

**Date:** 2026-05-02

**Evidence:** `lua/beast/libs/statusline/util.lua` — `M.file_bound`; `M.IGNORED_FILETYPES`; `M.is_file_buffer`; used by `components/{filetype,position,shiftwidth,encoding,git_commit}.lua`

## Context

Several statusline components are bound to a real file buffer (filetype, cursor position, shift width, encoding, last-commit info). When the user focuses a transient `beast-*` UI buffer (explorer, toast, packer, key viewer), these components have nothing meaningful to compute about that buffer. Two undesirable behaviors followed:

1. The components went blank, so the right side of the bar visibly collapsed every time the explorer was opened — distracting and ugly.
2. Worse, file-bound components could read meaningless data from the transient buffer (e.g., position would read line/col from the explorer window if no guard was in place).

Initial fix attempts duplicated the same `_var = nil` + `if not is_file_buffer then return last_value end` pattern across five components. The implementations diverged subtly (different ordering of branches; one had a bug where it computed from the explorer window before checking).

## Decision

Extract `util.file_bound(compute)` — a wrapper that takes a compute function and returns a provider function. The wrapper:

1. Calls `compute(ctx)` only when `is_file_buffer(ctx)` is true (i.e. not a `beast-*` filetype)
2. Remembers the last value across renders in a closure
3. On transient UI buffers, returns the last remembered value so the component stays visible

The compute function uses a three-value return contract:

| Return | Effect |
|--------|--------|
| `string` | Update the stored value |
| `false` | Clear the stored value (component will hide) |
| `nil` | Keep the previous value unchanged |

`IGNORED_FILETYPES` (in the same `util.lua`) lists every transient filetype — **only `beast-*` entries**. Third-party plugin filetypes are deliberately excluded; users who want extended behavior wire their own `condition`.

## Alternatives Considered

- **Keep per-component `_var` caches with manual `if not is_file_buffer then ... end` guards** — what we had during implementation. Rejected: 5 copies of the same logic, subtly different, and the position component had a bug where compute ran on the explorer before the guard.
- **Generic engine cache in `init.lua` with scope-based invalidation** — rejected as a separate decision; see [ADR-010](010-no-engine-level-statusline-cache.md).
- **Two-value contract (`string` to set, anything else to keep)** — rejected: needed a way for `git_commit` to clear its cached value when a file has no commits, otherwise it would keep showing the previous file's commit. The `false` sentinel handles this without conflating "clear" with "skip".
- **Include third-party plugin filetypes (`neo-tree`, `lazy`, `Trouble`, etc.) in `IGNORED_FILETYPES`** — rejected: opens the door to a long bikeshed list. Beast-only keeps the contract clear. Users add component-side `condition` if they want more.

## Rationale

1. One implementation, one set of edge-case fixes, five call sites
2. The `false`/`nil`/`string` contract handles the three real cases observed in components: "I have a fresh value", "I'm a real file but truly have no value (clear)", "I'm a real file but data isn't ready yet (keep last)"
3. UX: file-bound parts of the bar stay visible when the user pops open the explorer, instead of collapsing
4. Establishes a reusable pattern for future bars (winbar, tabline) that need the same behavior on transient `beast-*` buffers
5. `IGNORED_FILETYPES` lives next to `is_file_buffer` and `file_bound`, so the whole "what counts as a file buffer" concept is in one file

## Consequences

- **Positive:** Five components now consistent and ~10-15 lines each; explorer / toast focus no longer collapses the bar; the pattern is reusable
- **Negative:** Component authors must learn the `false` vs `nil` distinction; not enforced at the type level (it's a runtime contract)
- **Risks:** If a real file's filetype somehow matches `beast-*` (extremely unlikely — they're internal UI conventions), `file_bound` would skip the compute. Acceptable given how `Buffer.new()` is used.

## References

- Code: `lua/beast/libs/statusline/util.lua` — `M.file_bound`, `M.IGNORED_FILETYPES`, `M.is_file_buffer`
- Components: `filetype.lua`, `position.lua`, `shiftwidth.lua`, `encoding.lua`, `git_commit.lua`
- Dev spec: `docs/dev-specs/statusline-library.md` § "`file_bound` — the file-bound provider wrapper"
- Related ADRs:
  - [ADR-010](010-no-engine-level-statusline-cache.md) — No Engine-Level Statusline Cache
  - [ADR-009](009-native-statusline-replaces-heirline.md) — Native `%!` Statusline
