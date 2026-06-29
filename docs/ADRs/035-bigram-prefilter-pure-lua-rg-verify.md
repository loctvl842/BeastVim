# ADR-035: Pure-Lua Bigram Prefilter for live_grep (rg Verifies, No Native Binary)

**Status:** Accepted

**Date:** 2026-06-29

**Evidence:** Dev spec `docs/dev-specs/finder-bigram-index.md`; commits `9a963fe` (Phase 1 — bigram core + extraction), `bb19336` (Phase 2 — chunked builder), `7d17ee2` (Phase 3 — live_grep wiring), `12a91dd` (Phase 4 — fs_event overlay); files: `lua/beast/libs/finder/engine/bigram.lua`, `engine/index.lua`, `engine/extract.lua`, `source/live_grep.lua`, `config.lua`; tests `tests/test-bigram.lua` (26 cases); bench `scripts/bench-grep.lua`; related: ADR-009/015 (native over vendored), ADR-013 (opt-in caching).

## Context

`source/live_grep.lua` re-walks and re-reads the whole tree on every keystroke via `ug`/`rg`. On a 90k-file repo the first keystroke must scan everything before any result. fff.nvim solves this with a Rust binary holding an in-memory bigram bitset; matching that exactly would mean vendoring a compiled engine (and its build hook — the very failure mode that prompted this work). We wanted fff's prune-the-pool speed without leaving pure Lua or dropping the existing `rg` correctness.

## Decision

Build a persistent, in-process **bigram inverted index** in LuaJIT FFI and let `rg`/`ug` remain the verifier. Each 2-byte sequence maps to a uint32 bitset column (bit per file); a query ANDs columns to a survivor file list, which is grepped as positional args. The index **only prunes** — `rg` verifies survivors, so results are byte-identical to a full scan. Engine is opt-in (`config.engine.enabled=false` default). Bigrams come only from a query's **literal runs** (metachars split, `\` escapes); no literals ≥2 bytes → full-scan fallback. Content and keys are lowercased to keep smart-case a safe superset. Freshness via recursive `fs_event` (refresh = superset re-add, deletes tombstoned). Matrix sized to `max_files` (~56 MB) so live appends never overflow.

## Alternatives Considered

1. **Vendor fff's Rust binary** — rejected: reintroduces the build-hook fragility, leaves pure Lua, exceeds personal-config scope.
2. **rg `--files-from` / xargs per keystroke** — `--files-from` doesn't exist; `xargs -0` works but full-scan above `max_survivors` is simpler and equally false-negative-free, so xargs was dropped.
3. **HIR regex bigram extraction (fff-style)** — rejected: literal-run extraction is conservative and dialect-agnostic; over-pruning risk is zero, rg verifies.
4. **uint64 bitsets** — rejected: 32-bit words keep all math in LuaJIT `bit`; capacity headroom comes from `max_files` sizing instead.

## Consequences

**Positive:** keystroke #1 collapses 90k→hundreds; query AND ~0.03 ms, build ~73 ms; off = exact current behavior; rg stays source of truth. **Tradeoffs:** ~56 MB resident when enabled; capped 5000 columns + `max_files` cap mean rare edges fall back to full scan; superset survivors mean rg re-checks extras (cheap). New shared `finder/engine/` modules other code may require.
