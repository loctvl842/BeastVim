---
name: breadcrumb-init
description: "Beast Breadcrumb (Winbar) Library"
generated: 2026-05-25
---

# Summary

Native winbar library at `lua/beast/libs/breadcrumb/` that replaces the heirline-based
winbar at `lua/beast/plugins/bars/winbar/`. Renders via Neovim's `%!` evaluation model
(`vim.o.winbar = "%!v:lua.require'beast.libs.breadcrumb'.render()"`), following the same
architecture as the statusline and tabline libraries.

The breadcrumb bar is the **entire winbar** — it shows the filepath (directory segments
with separator, file icon, filename, modified flag). Later (out of scope) it will also
show LSP document symbols after the filepath.

User's example output:
```
lua  beast  plugins  bars  winbar  󰢱 init.lua   DefaultWinbar   [2]
```

**Phase 1** implements filepath-only rendering. LSP breadcrumbs are a separate dev spec.

**Public API:**

```lua
local breadcrumb = require("beast.libs.breadcrumb")
breadcrumb.setup({
    separator = "  ",
    ignored_filetypes = { ... },
})
```

# Requirements

### Functional

- Render winbar via `%!v:lua.require'beast.libs.breadcrumb'.render()`
- Display: `[dir1] [sep] [dir2] [sep] ... [sep] [icon] [filename] [modified_flag]`
- Directory segments shown relative to project root (`Util.root()`)
- File icon from `nvim-web-devicons` with correct color highlight
- Modified indicator (``) when buffer has unsaved changes
- Separator between path segments (default: `  ` — chevron right)
- Respect `g:statusline_winid` for per-window evaluation (winbar is per-window)
- Hide on transient beast-* UI buffers (explorer, finder, confirm, etc.) and special
  buftypes (nofile, prompt, help, quickfix, terminal)
- Cache per window — only recompute on `BufEnter`, `BufModifiedSet`, `BufWritePost`
- ColorScheme refresh via `highlight_modules` registry

### Non-Functional

- Render path must be cheap: `g:statusline_winid` lookup → cache check → string return.
  No I/O on the render path. Path computation happens once per buffer entry.
- Reuse `statusline/hlgroup.lua` for highlight group management (already palette-aware,
  dedup by hash, no statusline-specific logic)
- Follow BeastVim library conventions: state only in `init.lua`, frozen-config metatable,
  lazy autocmd registration, `Beast.Breadcrumb.*` types
- **Performance**: use tabline's dirty-flag + full-output-string cache pattern (not
  statusline's per-component fragment cache). Breadcrumb is one piece of content per
  window — a per-window `{ bufnr, output }` cache with dirty invalidation gives
  < 1 µs hot path. This is the right model because:
  - Winbar is per-window (like statusline) but its content is simple (like a single tabline cell)
  - No fragment/component abstraction needed — direct string assembly
  - Tabline bench shows dirty-flag cache hits at < 1 µs

### Out of Scope

- LSP breadcrumbs / document symbols (separate dev spec, requires LSP infrastructure)
- Click handlers on path segments (future enhancement)
- Truncation of long paths (paths in BeastVim configs are short; add when needed)
- Wiring into `lua/beast/init.lua` — owned by the user

# Research

### Repo Search

- Searched for: `winbar`, `breadcrumb`, `navic`, `g:statusline_winid`, `hlgroup`
- Found:
  - `lua/beast/plugins/bars/winbar/` — existing heirline-based winbar with filepath + LSP
    via nvim-navic. The `components.lua` has the filepath logic (root-relative path, icon,
    modified flag) which we rebuild natively. The naming is wrong there: "filepath" and
    "breadcrumbs" are separate components, but breadcrumb IS the whole bar.
  - `lua/beast/libs/statusline/` — established native `%!` bar pattern
  - `lua/beast/libs/tabline/` — dirty-flag + full-output cache pattern (adopted here)
  - `lua/beast/libs/statusline/hlgroup.lua` — shared highlight group manager:
    `ensure(spec)` takes `{fg, bg, bold, ...}` or string, creates/caches deterministic
    `BeastStl_<hash>` groups. Has zero statusline-specific logic despite living under
    `statusline/`. Cross-requiring is fine for now.
  - `lua/beast/libs/statusline/util.lua` — `IGNORED_FILETYPES` set (same buffers we skip)
  - `Util.root()` — project root resolver
  - `Util.wo()` — version-compat window-option setter

### Optimization Patterns Adopted

| From | Technique | Why |
|------|-----------|-----|
| Tabline | Dirty-flag + full-output string cache | One content piece per window; hot path is 3-field check |
| Tabline | Event-driven invalidation via autocmds | Only recompute when buffer actually changes |
| Statusline | `hlgroup.ensure()` for highlight groups | Dedup, palette-aware, hash-based naming |
| Statusline | `g:statusline_winid` context pattern | Correct per-window target resolution |
| Tabline | `WinClosed` cache cleanup | Prevent unbounded cache growth |
| Tabline | Icon lookup via `pcall(require, "nvim-web-devicons")` | Graceful fallback when devicons unavailable |

### Package Search

- Searched: Neovim native API for winbar
- Found: `vim.o.winbar` evaluated like `statusline` per `:h winbar`. Uses same
  `g:statusline_winid`. Same `%#Group#text%*` syntax. Refresh via `:redrawstatus`.
  Width = `nvim_win_get_width(target_win)` (per-window, NOT `vim.o.columns`).
- Decision: **Use native** — `%!v:lua` expression, no plugins needed.

# Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/breadcrumb/config.lua` | Create | Defaults, live cfg, `setup()` — § *Config Pattern* |
| `lua/beast/libs/breadcrumb/context.lua` | Create | Per-render context from `g:statusline_winid` |
| `lua/beast/libs/breadcrumb/filepath.lua` | Create | Compute filepath format string (dir segments, icon, filename, modified) |
| `lua/beast/libs/breadcrumb/highlights.lua` | Create | `BeastBc*` highlight groups, ColorScheme refresh hook |
| `lua/beast/libs/breadcrumb/init.lua` | Create | Public API: `setup()`, `render()`, state owner, autocmds |
| `scripts/bench-breadcrumb.lua` | Create | Headless render benchmark |

# Implementation Phases

### Phase 1: Core Breadcrumb Library — Filepath rendering with per-window caching

1. **Create `config.lua`** (File: `lua/beast/libs/breadcrumb/config.lua`)
   - Action: Define `Beast.Breadcrumb.Config` with `separator`, `ignored_filetypes` (map),
     `ignored_buftypes` (map). Read-only config metatable pattern matching
     `statusline/config.lua` and `tabline/config.lua`.
   - Why: Every lib needs config first; other modules read `config.separator` etc. inline.
   - Depends on: None
   - Risk: Low

2. **Create `context.lua`** (File: `lua/beast/libs/breadcrumb/context.lua`)
   - Action: Build `Beast.Breadcrumb.Context` from `g:statusline_winid`. Fields: `winid`,
     `bufnr`, `is_active`, `width`, `filetype`, `buftype`, `bufname`. Width uses
     `nvim_win_get_width(target_win)` — winbar is per-window, not global like `laststatus=3`.
     Fallback to `nvim_get_current_win()` when `g:statusline_winid` is nil/invalid.
   - Why: Correct target-window resolution is critical for per-window winbar.
   - Depends on: None
   - Risk: Low

3. **Create `filepath.lua`** (File: `lua/beast/libs/breadcrumb/filepath.lua`)
   - Action: Pure function `M.render(ctx, separator)` returning a statusline format string.
     - Split `bufname` relative to `Util.root()` into directory segments
     - Each dir segment: `%#BeastBcDir#segment%*` + `%#BeastBcSep#<sep>%*`
     - File icon via `pcall(require, "nvim-web-devicons")` → `hlgroup.ensure({fg=color})`
     - Filename: `%#BeastBcFile#name%*`
     - Modified flag: `%#BeastBcModified#%*` when `vim.bo[ctx.bufnr].modified`
     - Files outside root: show filename only (no directory path)
     - Unnamed buffers: return `""` (winbar hides)
   - Why: Core rendering logic. Stateless — receives context, returns string.
   - Depends on: Steps 1, 4 (highlight groups)
   - Risk: Low

4. **Create `highlights.lua`** (File: `lua/beast/libs/breadcrumb/highlights.lua`)
   - Action: Define palette-aware highlight groups using `Palette.get()`:
     - `BeastBcDir` — dimmed directory text
     - `BeastBcSep` — dimmed separator
     - `BeastBcFile` — filename text (slightly brighter)
     - `BeastBcModified` — modified indicator (accent color)
     Clear `hlgroup` cache via `hlgroup.clear_all()` and `redrawstatus` on re-require
     (same pattern as `statusline/highlights.lua`).
   - Why: ColorScheme refresh hook for `highlight_modules` registry.
   - Depends on: None
   - Risk: Low

5. **Create `init.lua`** (File: `lua/beast/libs/breadcrumb/init.lua`)
   - Action: Module-level state owns:
     - `cache`: `table<integer, { bufnr: integer, modified: boolean, output: string }>` keyed by winid
     - `augroup`: integer (lazy autocmd guard)
     `setup(opts)`: merge config, reset cache, register autocmds, set
     `vim.o.winbar = "%!v:lua.require'beast.libs.breadcrumb'.render()"`.
     `render()`:
     1. Build context from `g:statusline_winid`
     2. Early return `""` if ignored filetype/buftype
     3. Check cache: hit if `cache[winid].bufnr == ctx.bufnr` and
        `cache[winid].modified == vim.bo[ctx.bufnr].modified`
     4. Miss: call `filepath.render(ctx, config.separator)`, store in cache
     5. Return cached string
     Autocmds (in `ensure_autocmds()`):
     - `BufEnter`: invalidate cache for the entering window → `redrawstatus`
     - `BufModifiedSet`, `BufWritePost`: invalidate all cache entries for that bufnr → `redrawstatus`
     - `WinClosed`: clean up cache entry for closed window
   - Why: Orchestrates everything. State ownership in `init.lua` per § *State Ownership*.
   - Depends on: Steps 1–4
   - Risk: Medium — cache invalidation must cover buf switch, file save, modified toggle

6. **Create `bench-breadcrumb.lua`** (File: `scripts/bench-breadcrumb.lua`)
   - Action: Headless benchmark following the bench contract. Measure hot (cached) and
     cold (invalidated) render times. Stub `Palette` and `Util` globals.
   - Why: Performance verification against targets.
   - Depends on: Step 5
   - Risk: Low

# Testing Strategy

- **Bench**: `scripts/bench-breadcrumb.lua` — `nvim --clean --headless -l scripts/bench-breadcrumb.lua`
  - Hot (cached): target < 10 µs
  - Cold (recompute): target < 50 µs
  - Fail threshold: 1000 µs (1 ms)
- **Manual verification**:
  1. Open a deep Lua file → winbar shows `dir1  dir2  ...  󰢱 filename.lua`
  2. Modify buffer → `` appears after filename
  3. Save → `` disappears
  4. Switch to beast-explorer → winbar disappears
  5. Open second split → each window shows its own breadcrumb
  6. Change colorscheme → highlights refresh
  7. Open file outside project root → filename only, no directory segments
  8. Open `[No Name]` buffer → winbar hidden

# Risks & Mitigations

- **Risk**: `hlgroup.lua` lives under `statusline/` but is used by breadcrumb.
  **Mitigation**: Cross-require is fine — hlgroup has zero statusline-specific logic.
  When a third bar lib needs it, extract to `beast/libs/hlgroup.lua`. Flag as DRY
  opportunity in AGENTS.md.

- **Risk**: `g:statusline_winid` might not be set for winbar in edge cases.
  **Mitigation**: Same fallback as statusline — `nvim_get_current_win()` when nil/invalid.

- **Risk**: Per-window cache grows with many splits.
  **Mitigation**: `WinClosed` autocmd cleans entries. Typical usage is 2–4 splits.

# Success Criteria

- [ ] Winbar renders filepath with directory segments, separator, icon, filename, modified flag
- [ ] `bench-breadcrumb.lua` hot < 10 µs, cold < 50 µs
- [ ] Winbar hidden on all `beast-*` UI buffers and special buftypes
- [ ] Each window shows its own file's breadcrumb independently
- [ ] ColorScheme change refreshes highlights correctly
- [ ] No dependency on heirline.nvim or nvim-navic

# ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs:

- New library `beast.libs.breadcrumb` — third native `%!` bar (after statusline and tabline),
  establishing the pattern that all bars are native `%!` libraries
- Cross-requiring `statusline/hlgroup.lua` from breadcrumb — signals hlgroup should be
  extracted to a shared module (supersedes implicit assumption in ADR-009 that hlgroup
  is statusline-private)
