# ADR-026: Pure `M.get()` Highlight Module Contract

**Status:** Accepted

**Date:** 2026-06-05

**Evidence:** Commits `53b1116` (Util.mod), `8e27575` (M.get refactor + dispatcher); `docs/dev-specs/fast-highlight-reload.md`; `lua/beast/init.lua` (`apply_highlights`, `reload_highlights`); `lua/beast/util/colors.lua` (`build`); all 15 `lua/beast/**/highlights.lua` files.

## Context

Before this change, each `<lib>/highlights.lua` was a script: its top-level body called `Util.colors.set_hl(...)` as a side effect of `require()`. To re-apply on `ColorScheme`, the dispatcher cleared `package.loaded[mod] = nil` and re-required the module, re-running the side effects.

This had two problems:

1. **No way to introspect or batch.** Each module pushed to `nvim_set_hl` directly. The dispatcher couldn't merge groups, couldn't pre-compute, and couldn't cache. Every reload made ~14 separate `set_hl`/`hi! link` round-trips. Cold-path reload was ~1.1 ms.
2. **Side-effect coupling.** Modules that needed redraws (statusline, breadcrumb, tabline) buried `vim.cmd("redrawstatus")` or `icons.clear_cache()` at the top level of their highlight files. Refactoring or caching anything was risky because the side effects were invisible to the dispatcher.

tokyonight.nvim solved a similar problem with a uniform `M.get(colors, opts) -> table` contract and a `Util.mod` loadfile-based loader that bypasses `package.loaded`. We wanted the same shape.

## Decision

Every `<lib>/highlights.lua` exports:

- **`M.get(): table<string, vim.api.keyset.highlight>`** — a pure function returning the highlight groups this module owns. No `nvim_set_hl`, no `redraw*`, no Palette mutation.
- **`M.post_apply?(): nil`** — *optional* hook for non-set_hl side effects (statusline cache clear, tabline icon cache invalidation, redraws).

The central dispatcher in `beast.reload_highlights()`:

1. Iterates `M.highlight_modules`, gated by `package.loaded[parent]` and `is_builtin_colorscheme()`.
2. Loads each module via `Util.mod(name)` (a tokyonight-style `loadfile` loader that bypasses `package.loaded`).
3. Collects every `M.get()` into a single `merged` table.
4. Applies all groups in one `nvim_set_hl` pass.
5. Runs queued `M.post_apply()` hooks.

For lib first-load apply (at `setup()` time, before any `ColorScheme` event), `beast.apply_highlights(mod_name)` runs the same pipeline for a single module. Lib `setup()` calls `require("beast").apply_highlights("X.highlights")` instead of bare `require("X.highlights")`.

Helper `Util.colors.build(prefix, groups)` returns a prefixed table without applying it, so `M.get()` bodies stay declarative:

```lua
function M.get()
  local p = Palette.get()
  return Util.colors.build("BeastExplorer", {
    Normal = { fg = p.text, bg = p.dark1 },
    ...
  })
end
```

## Alternatives Considered

1. **Keep side-effect contract, add caching wrapper around `require`.** Rejected: caching would require sandboxing `nvim_set_hl` calls to capture what each module emits — fragile and slower than a return-value contract.
2. **Return a list of `(group, attrs)` tuples instead of a map.** Rejected: tokyonight uses a map, and merging maps lets later modules override earlier (e.g. palette base groups vs. lib-specific overrides) with `pairs()` semantics that match the previous sequential `set_hl` behavior.
3. **`M.apply()` returns the groups *and* applies them.** Rejected: defeats the purpose. The dispatcher needs the groups *without* application so it can merge/cache/post-process.
4. **Drop `M.post_apply()`, fold every side effect into the dispatcher.** Rejected: the side effects are module-specific (icons.clear_cache is a tabline implementation detail, hlgroup.clear_all is a statusline detail). Putting them in the dispatcher creates a reverse dependency from `beast/init.lua` into every lib's internals.

## Rationale

1. **Single batched apply path.** One `nvim_set_hl` loop replaces ~14 per-module loops + the slow `vim.api.nvim_command("hi! link …")` string parsing. Bench dropped from 1108 µs → 853 µs (~23% faster cold path).
2. **Cache-ready shape.** A future `Util.cache` layer can JSON-serialize `merged` keyed by palette hash — no module changes needed. (Spec Phase 3 was left unimplemented because the cold path already met the < 1 ms target; the shape is preserved if/when the trade-off shifts.)
3. **Side effects are explicit and discoverable.** `grep "post_apply"` lists every module that touches non-highlight state on reload. Future audits no longer have to read every top-level statement of every highlights file.
4. **`Util.mod` bypass.** Phase 1's `Util.mod` loader skips `package.loaded`, so the dispatcher doesn't have to manage cache invalidation per-module. `M.get()` is called fresh every reload — palette refresh propagates immediately without `package.loaded` bookkeeping.
5. **First-apply and ColorScheme refresh share a code path.** `apply_highlights(mod)` is `reload_highlights()` restricted to one module. No second implementation of the get → merge → apply → post_apply pipeline.

## Consequences

- **Positive:**
  - 23 % faster cold reload (1108 → 853 µs); single batched `nvim_set_hl`.
  - Highlight modules are now testable in isolation (`require("X.highlights").get()` returns a plain table).
  - Side effects are explicit (`M.post_apply`) instead of buried in module top-level.
  - Pipeline is cache-ready without further refactoring.
  - Both first-load and ColorScheme refresh go through one code path.
- **Negative:**
  - Each lib's `setup()` must explicitly call `require("beast").apply_highlights(…)` instead of bare `require(…)`. One extra line of glue per lib, but it makes the apply intent visible at the call site.
  - Modules with state-derived highlights (tabline reads `config.appearance`, computes blends) must factor a shared compute function used by both `M.get()` and `M.post_apply()` to stay consistent. Tabline does this with a module-local `compute()` memoized between the two entry points.
- **Risks:**
  - A module that returns a table mutated by reference can corrupt later reloads. Mitigated by always building a fresh table inside `M.get()`.
  - A future module that depends on user-specific options outside `Palette` would break cache assumptions (currently no module does — all colors flow from `Palette`). The cache layer (deferred) would need to widen `inputs` if this changes.

## References

- Commit: `53b1116` — feat(beast): Util.mod loader (Phase 1)
- Commit: `8e27575` — refactor(highlights): uniform M.get() + central dispatcher (Phase 2)
- Dev spec: `docs/dev-specs/fast-highlight-reload.md`
- Inspiration: `tokyonight.nvim` — `lua/tokyonight/util.lua:mod`, `lua/tokyonight/groups/init.lua`
- Related: ADR-008 (Namespaced Highlight Groups Across Libs) — namespace pattern preserved; only the apply mechanism changed.
