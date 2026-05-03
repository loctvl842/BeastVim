# ADR-010: No Engine-Level Statusline Cache

**Status:** Superseded by [ADR-013](013-opt-in-statusline-result-caching.md) (the "no engine cache" decision is reversed; the "components own their own state" half still holds for push-mirrored providers like `git_commit` / `git_branch`)

**Date:** 2026-05-02

**Evidence:** `lua/beast/libs/statusline/init.lua` (no `state.cache` table); dev spec "Drift from Original Plan" table; `eval_component` re-runs the provider on every render

## Context

The original dev spec for the statusline library called for a three-scope engine cache (`global` / `buffer` / `window`) keyed by component id, with autocmd-driven invalidation per declared `update` event. This was modeled after heirline's `update` semantics.

During implementation, several bugs surfaced (filetype showing "Lua" after switching to a no-filetype file; components disappearing on the explorer) that turned out to be cache-invalidation bugs — the framework cache held stale fragments because the invalidation logic missed an edge case. The fixes were straightforward but the underlying complexity (three keyed cache tables, `BufWipeout`/`WinClosed` cleanup, `invalidate_component` walking all three tables) added cost without measurable benefit: most providers are very cheap (read a `vim.bo` field, format a string).

A survey of `lualine.nvim` showed it does not cache component results at the framework level either — it re-runs `update_status()` on every render and lets specific components (branch, diff, diagnostics) cache internally with their own invalidation rules.

## Decision

Drop the engine-level result cache. `M.render()` re-runs every visible component on every redraw. `eval_component` only handles `condition` gating + `pcall` error isolation. The `scope` field on component specs is kept as declarative metadata but is no longer consulted by the engine.

Components that genuinely need caching own it themselves:

- `git_branch` caches resolved git_dir + branch internally and uses a `vim.uv.fs_event` watcher on `.git/HEAD` for invalidation
- `git_commit` and other file-bound components cache via `util.file_bound` (see [ADR-011](011-file-bound-provider-wrapper.md))

## Alternatives Considered

- **Keep the three-scope engine cache as originally designed** — rejected after implementation: the bugs we hit were cache-invalidation bugs, not provider-cost bugs. The cache was solving a problem we did not have.
- **Cache only "expensive" components (e.g. git_commit) at the engine level** — rejected: special-casing per component complicates the engine; component-side caching is simpler and gives the component author full control over invalidation.

## Rationale

1. Most providers are cheap: `vim.bo[bufnr].filetype`, `vim.fn.line(".")`, table lookups — caching saves microseconds and adds machinery
2. Component-side caching (`file_bound` closure, libuv watcher) lets each component pick the invalidation rule that fits its data source
3. Lualine demonstrates the same trade-off works in production (re-run on every redraw, components cache when needed)
4. Removes ~80 lines of cache + invalidation code, three keyed tables, and several edge-case bugs
5. Engine code becomes easier to reason about: a render is `condition → provider → fragments`, no hidden state

## Consequences

- **Positive:** Simpler engine (`eval_component` is ~15 lines); no cache-invalidation bugs at the framework level; component authors choose their own caching strategy
- **Negative:** Components that shell out (e.g. `git_commit` calls `vim.fn.system`) must implement their own caching, otherwise they will re-run on every redraw
- **Risks:** If a future component is expensive AND has no obvious invalidation rule, we may need to re-introduce a generic cache. So far `file_bound` covers this case.

## References

- Dev spec: `docs/dev-specs/statusline-library.md` § "Why we dropped the engine cache"
- Code: `lua/beast/libs/statusline/init.lua` — `eval_component`
- Reference: `lua/lualine/component.lua:271-295` — lualine's `draw()` re-runs `update_status()` on every render
- Related ADRs:
  - [ADR-009](009-native-statusline-replaces-heirline.md) — Native `%!` Statusline
  - [ADR-011](011-file-bound-provider-wrapper.md) — file_bound Provider Wrapper
