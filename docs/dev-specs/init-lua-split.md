# Dev Spec: Split `beast/init.lua` Into Focused Modules

> **Status: Phase 1 shipped (`0e50abe`). Phase 2 + 3 cancelled — 2026-06-05.**
>
> Phase 1 extracted `_G.*` registration + the highlight pipeline into
> `lua/beast/setup/{globals,highlights}.lua`. `init.lua` shrank 358 → 258 lines.
>
> Phase 2 (move `packer.lazy(...)` blocks to `setup/lazy_libs.lua`) and Phase 3
> (move keymaps + orchestrator) were cancelled after profiling showed they are
> pure code-organization with no startup-time impact — the requires would just
> shift files. The real startup-perf wins live elsewhere (eager top-level
> requires of on-demand modules like `packer.ui`); those belong in
> `util-mod-hot-paths.md`.
>
> Phase 1 ships independently and is sufficient as a seam for future highlight
> work. The remaining body of `beast/init.lua` (258 lines, mostly declarative
> `packer.lazy(...)` blocks) is left as one cohesive registration file.

## Summary

`lua/beast/init.lua` is 314 lines and combines six unrelated responsibilities:
config defaults, global registration, key/notify/toast/confirm/packer setup,
declarative lazy-lib registrations, highlight reload pipeline, and the
`ColorScheme` autocmd. Tokyonight's `init.lua` is 26 lines because each
concern lives in its own file. This spec mirrors that split: `init.lua`
becomes a thin entry + re-export, with the body moved to focused siblings
under `lua/beast/setup/`.

Pure refactor, no behaviour change. Enables future specs (e.g.
`util-mod-hot-paths`, `fast-highlight-reload`) to touch one concern at a
time.

## Requirements

- `require("beast").setup(opts)` continues to be the single public entry;
  the result of calling it is byte-identical to before.
- `beast/init.lua` shrinks to ≤ 40 lines: defaults table, type definition,
  `M.setup` dispatch, `M.highlight_modules` + `M.reload_highlights` re-export.
- One concern per file under `lua/beast/setup/`:
  - `setup/init.lua` — orchestrator that calls the siblings in order.
  - `setup/globals.lua` — registers `_G.Util / Palette / Key / Buffer / Icon / Toast`.
  - `setup/lazy_libs.lua` — all `packer.lazy(...)` declarations
    (breadcrumb, tabline, statuscolumn, git, explorer, indent, treesitter,
    finder, scroll, window).
  - `setup/highlights.lua` — `M.highlight_modules` table +
    `reload_highlights` function + the `ColorScheme` autocmd registration.
  - `setup/keymaps.lua` — the handful of global keymaps declared inline today
    (`<leader>d`, `<leader>n`, `<leader>p`, finder keys' starter-row entries).
- `M.highlight_modules` remains accessible as
  `require("beast").highlight_modules` so external callers (and the planned
  `fast-highlight-reload` spec) can keep appending to it.
- Each new file is **independently `require`-able** — no setup file imports
  another at top level; `setup/init.lua` is the only orchestrator.
- Out of scope: changing setup *order*, changing any wiring semantics,
  renaming the global vars, or touching the lib internals.

## Research

### Repo Search

- Searched for: top-level statements in `beast/init.lua`, all
  `packer.lazy(...)` call sites, all `_G.*` assignments, all `safe_set` and
  autocmd registrations in the entry file.
- Found: `lua/beast/init.lua` lines 27-268 are one giant `function M.setup`
  body. Sections are loosely commented (`-- Notification`, `-- Statusline`,
  `-- Breadcrumb / winbar`, `-- Explorer`, etc.) so the natural split lines
  are obvious. `M.highlight_modules` (lines 270-288) and
  `M.reload_highlights` (lines 300-312) are the only members other than
  `M.setup`.
- No other module currently requires `beast` itself (no circular risk).
- Reuse opportunity: `beast/plugins/init.lua` already demonstrates the
  "thin re-export + sibling files" pattern — same shape works here.

### Package Search

- Searched: nothing external needed.
- Decision: **Build** — pure file reorg using existing Lua module conventions.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/init.lua` | **Modify** | Shrink to defaults + `setup` dispatcher + `highlight_modules` re-export. |
| `lua/beast/setup/init.lua` | **Create** | Orchestrator: `function M.run(cfg) ...` calling each sibling in order. |
| `lua/beast/setup/globals.lua` | **Create** | `_G.*` registrations + initial `Palette.setup()`. |
| `lua/beast/setup/keymaps.lua` | **Create** | Inline global keymaps (`<leader>d`, `<leader>n`, `<leader>p`). |
| `lua/beast/setup/lazy_libs.lua` | **Create** | All `packer.lazy(...)` declarations. |
| `lua/beast/setup/highlights.lua` | **Create** | `highlight_modules` registry + `reload_highlights` + ColorScheme autocmd. |

## Implementation Phases

### Phase 1: Move highlight pipeline + globals (smallest cohesive slice)

1. **Create `lua/beast/setup/globals.lua`** (File: `lua/beast/setup/globals.lua`)
   - Action: Move lines 36-44 of `init.lua` (the `require("beast.option")`
     + all `_G.*` assignments + `Palette.setup()`) into `function M.run(cfg)`.
     Return `M`.
   - Why: Globals registration is self-contained and has no dependency on
     lib-specific options.
   - Depends on: None
   - Risk: Low

2. **Create `lua/beast/setup/highlights.lua`** (File: `lua/beast/setup/highlights.lua`)
   - Action: Move `M.highlight_modules` (lines 273-288),
     `builtin_only_highlights` (lines 293-295), `M.reload_highlights`
     (lines 300-312), and the `ColorScheme` autocmd (lines 47-55) into one
     module. Export both `M.highlight_modules` and `M.reload_highlights`.
     Add `function M.setup()` that registers the autocmd.
   - Why: All highlight-refresh concerns in one place; sets up the seam for
     `fast-highlight-reload.md` to land cleanly.
   - Depends on: None
   - Risk: Low

3. **Wire from `beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action: In `M.setup`, replace the moved blocks with calls:
     ```lua
     require("beast.setup.globals").run(cfg)
     local hl = require("beast.setup.highlights")
     hl.setup()
     M.highlight_modules = hl.highlight_modules
     M.reload_highlights = hl.reload_highlights
     ```
   - Why: Keep the public surface (`require("beast").highlight_modules`)
     identical so no caller breaks.
   - Depends on: Steps 1, 2
   - Risk: Low

**Phase 1 ships independently.** `init.lua` drops from 314 → ~240 lines.

### Phase 2: Move lazy lib registrations

4. **Create `lua/beast/setup/lazy_libs.lua`** (File: `lua/beast/setup/lazy_libs.lua`)
   - Action: Move every `packer.lazy(...)` block (lines 94-263) into
     `function M.run(cfg)`. Receive `cfg` so each lazy block can pass
     `cfg.explorer`, `cfg.treesitter`, etc.
   - Why: ~170 of the 314 lines belong here. Easiest single biggest win.
   - Depends on: None
   - Risk: Medium — must preserve the `cfg.starter.keys` mutation that
     happens between lazy registrations (lines 83, 237). Pass `cfg.starter`
     by reference (table) so mutations remain visible to the starter setup.

5. **Wire from `beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action: Replace lines 94-263 with `require("beast.setup.lazy_libs").run(cfg)`.
   - Depends on: Step 4
   - Risk: Low

**Phase 2 ships independently.** `init.lua` drops to ~70 lines.

### Phase 3: Move keymaps + finalise

6. **Create `lua/beast/setup/keymaps.lua`** (File: `lua/beast/setup/keymaps.lua`)
   - Action: Move the four inline `Key.safe_set` calls into
     `function M.run(notify, toast)`. Receive the notify/toast modules so
     `<leader>n`'s closure stays correct.
   - Why: Keymaps belong with their owners; or at least in a labelled file.
   - Depends on: None
   - Risk: Low

7. **Create `lua/beast/setup/init.lua` orchestrator** (File: `lua/beast/setup/init.lua`)
   - Action:
     ```lua
     local M = {}
     function M.run(cfg)
       require("beast.setup.globals").run(cfg)
       require("beast.libs.key").setup(cfg.key)
       local notify = require("beast.libs.notify"); notify.setup(cfg.notify)
       local toast = require("beast.libs.toast"); toast.setup(cfg.toast); _G.Toast = toast
       require("beast.setup.keymaps").run(notify, toast)
       require("beast.libs.confirm").setup()
       require("beast.libs.packer").setup(cfg.packer)
       -- statusline setup (lines 85-91)
       require("beast.setup.lazy_libs").run(cfg)
       require("beast.libs.starter").setup(cfg.starter)
       local hl = require("beast.setup.highlights"); hl.setup()
       Palette.refresh(); hl.reload_highlights()
     end
     return M
     ```
   - Why: All wiring order in one readable file.
   - Depends on: Steps 1, 2, 4, 6
   - Risk: Medium — order must match current `init.lua` exactly.

8. **Shrink `beast/init.lua` to the entry shell** (File: `lua/beast/init.lua`)
   - Action: Final form (~40 lines):
     ```lua
     local M = {}
     local defaults = { ... }                    -- lines 5-24 unchanged
     function M.setup(opts)
       local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
       if not (opts and opts.starter and opts.starter.keys) then cfg.starter.keys = {} end
       require("beast.setup").run(cfg)
       local hl = require("beast.setup.highlights")
       M.highlight_modules = hl.highlight_modules
       M.reload_highlights = hl.reload_highlights
     end
     return M
     ```
   - Why: Tokyonight-shape entry: defaults + dispatch + re-export.
   - Depends on: Step 7
   - Risk: Low

## Testing Strategy

- **Manual verification (each phase)**:
  - `nvim` opens, starter visible, no errors in `:messages`.
  - `:lua =require("beast").highlight_modules` returns the same 14-entry list.
  - `<leader>e`, `<leader>f`, `<leader>p`, `<leader>d`, `<leader>n` all work.
  - `:colorscheme tokyonight` triggers highlight reload (visible refresh).
  - `:checkhealth beast.libs.statusline` clean.
- **Bench (Phase 3 final)**: `scripts/bench-startup.sh` shows no regression
  vs main (within 1 ms median; this is a pure refactor).
- **Diff sanity**: `git diff main -- lua/beast/init.lua | wc -l` after
  Phase 3 shows ~275 lines removed; the lib-internal files are unchanged.

## Risks & Mitigations

- **Risk**: Setup order subtly shifts and breaks `cfg.starter.keys`
  accumulation (lazy libs append to it before starter.setup runs).
  → **Mitigation**: Pass the *same table reference* through every `run(cfg)`
  call; the `lazy_libs.run` block must run **before** `starter.setup`.
  Verified in Step 7's orchestrator order.
- **Risk**: `M.highlight_modules` consumer code (the existing
  `reload_highlights` loop reads it from `M`) breaks if not re-exported.
  → **Mitigation**: Phase 1 explicitly re-exports it on the top-level `M`.
- **Risk**: A lazy block reads `cfg.starter.keys[#cfg.starter.keys + 1] = …`
  which depends on the cfg table being mutable.
  → **Mitigation**: Lua tables are reference types; pass-by-name preserves
  this. Audit Step 4 to confirm no `vim.deepcopy(cfg)` is introduced inside
  `lazy_libs.run`.
- **Risk**: Some lib's `setup()` requires a global that
  `setup/globals.lua` hasn't yet installed. → **Mitigation**: Orchestrator
  (Step 7) calls globals first, exactly as today.

## Success Criteria

- [ ] `lua/beast/init.lua` is ≤ 40 lines.
- [ ] No file under `lua/beast/setup/` exceeds 100 lines.
- [ ] `require("beast").highlight_modules` returns the same list as before.
- [ ] `scripts/bench-startup.sh` median within ±1 ms of main.
- [ ] All keymaps, autocmds, and lazy libs behave identically (manual
      smoke-test checklist above passes).
- [ ] Codemap (`docs/CODEMAPS/architecture.md` *Module Tree* + *Setup Flow*)
      regenerated.

## ADR Required

No — pure refactor. The `setup/` subdirectory pattern is already used by
`beast/plugins/`, so it isn't a novel decision.
