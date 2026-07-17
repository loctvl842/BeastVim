---
name: util-mod-hot-paths
description: "Apply `Util.mod` to Hot Paths Beyond Highlights"
generated: 2026-06-05
---

# Dev Spec: Apply `Util.mod` to Hot Paths Beyond Highlights

## Summary

Tokyonight's `Util.mod` (`loadfile`-based module loader bypassing
`package.path`) gives a small but consistent speed-up on every module load.
The companion spec `fast-highlight-reload.md` introduces it for the
highlight reload pipeline. This spec extends its use to two other hot paths
where `require` is called repeatedly: statusline component dispatch on
every redraw, and finder source dispatch on every picker open.

Depends on `fast-highlight-reload.md` Phase 1 (which introduces `Util.mod`).
Strictly additive — `require` continues to work everywhere; this spec just
swaps it on **measured** hot paths.

## Requirements

- `Util.mod` (from `fast-highlight-reload.md` Phase 1) is available at
  `require("beast.util").mod`.
- Every replacement is paired with a bench number proving it is a hot path
  (no speculative migrations).
- A new helper `Util.lazy_table(prefix)` returns a metatable-backed table
  that lazy-loads `Util.mod(prefix .. "." .. key)` on first access —
  usable as a drop-in for namespace tables like `Components.git_branch`.
- After the spec, the following `require` call sites use `Util.mod`
  (or `Util.lazy_table`):
  - Statusline component dispatch.
  - Finder source loader (`require("beast.libs.finder.sources." .. name)`).
- **Out of scope**: rewriting any logic, changing public APIs, touching
  highlights (covered by `fast-highlight-reload.md`).

## Research

### Repo Search

- Searched for: `require\(.*statusline\.components`, `require\(.*finder`,
  hot `require` calls inside render/redraw loops.
- Found:
  - `lua/beast/libs/statusline/components/init.lua` exports each component
    via `require("...components.git_branch")` etc. Currently loaded once
    when `stl.setup({...})` is called at startup. Any unused component
    still gets loaded if it is referenced in the namespace table.
  - `lua/beast/libs/finder/init.lua` is only 23 lines — most logic
    delegates to siblings. `finder/sources/*.lua` (if present) loads on
    every `open(source)`.
  - `lua/beast/palette/init.lua` is a single file with no per-theme
    dispatch — **no hot path here, palette dropped from spec**.
- Reuse opportunity: **Adopt** `Util.mod` (introduced by sibling spec); add
  a small `Util.lazy_table` helper that wraps it in a metatable for the
  components namespace.

### Package Search

- Searched: nothing external — `Util.mod` is the only primitive needed.
- Decision: **Use native** (built on `loadfile` + `debug.getinfo`).

### Bench Baselines (must run before Phase 1)

Each migration target requires a "before" number from existing benches:

| Target | Bench | Threshold to justify migration |
|---|---|---|
| Statusline component dispatch | `scripts/bench-statusline.lua` | If `require` time > 5 % of per-render median, OR cold first-render shows ≥ 50 µs win |
| Finder source load | new `scripts/bench-finder-open.lua` | If module-load time > 500 µs cold |

If a target does not meet its threshold, **drop it from the spec**. Don't
migrate speculatively.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/util/init.lua` | **Modify** | Add `Util.lazy_table(prefix)` helper. |
| `lua/beast/libs/statusline/components/init.lua` | **Modify** | Replace per-component `require` with `Util.lazy_table("beast.libs.statusline.components")`. |
| `lua/beast/libs/finder/init.lua` (or `finder/sources/init.lua` if it exists) | **Modify** | Use `Util.mod` for source dispatch. |
| `scripts/bench-statusline.lua` | **Modify** | Add cold + warm runs showing before/after for the component dispatch path. |
| `scripts/bench-finder-open.lua` | **Create** | Measure cold open of `<leader>f` / `<leader>b` etc. |

## Implementation Phases

### Phase 0: Measure (mandatory — no code yet)

1. **Baseline benches** (no file changes)
   - Action: Run `scripts/bench-statusline.lua` on `main`. Create
     `scripts/bench-finder-open.lua` that times the first `require` of
     each source module. Record median + p95 for each.
   - Why: Each migration in Phase 1 must be justified by a real number.
     Without baseline data, this spec becomes speculative.
   - Risk: None (read-only)

### Phase 1: `Util.lazy_table` helper

2. **Add `Util.lazy_table(prefix)`** (File: `lua/beast/util/init.lua`)
   - Action:
     ```lua
     function M.lazy_table(prefix)
       return setmetatable({}, {
         __index = function(t, k)
           local mod = M.mod(prefix .. "." .. k)
           rawset(t, k, mod)
           return mod
         end,
       })
     end
     ```
   - Why: Pattern from tokyonight's `M.styles` (`colors/init.lua:6-10`).
     Stores resolved modules on the table so the metatable fires once per
     key, then becomes a normal lookup.
   - Depends on: `fast-highlight-reload.md` Phase 1 (`Util.mod` exists)
   - Risk: Low

### Phase 2: Statusline component dispatch

3. **Lazy-table the components namespace**
   (File: `lua/beast/libs/statusline/components/init.lua`)
   - Action: Replace the manual `M.git_branch = require("...")` style
     table with `return Util.lazy_table("beast.libs.statusline.components")`.
     Components used at startup (passed into
     `stl.setup({ left = { cpn.git_branch, … } })`) will trigger their
     first load there; unused components stay unloaded.
   - Why: Removes per-startup loading of components the user hasn't
     enabled; mirrors tokyonight's `groups/init.lua` plugin auto-detection.
   - Depends on: Step 2
   - Risk: Medium — if any caller iterates the table
     (`for k, v in pairs(cpn)`), the metatable won't populate keys.
     Audit before changing. Today only direct field access (`cpn.git_branch`)
     is used.

4. **Re-bench** (File: `scripts/bench-statusline.lua`)
   - Action: Re-run the bench from Phase 0. Compare. Must show no
     regression in render path; expect small startup win (proportional to
     # unused components).
   - Depends on: Step 3

### Phase 3: Finder source dispatch (only if Phase 0 justifies it)

5. **Use `Util.mod` for source loading** (File: `lua/beast/libs/finder/init.lua`)
   - Action: Wherever `require("beast.libs.finder.sources." .. name)` is
     called inside `open(source, opts)`, replace with
     `Util.mod("beast.libs.finder.sources." .. name)`.
   - Why: First `<leader>f` press shaves the path-scan cost.
   - Depends on: Phase 0 numbers justify
   - Risk: Low

## Testing Strategy

- **Bench (mandatory)**:
  - `scripts/bench-statusline.lua` — cold first-render + warm steady-state.
    Must be ≤ baseline.
  - `scripts/bench-finder-open.lua` — cold first-open. Must show
    measurable improvement (≥ 100 µs) to keep Phase 3.
- **Manual verification**:
  - Statusline renders all configured components identically; trigger a
    redraw (`:redrawstatus`) and confirm.
  - `<leader>f`, `<leader>b`, `<leader>/`, `<leader>h` all open the finder
    with correct results.
  - `:lua for k, _ in pairs(require("beast.libs.statusline.components")) do print(k) end`
    — confirm whether any caller iterates this table (if yes, revisit Step 3).

## Risks & Mitigations

- **Risk**: A caller iterates `cpn` (the components namespace) expecting
  all keys present. Lazy table won't populate via `pairs`.
  → **Mitigation**: Audit before Phase 2
  (`git grep -nE "pairs.*components|ipairs.*components" lua/`). If found,
  add an explicit `M.list = { "git_branch", "mode", … }` array for
  iteration.
- **Risk**: `loadfile` failure becomes a runtime error instead of a
  `require` error (slightly different format).
  → **Mitigation**: `Util.mod` already asserts; messages remain
  identifiable as Beast errors.
- **Risk**: Phase 0 numbers come back tiny and the spec stops being worth
  the change. → **Mitigation**: Explicit "drop targets that don't meet
  threshold" rule. Honest no-op > false win.

## Success Criteria

- [ ] `Util.lazy_table` exists and is used by
      `statusline/components/init.lua`.
- [ ] `scripts/bench-statusline.lua` warm-render median is ≤ baseline.
- [ ] `scripts/bench-statusline.lua` cold first-render shows measurable
      improvement (≥ 50 µs) OR the change is rolled back.
- [ ] No `pairs(components)` callers broken.
- [ ] Visual parity for statusline + finder.

## ADR Required

The `Util.lazy_table` helper introduces a new shared shape — a
metatable-backed namespace that lazy-loads on access. Worth a small ADR
("Lazy namespace tables for module dispatch") so future modules know to
reuse this instead of inventing their own metatable each time.
