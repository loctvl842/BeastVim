# ADR-023: `vim.text.diff` (with `vim.diff` fallback) as Diff Backend

**Status:** Accepted

**Date:** 2026-06-01

**Evidence:** `lua/beast/libs/git/diff.lua`; dev spec `docs/dev-specs/git-library.md` § *Phase 1*; `scripts/bench-git.lua`; related: ADR-022 (native git lib).

## Context

Computing per-line hunk types requires a line-level diff of the working buffer text against the HEAD blob. The hot path runs on every `BufWritePost` and on debounced (`~200 ms`) `TextChanged{,I}` — so per-call cost is the dominant perf budget for the lib.

Neovim ships two built-in diff entry points:
- `vim.diff(a, b, opts)` — available since 0.10. Returns either a unified-diff string or, with `result_type="indices"`, a list of `{a_start, a_count, b_start, b_count}` quadruples.
- `vim.text.diff(a, b, opts)` — same signature, lives under the newer `vim.text` namespace introduced in 0.11.

Both wrap the same C-side `xdiff` (libxdiff, the same engine git itself ships) and accept `algorithm`, `linematch`, `result_type` options. `gitsigns.nvim` itself delegates to `vim.diff` for its hot path.

## Decision

Use `vim.text.diff` when available, fall back to `vim.diff` otherwise. Always call with:

```lua
{ result_type = "indices", algorithm = "histogram", linematch = 60 }
```

Feature-detect once at module load:

```lua
local diff_fn = (vim.text and vim.text.diff) or vim.diff
```

Surface the chosen backend via `M.backend` ("vim.text.diff" / "vim.diff") so `:checkhealth` reports which one is in use.

## Alternatives Considered

1. **Shell out to `git diff --no-index <tmp_base> <tmp_current>`.** Authoritative and version-stable. Rejected — every recompute would fork `git` plus write two temp files. Bench would not survive: even at 5k lines we'd be paying ~10–20 ms of process+IO overhead vs `vim.text.diff`'s ~2.6 ms (pure in-process). Also ties debounce timing to process startup latency on slow filesystems.
2. **libgit2 via Lua FFI.** Cross-platform install story is awful — users would need a system `libgit2` matching our cdef. Rejected; the per-call savings vs `xdiff` would be negligible since both are C-level.
3. **Pure-Lua diff implementation (e.g. Myers from `neogen` or `mini.diff`).** Rejected — orders of magnitude slower for buffers > 1 k lines than the C-side `xdiff`, and adds maintenance burden for zero feature gain.
4. **`require("gitsigns.diff_int")` or any gitsigns internal.** Rejected — that's exactly the dependency ADR-022 removes.

## Rationale

1. **Same C engine as `gitsigns.nvim`.** There is no realistic performance ceiling above what gitsigns achieves; we're not paying for an indirection.
2. **`result_type="indices"` skips string allocation.** Returns four-int quadruples we feed straight into `hunks.lua` — no unified-diff text to parse.
3. **`algorithm="histogram"` + `linematch=60` match git's own defaults.** Produces hunks visually identical to `git diff` so users' mental model carries over.
4. **Both APIs exist on the floor Neovim version (0.10+)** the rest of BeastVim targets — feature detection is a one-liner with no runtime cost.
5. **Health surface is honest about which path is hot.** When 0.11+ is the floor, the fallback can be removed; until then, `:checkhealth` shows which entry point each user is actually exercising.

## Consequences

- **Positive:** Bench `scripts/bench-git.lua`: 1k=0.3 ms, 5k=2.6 ms (threshold 10 ms), 20k=19 ms — comfortably under budget even at 20 k lines. The debounce buffer absorbs typing storms entirely.
- **Positive:** Zero new dependencies, zero new build steps, zero new tmp files on disk per recompute.
- **Positive:** When `vim.text.diff` becomes the only entry point, removing the fallback is a one-line delete.
- **Negative:** We inherit any `xdiff` quirks (notably its `linematch` heuristic occasionally chooses surprising boundaries on contiguous identical lines). Acceptable — same quirks ship with `git diff` itself.
- **Negative:** Pure-delete hunks have `b_count=0` and `b_start` pointing at the *previous* surviving line (or `0` if deletion is at the top). Required dedicated handling in `hunks.lua` (`topdelete` vs `delete`) and `nav.lua` (b_start=0 → 1 normalisation). Documented in code.
- **Risk:** If `vim.text.diff` ever diverges in option shape from `vim.diff`, the feature-detect breaks silently. Mitigated — both have identical signatures today, and `:checkhealth` would flag a runtime error from `diff.compute_hunks` immediately.
