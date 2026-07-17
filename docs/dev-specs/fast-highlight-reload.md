# Dev Spec: Fast Highlight Reload Pipeline

> **Status: Completed (Phase 1 + 2) — 2026-06-05.** Phase 3 (JSON cache) intentionally **skipped**.
> Cold-path reload landed at **853 µs** (baseline 1108 µs, target < 1 ms), so the
> warm-path cache investment was not justified versus its stale-cache risks. The
> dispatcher shape is cache-ready if/when the trade-off shifts. See ADR-026.
>
> Commits: `53b1116` (Phase 1 — Util.mod), `8e27575` (Phase 2 — M.get + dispatcher).

## Summary

Adopt two patterns from `tokyonight.nvim` to make BeastVim's `ColorScheme` refresh
cheaper and self-cacheable:

1. **`Util.mod`** — `loadfile`-based module loader that bypasses Lua's
   `package.path` scan, used by tokyonight for every palette + plugin-group file.
2. **Uniform `M.get() → table` contract for highlights + JSON cache** —
   each `<lib>/highlights.lua` returns a pure highlight table instead of calling
   `Util.colors.set_hl` at top level. The dispatcher in `beast/init.lua` merges
   the tables and caches the merged result keyed by `(colors_name, palette hash,
   version)` so subsequent `:colorscheme` switches between cached themes skip
   all per-lib work and run one `nvim_set_hl` loop from JSON.

Today every `reload_highlights()` re-`require`s ~14 modules; each one calls
`Palette.get()` (which calls `nvim_get_hl` for ~15 source groups) and runs its
own `Util.colors.set_hl` loop. There is no caching layer.

## Requirements

- `Util.mod(modname)` returns the same table `require` would, but uses
  `loadfile` from an absolute path computed once from `debug.getinfo(1,"S").source`.
- Every `<lib>/highlights.lua` exports `function M.get(): table<string, vim.api.keyset.highlight|{link=string}>`
  with **no top-level side effects** (no `set_hl`, no `redrawstatus`, no `require("beast.palette").get()` outside `M.get`).
- The dispatcher in `beast.reload_highlights()` merges every enabled module's
  `M.get()` into one flat table and applies it via a single
  `for group, hl in pairs(...) do nvim_set_hl(0, group, hl) end` loop.
- A JSON cache file at `stdpath("cache") .. "/beast-hl-<colors_name>.json"`
  stores `{ inputs = {...}, groups = {...} }`. Cache hit ⇒ skip every
  `M.get()` call and `Palette.refresh()` recomputation; apply groups directly.
- Cache invalidation key includes: `colors_name`, a hash of the resolved
  `Palette.get()` table, the registered module name list, and a manual `version`
  integer (bumped when the dispatcher or any contract changes).
- The existing `Palette.is_builtin_colorscheme()` gating for
  `beast.libs.treesitter.highlights` is preserved.
- `Util.colors.set_hl(prefix, groups)` keeps working — the dispatcher
  produces fully-prefixed group names by calling each module's `M.get()` (which
  internally still composes its prefix). Migration is mechanical, not semantic.
- **Out of scope**: changing palette extraction logic; touching individual
  highlight values; rewriting `Util.colors.set_hl` itself; lazy-loading
  highlights on first use (still applied eagerly post-`ColorScheme`).

## Research

### Repo Search

- Searched for: `require\("beast\.libs.*highlights"\)`, `M\.apply`, `M\.get`,
  `package\.loaded.*highlights`, top-level `Util.colors.set_hl` calls.
- Found:
  - `lua/beast/init.lua:273-311` — `M.highlight_modules` (14 entries) and
    `M.reload_highlights()` that does `package.loaded[m] = nil; pcall(require, m)`.
  - Every `lua/beast/libs/*/highlights.lua` calls `Palette.get()` and
    `Util.colors.set_hl(...)` at **module load time** (top-level statements).
    `statusline/highlights.lua` additionally calls `vim.cmd("redrawstatus")`.
  - `lua/beast/util/init.lua` (25 lines) exposes `Util.wo`, `Util.create_scratch_buf`,
    `Util.hrtime`. No module-loader helper exists.
  - `lua/beast/util/colors.lua:143` — `Util.colors.set_hl(prefix, groups)`
    iterates a `{ Name = {fg=…} }` table; it's already the shape the new
    `M.get()` will return.
- Reuse opportunity:
  - **Adopt** `Util.colors.set_hl` as-is — the dispatcher can keep using it
    per-module when there is no cache hit. Only the cache-applier needs to
    inline the loop (groups in cache are already fully prefixed).
  - **Extract first** — `M.highlight_modules` registry already exists; the
    refactor formalises its contract.

### Package Search

- Searched: `vim.json`, `vim.uv`/`vim.loop`, `loadfile`, `vim.deep_equal`,
  `debug.getinfo`.
- Found:
  - `vim.json.encode`/`vim.json.decode` — built-in, what tokyonight uses.
  - `vim.deep_equal` — built-in, used by tokyonight for cache input matching.
  - `loadfile` + `debug.getinfo(1,"S").source:sub(2)` — Lua/Neovim primitives.
  - `vim.uv.fs_unlink` — built-in, for `cache.clear()`.
- Decision: **Use native** for everything. No new dependency. Pattern is a
  direct port of `tokyonight/util.lua:18-25` (Util.mod) and
  `tokyonight/util.lua:140-167` + `tokyonight/groups/init.lua:139-163` (cache).

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/util/init.lua` | **Modify** | Add `Util.mod(modname)` lazy loader. |
| `lua/beast/util/cache.lua` | **Create** | JSON `read/write/clear/file(key)` helpers for highlight cache. |
| `lua/beast/libs/breadcrumb/highlights.lua` | **Modify** | Convert top-level body into `function M.get()`; return groups table. |
| `lua/beast/libs/confirm/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/explorer/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/finder/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/git/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/indent/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/key/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/notify/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/packer/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/statuscolumn/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/statusline/highlights.lua` | **Modify** | Same; move `redrawstatus` out (dispatcher handles it once). |
| `lua/beast/libs/tabline/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/toast/highlights.lua` | **Modify** | Same. |
| `lua/beast/libs/treesitter/highlights.lua` | **Modify** | Same; remains gated by `Palette.is_builtin_colorscheme()`. |
| `lua/beast/palette/highlights.lua` | **Modify** | Same. |
| `lua/beast/init.lua` | **Modify** | Rewrite `reload_highlights()` to use `Util.mod` + dispatcher + cache. Replace eager `_G.*` requires with `Util.mod`. |
| `scripts/bench-highlight-reload.lua` | **Create** | Bench the ColorScheme refresh path. |

## Implementation Phases

### Phase 1: `Util.mod` — Standalone fast loader

Ships independently. Provides a small constant speed-up on the eager
`_G.*` block and on `reload_highlights()` even before the cache lands.

1. **Add `Util.mod(modname)`** (File: `lua/beast/util/init.lua`)
   - Action: At top of the file, compute `local root = vim.fn.fnamemodify(debug.getinfo(1,"S").source:sub(2), ":h:h:h")` (resolves to the `lua/` directory). Add:
     ```lua
     function M.mod(modname)
       local cached = package.loaded[modname]
       if cached then return cached end
       local path = root .. "/" .. modname:gsub("%.", "/") .. ".lua"
       local ret = assert(loadfile(path))()
       package.loaded[modname] = ret
       return ret
     end
     ```
   - Why: Bypass `package.path` scan; one `stat` + one `read` per module.
   - Depends on: None
   - Risk: Low — falls through to `require` semantics on `loadfile` failure (assert ensures loud error).

2. **Use `Util.mod` for the eager globals + reload loop** (File: `lua/beast/init.lua`)
   - Action: Replace `require("beast.util")`, `require("beast.palette")`,
     `require("beast.libs.key")`, `require("beast.libs.view")`,
     `require("beast.icon")` in the `_G.*` block with `Util.mod(...)`.
     Note: `Util` itself must still be loaded via plain `require` once first
     (chicken-and-egg). Then inside `reload_highlights()`, replace
     `pcall(require, mod_name)` with `pcall(Util.mod, mod_name)`.
   - Why: Removes ~5 `package.path` scans per startup and 1 per highlight
     module per reload.
   - Depends on: Step 1
   - Risk: Low

3. **Verify with bench** (File: `scripts/bench-highlight-reload.lua`)
   - Action: Create a tiny bench that records `vim.uv.hrtime()` around
     `M.reload_highlights()` for 100 iterations and prints
     median/p95 µs. Pattern mirrors `scripts/bench-statusline.lua`.
   - Why: Establish a baseline for Phase 2/3 to beat.
   - Depends on: Step 2
   - Risk: Low

**Phase 1 ships as a commit.** Behaviour is identical; only the loader changes.

### Phase 2: Uniform `M.get()` contract — Refactor without caching yet

Mechanical refactor. Behaviour identical post-phase; enables Phase 3.

4. **Refactor each highlight module to `M.get()`** (Files: all 15 `*/highlights.lua` listed above)
   - Action: Wrap the existing top-level body in `function M.get()`,
     replacing the `Util.colors.set_hl(prefix, groups)` call with
     `local prefix = "BeastFoo"; local out = {}; for name, def in pairs(groups) do out[prefix..name] = def end; return out`.
     Keep `link = "X"` entries — they stay as `{ link = "X" }` in the returned
     table. Move the `Palette.get()` call inside `M.get` so it isn't invoked
     at module-load time.
   - For `statusline/highlights.lua` specifically: remove the top-level
     `vim.cmd("redrawstatus")` and `hlgroup.clear_all()` — these become a
     side-effect the dispatcher invokes after applying highlights (see Step 5).
   - For `treesitter/highlights.lua` (208 lines): same wrap; the dispatcher's
     `is_builtin_colorscheme()` gate continues to skip it.
   - Why: Pure return value lets the dispatcher merge once, cache once, and
     apply once.
   - Depends on: None (independent of Phase 1)
   - Risk: Medium — statusline post-apply hooks must be replicated.

5. **Dispatcher: collect-then-apply** (File: `lua/beast/init.lua`)
   - Action: Rewrite `M.reload_highlights()`:
     ```lua
     local merged = {}
     for _, mod_name in ipairs(M.highlight_modules) do
       -- existing skip-when-parent-not-loaded + builtin-only gates
       local mod = Util.mod(mod_name)
       if mod and mod.get then
         for g, hl in pairs(mod.get()) do merged[g] = hl end
       end
     end
     for g, hl in pairs(merged) do vim.api.nvim_set_hl(0, g, hl) end
     -- Post-apply hooks (formerly top-level side-effects)
     pcall(function() require("beast.libs.statusline.hlgroup").clear_all() end)
     vim.schedule(function() pcall(vim.cmd, "redrawstatus") end)
     ```
   - Why: One merge loop, one `nvim_set_hl` loop, deterministic ordering
     (later modules can override earlier ones, same as current pseudo-order).
   - Depends on: Step 4
   - Risk: Medium — must preserve the secure-mode `vim.schedule` wrapper for
     `redrawstatus` (statusline relies on `vim.schedule` to avoid E12 in
     secure mode).

6. **Re-run bench** (File: `scripts/bench-highlight-reload.lua`)
   - Action: Confirm no regression vs Phase 1. Expect small improvement
     from the single `nvim_set_hl` loop.
   - Depends on: Step 5

**Phase 2 ships as a commit.** Cache layer not yet active.

### Phase 3: JSON cache — The actual startup win

7. **Add `Util.cache`** (File: `lua/beast/util/cache.lua`)
   - Action: New module:
     ```lua
     local M = {}
     local uv = vim.uv or vim.loop
     local function path(key) return vim.fn.stdpath("cache").."/beast-hl-"..key..".json" end
     function M.read(key)  -- pcall + io.open + vim.json.decode (luanil object+array)
     function M.write(key, data)  -- pcall + io.open w+ + vim.json.encode
     function M.clear()  -- iterate known keys + uv.fs_unlink
     return M
     ```
   - Why: Mirrors `tokyonight/util.lua:140-167`. Built-in JSON only.
   - Depends on: None
   - Risk: Low

8. **Add `Palette.hash()`** (File: `lua/beast/palette/init.lua`)
   - Action: Add `function M.hash() return vim.json.encode(M.get()) end`
     (the palette table is small and order-stable enough; alternatively
     concatenate sorted keys+values into a single string).
   - Why: Cache key must change when palette resolution changes (e.g. user
     switched between two tokyonight variants that share `colors_name` root).
   - Depends on: None
   - Risk: Low — palette table is ~15 short hex strings.

9. **Plug cache into dispatcher** (File: `lua/beast/init.lua`)
   - Action: Wrap the Phase 2 dispatcher with cache check:
     ```lua
     local Cache = Util.mod("beast.util.cache")
     local key = vim.g.colors_name or "default"
     local inputs = {
       scheme  = key,
       palette = Palette.hash(),
       modules = M.highlight_modules,        -- list itself is the contract
       builtin = Palette.is_builtin_colorscheme(),
       version = 1,
     }
     local cached = Cache.read(key)
     if cached and vim.deep_equal(cached.inputs, inputs) then
       for g, hl in pairs(cached.groups) do vim.api.nvim_set_hl(0, g, hl) end
     else
       -- Phase 2 collect-then-apply loop, then:
       Cache.write(key, { inputs = inputs, groups = merged })
     end
     -- Post-apply hooks unchanged
     ```
   - Why: Cache hit collapses ~14 module loads + ~14 `Palette.get()` calls
     + per-module set_hl loops into one JSON decode + one `nvim_set_hl` loop.
   - Depends on: Steps 5, 7, 8
   - Risk: Medium — stale cache after manual highlight edits during dev;
     mitigated by `Util.cache.clear()` exposed for `:lua`.

10. **Expose `:BeastHlCacheClear`** (File: `lua/beast/init.lua`)
    - Action: `vim.api.nvim_create_user_command("BeastHlCacheClear", function() Util.mod("beast.util.cache").clear() end, {})`.
    - Why: Escape hatch for the user when editing highlights locally.
    - Depends on: Step 7
    - Risk: Low

11. **Bench cache-hit vs cache-miss** (File: `scripts/bench-highlight-reload.lua`)
    - Action: Two bench runs: cold (cache deleted before each iteration) and
      warm. Report median µs for both.
    - Depends on: Step 9

## Testing Strategy

- **Bench**: `scripts/bench-highlight-reload.lua` reports
  median/p95 µs for `reload_highlights()` cold + warm.
- **Manual verification**:
  - `:colorscheme tokyonight` → reload triggers, all `Beast*` groups visible
    in `:hi BeastExplorer*` etc.
  - `:colorscheme monokai-pro` → switch, then back to `tokyonight` →
    second switch should be a cache hit (delete the cache file once, observe
    re-write; second switch reads it back).
  - `:BeastHlCacheClear` then `:colorscheme tokyonight` → cache rebuilt.
  - `:checkhealth beast.libs.statusline` clean.
  - Open explorer, finder, key popup, notify, toast — visual parity with main.
- **Unit tests**: `tests/` is currently empty; out of scope for this spec
  (would be its own dev spec for the testing harness).

## Risks & Mitigations

- **Risk**: A highlights module relies on its top-level side-effects firing at
  `require` time (e.g. statusline's `redrawstatus`). → **Mitigation**: Phase 2
  explicitly relocates statusline's `hlgroup.clear_all()` + `redrawstatus`
  into the dispatcher's post-apply hook. Audit each of the 15 files for any
  other side-effects before Phase 2 merge.
- **Risk**: JSON cache stale after the user edits a `*/highlights.lua` file.
  → **Mitigation**:   Bump `version` in the cache `inputs` when the contract
  changes; expose `:BeastHlCacheClear`.
- **Risk**: `Palette.hash()` not stable across runs (table iteration order).
  → **Mitigation**: Sort keys before serialising — `local k = vim.tbl_keys(p); table.sort(k); …`.
- **Risk**: `Util.mod` breaks when a module isn't a real file path (e.g.
  loaded via `package.preload`). → **Mitigation**: `assert(loadfile(path))`
  errors loudly during dev; fallback isn't needed for Beast's own modules
  which all live under `lua/beast/**`.
- **Risk**: Cache hit applies stale highlights when a lib's `M.get()` depends
  on something outside `inputs` (e.g. user-specific options). → **Mitigation**:
  Today no Beast highlight module reads from user opts — all colors come
  from `Palette`. Document this contract in the ADR that lands with this spec.

## Success Criteria

- [ ] `Util.mod("beast.palette")` returns the same table as `require("beast.palette")`.
- [ ] Every `<lib>/highlights.lua` exposes `M.get(): table` with no top-level side-effects.
- [ ] `bench-highlight-reload.lua` cold-path median is no worse than the pre-spec baseline (no regression).
- [ ] `bench-highlight-reload.lua` warm-path (cache hit) median is **< 1 ms** on the developer's machine.
- [ ] Cache file `~/.cache/nvim/beast-hl-<scheme>.json` is created on first reload and re-read on the next reload.
- [ ] `:BeastHlCacheClear` deletes all `beast-hl-*.json` files.
- [ ] Visual parity: explorer, finder, statusline, tabline, notify, toast, key popup, git preview all unchanged.
- [ ] Codemap regenerated (`docs/CODEMAP/architecture.md` *ColorScheme Refresh Pipeline* section updated).

## ADR Required

This dev spec introduces two architectural shapes worth ADRs once committed:

- **Highlight Module Contract** — `<lib>/highlights.lua` exports
  `M.get(): table<string, hl>` with no side-effects. Establishes a new
  uniform pattern for all libs.
- **Highlight Resolution Cache** — JSON cache layer keyed by
  `(colors_name, palette hash, module list, version)`. New on-disk artifact
  under `stdpath("cache")`; needs to be documented alongside other cache
  files Beast produces.
