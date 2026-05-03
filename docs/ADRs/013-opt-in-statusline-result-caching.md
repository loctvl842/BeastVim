# ADR-013: Opt-In Result Caching with Event-Gated Invalidation

**Status:** Accepted (supersedes [ADR-010](010-no-engine-level-statusline-cache.md))

**Date:** 2026-05-03

**Evidence:** `lua/beast/libs/statusline/init.lua` (`state.cache`, `eval_component`, `invalidate_component`); `scripts/bench-statusline.lua` output (6.41 µs/render post-cache vs ~10–12 µs/render pre-cache); component migrations in `lua/beast/libs/statusline/components/{position,filetype,shiftwidth,encoding}.lua`

## Context

[ADR-010](010-no-engine-level-statusline-cache.md) removed the engine-level cache because the original design (always-on, three-scope cache) caused invalidation bugs (e.g. filetype showing "Lua" after switching to a no-filetype buffer; explorer components disappearing) and seemed to add machinery without measurable benefit on cheap providers.

After ADR-010 landed, two facts became clear:

1. **The bar redraws on every keystroke.** Neovim re-evaluates `statusline` (a `%!` expression) on every CursorMoved / TextChanged / mode change. Most components don't actually need this granularity — a `vim.bo[bufnr].filetype` lookup produces the same answer between redraws of the same buffer.
2. **`update` was a vestigial knob.** Each component already declared its semantic refresh events (`update = { "ModeChanged" }` for mode, `update = { "DiagnosticChanged", "BufEnter" }` for diagnostics). The engine ignored `update` after ADR-010 — the field only triggered `redrawstatus`, which was redundant since the bar redraws constantly. The `---@field update string[] -- "invalidate this component's cache"` doc was a lie.

The post-mortem on ADR-010's bugs revealed they weren't intrinsic to caching — they were intrinsic to *always* caching (a window-scoped cache that survived buffer switches in the same window). Opt-in caching keyed by an explicit `update` list lets the component author state exactly when their result becomes stale, which is the same contract heirline ships in production.

## Decision

Reintroduce the engine cache as **opt-in via the `update` field**:

- **No `update` declared** → run the provider on every render (preserves current behaviour for migration safety).
- **`update = { ... }` declared** → cache the provider's return value, keyed by `scope`, and invalidate the cache only when one of the declared events fires.

Cache buckets:

| `scope` | Key | Cleanup trigger |
|---|---|---|
| `global` | `comp_id` | declared `update` event |
| `buffer` | `(comp_id, ctx.bufnr)` | `BufWipeout` clears the slot for `args.buf`; declared event clears all buffers for that component |
| `window` | `(comp_id, ctx.winid)` | `WinClosed` clears the slot for `tonumber(args.match)`; declared event clears all windows |

**`pcall` failures are NOT cached** (rubber-duck blocking finding). A transient provider error must not stick the component to "hidden" until the next event — the next render retries.

`update` strings keep the existing `"<event> [pattern]"` syntax (e.g. `"OptionSet shiftwidth"`, `"User BeastStatuslineGitChanged"`).

## Alternatives Considered

- **Keep ADR-010's "no cache" stance and let every component implement its own cache.** Rejected: components that need event-gated freshness (position on CursorMoved, filetype on FileType, shiftwidth on `OptionSet shiftwidth`) all end up writing the same caching scaffold. Centralising it in the engine collapses ~30 lines per component into one declarative `update = { ... }` list and a `scope`.
- **Always cache (the original ADR-010 antagonist).** Rejected again: this is what caused ADR-010's bugs. Always-on caching forces the engine to guess invalidation; component authors know when their data goes stale.
- **Composite `(winid, bufnr)` key for `window` scope** to avoid declaring `BufEnter` for window-scoped components. Set aside (rubber-duck suggestion): keeps scope semantics single-keyed (key = winid OR bufnr, never pairs); the cost is one extra `BufEnter` entry in `position`'s update list — explicitly documented in the dev spec.
- **Drop `update` for cheap components** (e.g. position, filetype). Rejected during user review: a "cheap" provider still costs a `vim.fn.line(".")` + `string.format` on every keystroke. Caching is a free win once the framework supports it, and "cheap" is not a load-bearing distinction once the engine handles invalidation declaratively.

## Rationale

1. **Measured speedup**: bench dropped from ~10–12 µs/render to **6.41 µs/render** (3 × 1000 sample). Lualine baseline 94.77 µs/render → Beast is now **14.8× faster** (was ~7.3×).
2. **Component code shrank**: `position` / `filetype` / `shiftwidth` / `encoding` now each declare 1–3 events instead of running their provider every keystroke.
3. **Component-author ergonomics**: the contract is "list the events that change your data; the engine handles the rest." This is the same model heirline uses successfully.
4. **Backwards compatible**: components without `update` still run every render — existing behaviour is preserved during migration.
5. **Failure isolation preserved**: pcall failures are NOT cached, so a flaky provider doesn't get stuck hidden until the next event — it retries on the next render.

## Consequences

- **Positive:**
  - Statusline render time roughly halved (6.41 µs vs ~10–12 µs).
  - Components express staleness declaratively (`update` is now meaningful, not a no-op).
  - `BufWipeout` / `WinClosed` cleanup is centralised — no per-component cache to leak.
- **Negative:**
  - The engine grew by ~80 lines (cache buckets, `invalidate_component`, scoped lookup branches in `eval_component`).
  - Window-scoped components must include `BufEnter` in their `update` list (e.g. `position`) to invalidate on `:bnext`. Documented in the dev spec.
  - Authors who forget `update` will silently get every-render behaviour — no error, just slower. (Acceptable: it's the safe default.)
- **Risks:**
  - If a future event is fired *before* a buffer/window is set up properly, a stale empty fragment could be cached. Mitigated by the rubber-duck-suggested rule: pcall failures and `nil` returns are never cached, only successful returns (including `{}` for "hide").
  - All-buckets invalidation on a declared event is conservative (we drop entries for buffers / windows that didn't actually change). Acceptable: the next render is still O(visible components), and per-event optimisation would re-introduce the kind of edge-case bugs ADR-010 cited.

## References

- Supersedes: [ADR-010](010-no-engine-level-statusline-cache.md) — the "no engine cache" decision is reversed; the "components own their own state" half (push-mirrored providers like `git_commit`, `git_branch`) still holds.
- Dev spec: `docs/dev-specs/statusline-library.md` § "Why we (re)introduced opt-in result caching"
- Code:
  - `lua/beast/libs/statusline/init.lua` — `state.cache`, `eval_component`, `invalidate_component`
  - `lua/beast/libs/statusline/components/position.lua` — added `update = { CursorMoved, CursorMovedI, BufEnter }`
  - `lua/beast/libs/statusline/components/filetype.lua` — added `update = { BufEnter, FileType }`
  - `lua/beast/libs/statusline/components/shiftwidth.lua` — added `OptionSet shiftwidth`
  - `lua/beast/libs/statusline/components/encoding.lua` — added `OptionSet fileencoding/encoding`
- Bench: `scripts/bench-statusline.lua` (3 × 1000 samples; auto-discovered by health-config)
- Related ADRs:
  - [ADR-009](009-native-statusline-replaces-heirline.md) — Native `%!` Statusline
  - [ADR-011](011-file-bound-provider-wrapper.md) — `file_bound` (UX wrapper, not a cache)
  - [ADR-012](012-compound-fragment-component-model.md) — Compound-Fragment Component Model
