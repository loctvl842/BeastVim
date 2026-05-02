# Dev Spec: Beast Statusline Library

> **Status**: Implemented. This document was rewritten after the implementation to reflect
> what was actually built. The original plan diverged in several ways during development —
> notably, the engine cache was dropped in favour of lualine-style "every render re-runs the
> provider" with components owning their own caching when needed. See [Implementation Notes](#implementation-notes)
> for the full diff vs the original design.

## Summary

Native statusline library at `lua/beast/libs/statusline/` that replaces heirline.nvim for the
statusline only (heirline still drives tabline + winbar). Combines lualine's "render is just
table.concat over cheap data" philosophy with heirline's declarative component-spec model,
while following BeastVim library conventions.

**Public API:**

```lua
local stl = require("beast.libs.statusline")
local cpn = require("beast.libs.statusline.components")
stl.setup({
    left  = { cpn.git_branch, cpn.diagnostics },
    right = { cpn.git_commit, cpn.position, cpn.filetype, cpn.shiftwidth, cpn.encoding, cpn.mode },
})
```

`setup()` registers the components, wires autocmds, and sets `vim.o.statusline` to call
`render()` via `%!`. Neovim handles **when** to redraw; `render()` only handles **what** to
draw.

## Requirements

### Functional

- Render statusline via `%!v:lua.require'beast.libs.statusline'.render()`
- Three regions: `left` / `center` / `right`, joined with native `%=`
- Components are declarative tables with: `provider`, `condition`, `update`, `scope`,
  `priority`, `separator`
- Each component returns **compound fragments** (list of `{text, hl}` pairs) for
  multi-coloured segments (used heavily by `diagnostics` and `mode`)
- Components can declare autocmd events (`update = { "DiagnosticChanged", ... }`) that
  trigger a `redrawstatus`
- Active vs. inactive window differentiation via `g:statusline_winid`
- Width-aware truncation: drop lowest-priority components across all regions until total
  fits the available width
- Highlight groups created lazily from `{fg, bg, bold, ...}` specs, deduped by deterministic
  hash, refreshed on `ColorScheme` via the BeastVim `highlight_modules` registry
- File-bound components (`filetype`, `position`, `shiftwidth`, `encoding`, `git_commit`)
  remain visible with their last-known value when focus moves to a transient `beast-*` UI
  buffer (explorer, toast, packer, etc.)
- Config-driven: `setup(opts)` merges into a frozen-by-metatable `config` module

### Non-Functional

- Render path must be cheap: `g:statusline_winid` lookup → provider calls → string concat.
  No I/O on the render path (git_commit shells out, but only on first compute per file
  buffer; result is held by `file_bound`'s closure).
- No external Neovim plugin dependencies. Git branch uses a `vim.uv` `fs_event` on
  `.git/HEAD` rather than depending on gitsigns.
- Follows BeastVim library conventions: state only in `init.lua`, frozen-config metatable,
  lazy autocmd registration, palette refresh via `highlight_modules`.

### Out of Scope (deferred)

- Tabline / winbar (separate libraries; would share `hlgroup.lua`)
- Statuscolumn (different evaluation model — per-line, much stricter perf)
- `on_click` support (`%@Func@...%T`) — not used yet
- `flexible` priority variants (heirline-style "shorter form when tight") — current
  whole-component drop-by-priority is good enough for ~8 components
- Wiring into the user config (`lua/beast/init.lua` / `plugins/bars`) — owned by the user

### Future Components

Possible components to add later. Each gets its own dev spec when work begins:

- AI-sync (Copilot / Codeium / Supermaven / Avante / etc.)

## Research

### Repo Search

- Searched for: `statusline`, `stl`, `redrawstatus`, `winbar`, `%!`
- Found: Existing statusline at `lua/beast/plugins/bars/statusline/` uses heirline.nvim
- Found: `Util.colors.inspect()` in `beast/util/colors.lua` — reusable for hl resolution
- Found: Existing `Palette` system — palette aliases (e.g. `accent1`) resolve via `Palette.get()`
- Reuse: `Palette.get()` for colour aliases, `M.highlight_modules` registry pattern for
  ColorScheme refresh

### Package Search

- Lualine, heirline, feline, galaxyline, express_line — all framework-style, all heavier
  than what we need
- Decision: **build native**. Lualine's perf patterns and heirline's component model inform
  the design; no dependency taken.

## Design Notes

### From Lualine — Performance Patterns

1. **Highlight pre-creation & dedup** — adopted: `hlgroup.ensure(spec)` returns a deterministic
   group name from a hashed spec; the group is created once via `nvim_set_hl` and cached.
2. **Render = cheap string assembly** — adopted: `render()` is `table.concat` over fragment
   text + `%#Group#…%*` markers. No shell calls or filesystem access on the render path.
3. **Error isolation per component** — adopted: `pcall(spec.provider, ctx)` in
   `eval_component`. One broken provider doesn't crash the bar.
4. **No engine-level result cache** — adopted (this is a key divergence from the original
   plan). Lualine re-runs every component on every render and lets components cache
   internally if they need to. We do the same — see [Implementation Notes](#implementation-notes).
5. **Refresh coalescing** — handled by Neovim's own `%!` redraw timing; we don't run a
   timer.

### From Heirline — Extensibility Patterns

1. **Declarative component specs** — adopted fully. Components are plain Lua tables.
2. **`update` event declarations** — adopted, but the semantics are simpler than heirline:
   each declared autocmd just triggers `redrawstatus`. Since we have no cache to invalidate,
   the engine's only job is to ensure Neovim redraws.
3. **`condition` gates** — adopted. Returning `false` from `condition` skips the provider
   entirely.
4. **Priority-based truncation** — adopted in a simplified form: whole components are
   dropped (no flexible variants).
5. **Skip nested children / parent-child highlight inheritance** — too much machinery for
   ~8 flat components.

### From Neovim — The `%!` Advantage

- Neovim re-evaluates `%!` automatically on mode change, cursor move, window focus, buffer
  switch, etc. — we don't need our own refresh loop.
- The returned string can still contain native items (`%l`, `%c`, `%P`, etc.) which Neovim
  evaluates after our Lua returns — zero Lua cost for those.
- `g:statusline_winid` tells us **which** window the bar is being drawn for, regardless of
  which window is "current" in Lua-land.

## Architecture

### Final File Layout

```
lua/beast/libs/statusline/
├── init.lua          ← public API, state owner, autocmd registration
├── config.lua        ← defaults, frozen-by-metatable, setup(opts)
├── context.lua       ← stateless: build per-render Beast.Statusline.Context
├── hlgroup.lua       ← deterministic hl group creation + cache + clear_all
├── highlights.lua    ← ColorScheme refresh hook (clears hl cache, redraws)
├── util.lua          ← width helpers, fragment assembler, IGNORED_FILETYPES,
│                       is_file_buffer(), file_bound() provider wrapper
├── truncate.lua      ← priority-based component dropping
└── components/
    ├── init.lua      ← barrel + type definitions for ComponentSpec / Fragment / ...
    ├── mode.lua
    ├── git_branch.lua    ← libuv fs_event on .git/HEAD
    ├── git_commit.lua    ← `git log -1 --format='%an (%cr)' -- <file>`, file_bound
    ├── diagnostics.lua
    ├── position.lua      ← file_bound, only for named files
    ├── filetype.lua      ← file_bound
    ├── shiftwidth.lua    ← file_bound
    └── encoding.lua      ← file_bound
```

### Dependency Flow

```
init.lua  ──→ config.lua, context.lua, util.lua, truncate.lua
util.lua  ──→ hlgroup.lua
truncate.lua ──→ util.lua
components/*.lua ──→ util.lua  (for file_bound + types)
highlights.lua  ──→ hlgroup.lua  (ColorScheme hook only — does not require init.lua)
beast/init.lua ──→ statusline (calls stl.setup) and registers
                   "beast.libs.statusline.highlights" in M.highlight_modules
```

### Render Pipeline

```
%! → M.render()
  1. ctx = context.build()                 -- read g:statusline_winid + bufnr + width
  2. for region in {left, center, right}:
       items = build_visible_items(region_ids, ctx)
       └── for each component:
             if condition(ctx) is false → skip
             pcall(provider, ctx) → fragments
             pre-compute strdisplaywidth on each fragment
  3. truncate.fit(regions, ctx.width, ...)  -- drop lowest priority across regions
  4. assemble parts:
       %< (truncate marker)
       %#StatusLine# or %#StatusLineNC# (active/inactive base)
       util.assemble(left, sep)
       %=
       util.assemble(center, sep)
       %=
       util.assemble(right, sep)
  5. table.concat → return
```

### Render Context

`context.build()` produces, every render:

```lua
{
  winid    = <target window from g:statusline_winid>,
  bufnr    = <buffer in target window>,
  is_active = <target == current window>,
  mode     = <vim.api.nvim_get_mode().mode>,
  width    = <vim.o.columns when laststatus=3, else nvim_win_get_width(target)>,
  filetype = <vim.bo[bufnr].filetype>,
  buftype  = <vim.bo[bufnr].buftype>,
}
```

Two important details:

1. **`g:statusline_winid` fallback** — if it's nil/invalid (e.g. `:lua` direct call), fall
   back to current window so manual invocation still works.
2. **`laststatus=3` width fix** — with the global statusline, `nvim_win_get_width(target)`
   returns the focused window's width, **not** the bar's width. When a narrow sidebar
   (explorer ~30 cols) was focused, truncation thought it had 30 cols and dropped most
   components. Fix: use `vim.o.columns` for global statusline width.

### `file_bound` — the file-bound provider wrapper

Several components (`filetype`, `position`, `shiftwidth`, `encoding`, `git_commit`) need to
keep showing meaningful info when focus moves to a transient `beast-*` UI buffer (explorer,
toast, packer dialog…). Otherwise the right side of the bar collapses every time you open
the explorer.

`util.file_bound(compute)` wraps a compute function and:

- Calls `compute(ctx)` only when the current buffer is a real file (`is_file_buffer(ctx)`)
- Remembers the last computed value
- On ignored filetypes, returns the last value (component stays visible)

`compute` return contract:

| Return | Effect |
|--------|--------|
| `string` | Update the stored value |
| `false`  | Clear the stored value (component will hide) |
| `nil`    | Keep the previous value unchanged |

The `false` sentinel is what makes `filetype` correctly clear when you switch from
`init.lua` (filetype=lua) to `profile.log` (filetype=""), instead of showing stale "Lua".
The `nil` "skip" path is for transient states where the buffer is a file but we don't yet
have data (e.g. filetype not yet set during early startup renders).

### `IGNORED_FILETYPES`

Lives in `util.lua`. Lists every transient `beast-*` filetype produced by `Buffer.new()`
across the BeastVim libs. **Only `beast-*` entries** — third-party plugin filetypes are not
included on purpose.

```lua
M.IGNORED_FILETYPES = {
    ["beast-backdrop"] = true,
    ["beast-confirm"]  = true,
    ["beast-explorer"] = true,
    ["beast-key"]      = true,
    ["beast-key-actions"] = true,
    ["beast-notify"]   = true,
    ["beast-packer"]   = true,
    ["beast-packer-actions"] = true,
    ["beast-toast"]    = true,
}

function M.is_file_buffer(ctx)
    return not M.IGNORED_FILETYPES[ctx.filetype]
end
```

### Highlight Groups

`hlgroup.ensure(spec)` returns a Vim-friendly group name:

- String spec (e.g. `"Comment"`) — passes through unchanged
- Table spec (e.g. `{ fg = "accent1", bold = true }`) — hashed using sorted keys
  (`fg, bg, bold, italic, underline, reverse, link`), sanitised, prefixed with
  `BeastStl_`. The group is created once via `nvim_set_hl` and cached in a `created` table.

Palette aliases (`accent1`, `text`, `dimmed3`, …) resolve through `Palette.get()`. Hex
strings (`#rrggbb`) and `"NONE"` pass through.

`hlgroup.clear_all()` deletes every created group and resets both caches. This is called
from `highlights.lua` whenever the colorscheme changes.

### ColorScheme Integration

We don't register a `ColorScheme` autocmd inside the statusline lib. Instead:

1. `lua/beast/init.lua` defines `M.highlight_modules` — a registry of lib hl modules.
2. `"beast.libs.statusline.highlights"` is in that registry.
3. On `ColorScheme`, BeastVim runs `Palette.refresh()` then re-requires every entry
   in `highlight_modules`. Re-requiring `highlights.lua` runs its body, which is
   two-phase:
   - `hlgroup.clear_all()` — wipe the dynamic `BeastStl_<hash>` cache.
   - `redrawstatus` — trigger `M.render()`, which re-calls `hlgroup.ensure(spec)`
     for every fragment, lazily re-creating groups from the fresh palette.

Unlike other libs (explorer/key/confirm/packer/notify), the statusline does **not**
define any static `BeastStatusline*` groups via `nvim_set_hl`. All groups are
generated on demand from inline specs (`{ fg = "accent3" }`) in component
providers. The two-phase refresh is what makes that work across colorscheme
changes.

This keeps the order strict: palette refreshes **before** statusline re-renders, so
`accent1` etc. resolve to the new colours.

### Truncation

`truncate.fit(regions, available_width, default_sep, default_priority)`:

1. If everything fits → return as-is.
2. Pool every visible item across regions, tagged with `priority`, `width`, region, index.
3. Sort by priority ascending — lowest dropped first.
4. Walk the pool; mark items hidden, subtract their width + a separator estimate, until
   the total fits.
5. Rebuild per-region item lists in original order, skipping hidden indices.

Cross-region — a low-priority right item gets dropped before a high-priority left item.

### Component Spec Reference

```lua
---@class Beast.Statusline.ComponentSpec
---@field provider  fun(ctx): Beast.Statusline.Fragment[]?
---@field condition? fun(ctx): boolean    -- skip provider entirely if false
---@field update?   string[]               -- autocmds that should trigger redrawstatus
---@field scope?    "global"|"buffer"|"window"   -- declarative metadata
---@field priority? integer                -- truncation priority (default config.default_priority)
---@field separator? string                 -- separator after this component (overrides default)
```

```lua
---@class Beast.Statusline.Fragment
---@field text  string                      -- displayable text (may contain native % items)
---@field hl?   string|Beast.Statusline.HighlightSpec
---@field width? integer                    -- pre-computed by the engine
```

`update` entries are autocmd event names, optionally `"Event Pattern"` (e.g.
`"User BeastStatuslineGitChanged"` or `"FileType lua"`). The engine `split_event()`s on
the first space and passes `pattern` to `nvim_create_autocmd`.

> **Note on `scope`**: this is currently declarative metadata only — the engine no longer
> uses it (since we dropped the result cache). Components keep declaring it for clarity and
> for forward compatibility if we re-introduce caching.

## Component Examples

### `mode` — global, instant on `ModeChanged`, compound fragment

```lua
local mode_names = {
    n = "NORMAL", i = "INSERT", v = "VISUAL", V = "V-LINE",
    ["\22"] = "V-BLOCK", c = "COMMAND", R = "REPLACE", t = "TERMINAL",
    -- (full table covers every variant: niI, vs, ic, ix, Rv, …)
}
local mode_colors = {
    n = "accent1", i = "accent4", v = "accent5",
    V = "accent5", ["\22"] = "accent5", c = "accent2",
    R = "accent2", t = "accent4", s = "accent6",
}

return {
    condition = function(ctx) return ctx.is_active end,
    update = { "ModeChanged" },
    scope = "global",
    priority = 90,
    provider = function(ctx)
        local key = mode_names[ctx.mode] and ctx.mode or ctx.mode:sub(1, 1)
        local name = mode_names[key] or "NORMAL"
        local color = mode_colors[ctx.mode:sub(1, 1)] or "accent1"
        return {
            { text = name, hl = { fg = color, bold = true } },
            { text = " ",  hl = { fg = "text" } },
        }
    end,
}
```

### `git_branch` — buffer, libuv fs_event watcher

Resolves a buffer's `.git/HEAD` upward through parents, caches the git_dir per directory,
and starts a `vim.uv.new_fs_event` watcher on `HEAD`. When the watcher fires (branch
change), it invalidates its internal branch cache and emits
`User BeastStatuslineGitChanged`, which `git_branch` and `git_commit` both subscribe to.

```lua
return {
    update = { "BufEnter", "DirChanged", "User BeastStatuslineGitChanged" },
    scope = "buffer",
    priority = 60,
    provider = function(ctx)
        local branch = branch_for_buf(ctx.bufnr, ctx.winid) or "!=vcs"
        return {
            { text = "   ",  hl = { fg = "text" } },
            { text = branch, hl = { fg = "accent4", bold = true } },
        }
    end,
}
```

### `git_commit` — file_bound, shells out to git log

```lua
local last_commit_for_buf = function(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then return nil end
    local result = vim.fn.system({ "git", "log", "-1", "--format=%an (%cr)", "--", name })
    if vim.v.shell_error ~= 0 or not result or result == "" then return nil end
    return vim.trim(result)
end

local get_commit = util.file_bound(function(ctx)
    return last_commit_for_buf(ctx.bufnr) or false
end)

return {
    condition = function(ctx) return ctx.is_active end,
    update = { "BufEnter", "BufWritePost", "User BeastStatuslineGitChanged" },
    scope = "buffer",
    priority = 30,
    provider = function(ctx)
        local result = get_commit(ctx)
        if not result then return {} end
        return {
            { text = " ",    hl = { fg = "dimmed3" } },
            { text = result, hl = { fg = "dimmed3" } },
        }
    end,
}
```

`return last_commit_for_buf(ctx.bufnr) or false` — returning `false` when there's no commit
clears `file_bound`'s stored value so the component hides instead of showing a stale value
from the previous buffer.

### `diagnostics` — buffer, compound fragment, no condition

```lua
return {
    update = { "DiagnosticChanged", "BufEnter" },
    scope = "buffer",
    priority = 50,
    provider = function(ctx)
        local counts = { 0, 0, 0, 0 }
        for _, d in ipairs(vim.diagnostic.get(ctx.bufnr)) do
            counts[d.severity] = (counts[d.severity] or 0) + 1
        end
        local sev = vim.diagnostic.severity
        local icons = (Icon and Icon.diagnostics) or { error="E", warn="W", info="I", hint="H" }
        return {
            { text = icons.error .. " " .. counts[sev.ERROR] .. " ", hl = { fg = "accent1" } },
            { text = icons.warn  .. " " .. counts[sev.WARN]  .. " ", hl = { fg = "accent3" } },
            { text = icons.info  .. " " .. counts[sev.INFO]  .. " ", hl = { fg = "accent5" } },
            { text = icons.hint  .. " " .. counts[sev.HINT],          hl = { fg = "accent4" } },
        }
    end,
}
```

### `position` — file_bound, only for named files, no `update` field

Cursor moves auto-redraw the statusline natively, so we don't need to declare `CursorMoved`
as an `update` event.

```lua
local get_position = util.file_bound(function(ctx)
    if vim.api.nvim_buf_get_name(ctx.bufnr) == "" then return nil end
    local line = vim.fn.line(".", ctx.winid)
    local col  = vim.fn.charcol(".", ctx.winid)
    return string.format("Ln %d, Col %d", line, col)
end)

return {
    scope = "window",
    priority = 70,
    provider = function(ctx)
        local result = get_position(ctx)
        if not result then return {} end
        return { { text = result, hl = { fg = "accent6" } } }
    end,
}
```

The `nvim_buf_get_name(...) == ""` guard prevents the empty startup buffer from showing
"Ln 1, Col 1" before the user has opened a real file.

### `filetype` / `shiftwidth` / `encoding` — file_bound, simple

All three follow the same pattern:

```lua
-- filetype.lua
local get_filetype = util.file_bound(function(ctx)
    local ft = vim.bo[ctx.bufnr].filetype
    if ft ~= "" then
        local formatted = ft:gsub("^%l", string.upper)  -- captures into local to drop gsub's 2nd return
        return formatted
    end
    return false  -- clear when buffer truly has no filetype (e.g. profile.log)
end)

return {
    update = { "BufEnter", "FileType" },
    scope = "buffer",
    priority = 40,
    provider = function(ctx)
        local result = get_filetype(ctx)
        if not result then return {} end
        return { { text = result, hl = { fg = "accent5" } } }
    end,
}
```

`shiftwidth` (`Spaces: 2`, priority 20, hl `accent3`) and `encoding` (`UTF-8`, priority 15,
hl `accent4`) are structurally identical. We deliberately gave them different colours since
they sit next to each other.

## Implementation Notes

### Drift from Original Plan

| Original plan | What we shipped |
|--------------|-----------------|
| Engine cache with global/buffer/window scopes + invalidation on declared events | **No engine cache.** Every render re-runs each visible component. Components own their caching when they need it (`file_bound`, `git_branch`'s libuv watcher). |
| `lua/beast/libs/statusline/highlight.lua` | Renamed to `hlgroup.lua` (engine) + new `highlights.lua` (ColorScheme refresh hook, 9 lines) |
| `section.lua` (fragment assembly) | Merged into `util.lua` along with `IGNORED_FILETYPES`, `is_file_buffer`, `file_bound`, width helpers |
| `components.lua` single file | `components/` directory with one file per component |
| `condition = function(ctx) return ctx.buftype == "" end` | Switched to `IGNORED_FILETYPES` lookup. Filtering by buftype was too aggressive (broke on `nofile` real files); only `beast-*` filetypes are excluded. |
| Components hide on transient buffers | Components using `file_bound` keep showing their last value on `beast-*` buffers — better UX, the right side of the bar doesn't collapse every time you open the explorer. |
| `add()` / `remove()` API | Just `setup(opts)` + `render()`. Adding components dynamically wasn't needed. |
| `on_click` field | Not implemented. Add when needed. |
| `cache.hl_groups` in init.lua | Lives in `hlgroup.lua` instead (closer to use). |

### Why we dropped the engine cache

Most of our providers are extremely cheap (read a `vim.bo` field, format a string). Caching
those saves microseconds and adds:

- Three keyed cache tables (`global` / `buffer` / `window`)
- `BufWipeout`/`WinClosed` cleanup hooks for each
- An `invalidate_component(comp_id)` helper that has to walk all three tables
- Subtle bugs around when `_filetype = nil` vs `keep` (this is what kept the filetype
  component stuck on "Lua" after switching to a no-ft buffer).

The expensive providers we actually have are:

- `git_branch` — already cached internally by directory + invalidated by libuv fs_event
- `git_commit` — `vim.fn.system` git log; held by `file_bound`'s closure (one shell call
  per file the first time, then sticky)

Both manage their own caching better than a generic engine cache could (because they know
their own invalidation rules). For everything else, re-running on every render is fine — it's
literally just `vim.bo[bufnr].filetype`.

### Critical Bug Fixes That Became Architecture

1. **`g:statusline_winid` can be a float** — fixed by always using whatever winid Neovim
   sets; the `is_active` flag accounts for it. (Earlier we tried "find the main window"
   logic — turned out to be unnecessary once the width fix below was in place.)
2. **`laststatus=3` width** — `nvim_win_get_width(target_win)` returns the focused window's
   width, not the bar's width. When the explorer (~30 cols) was focused, truncation
   thought it had 30 cols and dropped components, so filetype/position/shiftwidth/encoding
   "disappeared" when you focused the explorer. Fix: `width = vim.o.columns` when
   `laststatus == 3`.
3. **`%!` result is cached by Neovim** — even after we re-render, the previously-rendered
   string can persist on screen until Neovim decides to redraw. We now run
   `vim.cmd("redrawstatus")` explicitly on `BufWipeout` and `WinClosed` so the bar updates
   immediately when a transient UI buffer goes away.

### `string.gsub` and the LSP

`return ft:gsub("^%l", string.upper)` triggers `redundant-return-value` because gsub returns
two values (string + count). Capturing into a local variable first discards the count:

```lua
local formatted = ft:gsub("^%l", string.upper)
return formatted
```

## Implementation Phases

### Phase 1: Core Engine ✅

- `config.lua` — defaults + frozen-by-metatable + `setup(opts)`
- `context.lua` — `g:statusline_winid` resolution, `laststatus=3` width fix
- `hlgroup.lua` — deterministic group names, hash dedup, `clear_all`
- `util.lua` — fragment assembly, width helpers, `IGNORED_FILETYPES`,
  `is_file_buffer`, `file_bound`
- `truncate.lua` — cross-region priority drop
- `init.lua` — public API, autocmd registration, `BufWipeout`/`WinClosed` redraw

### Phase 2: Components ✅

- `mode`, `git_branch` (libuv fs_event), `diagnostics`, `position`, `filetype`,
  `shiftwidth`, `encoding`, `git_commit`
- All file-bound components use `file_bound`
- `git_branch` and `git_commit` subscribe to `User BeastStatuslineGitChanged`

### Phase 3: Wrap-up (deferred)

- ADRs (see [ADR Required](#adr-required))
- Codemap regeneration

## Testing

- **Manual verification** (no test framework in repo):
  - `:lua print(require("beast.libs.statusline").render())` — verify output
  - Mode switch — `mode` updates instantly
  - Open `init.lua` (filetype=lua) → `profile.log` (filetype="") — `filetype` clears
  - Focus explorer — file-bound components keep last value
  - Focus toast (transient) at startup — file-bound components don't go blank
  - Narrow to ~50 cols — low-priority components drop, high-priority stay
  - `:colorscheme X` — highlights rebuild via `M.reload_highlights()`
  - Open file in fresh git repo with no commits — `git_commit` hides (returns `false`)
  - Switch branches in shell — `git_branch` updates without nvim restart (libuv watcher)

## Risks & Mitigations

- **Synchronous git log in git_commit** → mitigated by `file_bound` closure caching the
  result; one shell call per file the first time. If this becomes a bottleneck, switch to
  `vim.system` async (Neovim 0.10+).
- **`g:statusline_winid` confusion** → handled by always using it (with current-window
  fallback) and computing `is_active` from comparison.
- **Highlight group explosion** → bounded by `hash(spec)` dedup; specs with the same
  fg/bg/attrs share a group.
- **Coexistence with heirline** → statusline is independent of tabline/winbar; we only set
  `vim.o.statusline`.

## Success Criteria

- [x] All core components render (mode, git_branch, git_commit, diagnostics, position,
  filetype, shiftwidth, encoding)
- [x] Active/inactive distinction via `is_active` flag and `StatusLine`/`StatusLineNC`
- [x] Mode changes reflect via `ModeChanged`; cursor moves auto-redraw
- [x] Diagnostics update on `DiagnosticChanged`
- [x] Git branch updates on `BufEnter` + libuv `.git/HEAD` watch
- [x] Git commit info updates on `BufEnter` + `BufWritePost`
- [x] File-bound components stay visible on transient `beast-*` UI buffers
- [x] `position` only appears once a real (named) file is opened
- [x] `filetype` clears when switching from a buffer with a filetype to one without
- [x] ColorScheme refresh hook (`highlights.lua`) rebuilds groups
- [x] Narrow window drops low-priority components, keeps high-priority
- [x] No `heirline` dependency for statusline rendering
- [x] Follows BeastVim conventions: state in init.lua, frozen config metatable, lazy
  autocmd registration, palette refresh through registry

## ADR Required

These decisions are worth documenting:

- **Drop engine-level result cache; lualine-style re-evaluate every render** — diverges
  from the original plan; rationale: providers are cheap, components own their own
  caching, simpler to reason about.
- **`file_bound` provider wrapper for transient UI buffers** — establishes a pattern other
  bars (winbar, tabline) can reuse.
- **`IGNORED_FILETYPES` is `beast-*` only** — explicitly does not include third-party
  plugin filetypes; users who want to extend can do so via component-side conditions.
- **ColorScheme refresh through `M.highlight_modules` registry** — consistent with other
  Beast libs, ensures palette refreshes before any highlight resolution.
- **Compound-fragment component model** — establishes the multi-output pattern across
  Beast libs (used heavily by mode + diagnostics).
