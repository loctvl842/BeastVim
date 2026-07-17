---
name: statusline-init
description: "Beast Statusline Library"
generated: 2026-05-02
---

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

### Component Data Classes

Components fall into two performance classes:

**A. Sync** — `provider` reads cheap data (`vim.bo`, `vim.fn.line`, module-local
state) and returns fragments. Two sub-modes depending on whether the component
declares `update`:

- *Uncached* — no `update` field. Provider re-runs on **every render**. Use when
  the value depends on something with no clean event hook, or for ad-hoc
  components where opt-in caching adds no value (the cost is sub-µs anyway).
- *Cached / event-gated* — `update` declared. Provider runs only on cache-miss
  or when one of the declared autocmd events fires (which clears the cache and
  triggers `redrawstatus`). Cache key is `scope` (`global` / `buffer` / `window`).
  This is the **default** for built-in components — declare the events that
  actually change your value, and the engine handles the rest.

> Used by: `mode` (cached, ModeChanged), `position` (cached, CursorMoved+CursorMovedI+BufEnter),
> `filetype` (cached, BufEnter+FileType), `shiftwidth` (cached, BufEnter+OptionSet),
> `encoding` (cached, BufEnter+OptionSet), `diagnostics` (cached, DiagnosticChanged+BufEnter).

**B. Push-mirrored** — the module holds `state.value`. A handler (autocmd or libuv
watcher) **overwrites** `state.value` when the source-of-truth changes and triggers a
redraw (directly via `redrawstatus`, or by firing a `User` event the engine subscribes
to via `update`). The provider is a trivial read of `state.value`.

The recompute can be:

- **Sync handler** — e.g. `git_branch` reads `.git/HEAD` from a libuv `fs_event` callback.
- **Async handler** — e.g. `git_commit` spawns `vim.system({...}, {}, callback)`; the
  callback writes `state.value`.

Either way, **the provider never blocks and never spawns a process**. All I/O lives in
handlers. There is no "cache invalidation" — the handler just *overwrites* the mirrored
state when the source-of-truth changes.

```lua
-- Push-mirrored skeleton
local cache     = {}    -- [bufnr] = string | false
local in_flight = {}    -- prevents stacking duplicate spawns

local function fetch(bufnr) ... end   -- vim.system / libuv; writes cache[bufnr]

local function ensure_autocmds()
    -- Subscribe to BufEnter / BufWritePost / etc., call fetch(args.buf).
    -- Also BufDelete to free entries.
end
ensure_autocmds()

return {
    update   = { "User BeastStatuslineGitChanged" },  -- triggers redraw, NOT recompute
    provider = function(ctx)
        local v = cache[ctx.bufnr]
        if not v then return {} end
        return { { text = v, hl = "..." } }
    end,
}
```

### Performance Contract

For every component:

- `provider(ctx)` is **read-only** — no syscalls, no spawns, no filesystem access.
- Typical cost: **≤ 10 µs**. Anything heavier indicates a missed mirror.
- Side effects (process spawn, file watch, autocmd) live in **handlers** registered by
  the component module on first require (lazy autocmd guard).
- Full bar render target: **< 1 ms** with all components active.
- **Caching is opt-in via `update`.** Declaring `update = { ... }` enables the engine
  result cache: the provider runs only on cache-miss or when a declared event fires
  (engine clears entries for that component, then `redrawstatus`). Omitting `update`
  keeps the simple "run every render" semantics.

### `file_bound` — transient-buffer fallback for cheap file-bound providers

Several cheap file-bound components (`filetype`, `position`, `shiftwidth`, `encoding`)
need to keep showing meaningful info when focus moves to a transient `beast-*` UI buffer
(explorer, toast, packer dialog…). Otherwise the right side of the bar collapses every
time you open the explorer.

`util.file_bound(compute)` is a **UX wrapper, not a cache**:

- On a real file buffer: runs `compute(ctx)` every render (no caching for this path).
- On a transient `beast-*` buffer: returns the value stored from the previous real-file
  render, so the component visually persists.

`compute` return contract:

| Return | Effect |
|--------|--------|
| `string` | Update the stored value (rendered now and on next transient buffer) |
| `false`  | Clear the stored value (component will hide) |
| `nil`    | Keep the previous value unchanged |

The `false` sentinel is what makes `filetype` correctly clear when you switch from
`init.lua` (filetype=lua) to `profile.log` (filetype=""), instead of showing stale "Lua".
The `nil` "skip" path is for transient states where the buffer is a file but data isn't
ready yet (e.g. filetype not yet set during early startup renders).

> **Not for expensive providers.** Because `compute` runs every render on a real file
> buffer, `file_bound` is **only suitable for cheap reads** (`vim.bo`, `vim.fn.line`).
> Expensive computations (process spawn, fs scan) belong in the push-mirrored class
> above — they store state directly, no `file_bound` involved.

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
---@field update?   string[]               -- autocmds that invalidate this component's cache and trigger redrawstatus.
                                           -- When omitted, the provider runs on every render (uncached).
---@field scope?    "global"|"buffer"|"window"   -- cache key when `update` is declared (default "global")
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
`"User BeastStatuslineGitChanged"`, `"FileType lua"`, `"OptionSet shiftwidth"`).
The engine `split_event()`s on the first space and passes `pattern` to
`nvim_create_autocmd`.

When `update` is declared, the engine caches the provider's return value keyed by
`scope`:

| `scope` | Cache key | Use when… |
|---------|-----------|-----------|
| `"global"` (default) | comp_id | Value doesn't depend on buffer or window (e.g. `mode`) |
| `"buffer"` | (comp_id, bufnr) | Value depends on the buffer (e.g. `filetype`, `diagnostics`) |
| `"window"` | (comp_id, winid) | Value depends on the window (e.g. `position`) |

When any event in the component's `update` list fires, the engine clears **all**
entries for that component (across all bufnrs / winids) and calls `redrawstatus`.
Per-buffer / per-window cleanup also runs on `BufWipeout` and `WinClosed` to bound
memory across long sessions.

> **Cache hit semantics.** The engine caches successful provider returns —
> including `{}` ("hide"). It does **not** cache `pcall` failures (provider
> threw); those return uncached so a transient error doesn't stick the
> component to "hidden" until the next event.

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

### `git_commit` — push-mirrored, async via `vim.system`

```lua
local util = require("beast.libs.statusline.util")

-- bufnr -> string|false ; string = display, false = no commit / hidden
local cache     = {}
-- bufnr -> true while a vim.system call is running (debounce)
local in_flight = {}

local function fetch(bufnr)
    if in_flight[bufnr] then return end
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then cache[bufnr] = false; return end

    in_flight[bufnr] = true
    vim.system(
        { "git", "log", "-1", "--format=%an (%cr)", "--", name },
        { text = true },
        vim.schedule_wrap(function(out)
            in_flight[bufnr] = nil
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            if out.code ~= 0 or not out.stdout or out.stdout == "" then
                cache[bufnr] = false
            else
                cache[bufnr] = vim.trim(out.stdout)
            end
            vim.api.nvim_exec_autocmds("User", { pattern = "BeastStatuslineGitChanged" })
        end)
    )
end

local registered = false
local function ensure_autocmds()
    if registered then return end
    registered = true
    local group = vim.api.nvim_create_augroup("BeastStatuslineGitCommit", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = group,
        callback = function(args)
            if util.IGNORED_FILETYPES[vim.bo[args.buf].filetype] then return end
            fetch(args.buf)
        end,
    })
    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,
        callback = function(args)
            cache[args.buf]     = nil
            in_flight[args.buf] = nil
        end,
    })
end
ensure_autocmds()

return {
    condition = function(ctx) return ctx.is_active end,
    update    = { "User BeastStatuslineGitChanged" },  -- load-bearing: triggers redraw on cache write
    scope     = "buffer",
    priority  = 30,
    provider  = function(ctx)
        local v = cache[ctx.bufnr]
        if not v then return {} end
        return {
            { text = " ", hl = { fg = "dimmed3" } },
            { text = v,    hl = { fg = "dimmed3" } },
        }
    end,
}
```

Notes:

- **`vim.system` is non-blocking** (Neovim 0.10+). The render path never spawns a process.
- **`in_flight` debounce** prevents stacking N `git log` processes if `BufEnter` fires
  rapidly during fzf navigation or `:bnext`-style scripting.
- **`BufDelete` cleanup** keeps `cache` from growing unbounded over a long session.
- **`update = { "User BeastStatuslineGitChanged" }`** is load-bearing — without this the
  engine wouldn't subscribe to the User event and the bar would only repaint on the next
  unrelated redraw.
- **First-render latency**: on first open of a file the bar renders without `git_commit`;
  ~10–30 ms later the `vim.system` callback writes the cache and fires the User event →
  bar redraws with the commit info. Trade-off accepted to keep the render path
  non-blocking.
- **No `file_bound`** — the cache itself acts as the visibility gate. Transient
  `beast-*` buffers never get a cache entry, so they implicitly hide.

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

### `position` — window-scoped, gated on cursor + buffer events

`position` depends on cursor position **and** the active buffer in the window.
The window-scoped cache means each (window, current-buffer) pair gets its own
entry; we declare `BufEnter` so a buffer switch in the same window invalidates
the previous buffer's cached position.

```lua
local get_position = util.file_bound(function(ctx)
    if vim.api.nvim_buf_get_name(ctx.bufnr) == "" then return nil end
    local line = vim.fn.line(".", ctx.winid)
    local col  = vim.fn.charcol(".", ctx.winid)
    return string.format("Ln %d, Col %d", line, col)
end)

return {
    update   = { "CursorMoved", "CursorMovedI", "BufEnter" },
    scope    = "window",
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

> **Why gated when CursorMoved already triggers a full redraw?** Without `update`,
> `position` would re-run on every render — including renders triggered by
> unrelated events (`ModeChanged`, `DiagnosticChanged`, `BufWritePost`, …). With
> the gate, those renders hit the cache. Position only re-runs on the events
> that can actually change its value.

### `filetype` / `shiftwidth` / `encoding` — file_bound, gated on the events that change them

All three follow the same pattern. Each declares the precise events that
change its value — none re-runs on unrelated renders.

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
    update   = { "BufEnter", "FileType" },
    scope    = "buffer",
    priority = 40,
    provider = function(ctx)
        local result = get_filetype(ctx)
        if not result then return {} end
        return { { text = result, hl = { fg = "accent5" } } }
    end,
}
```

`shiftwidth` and `encoding` use the `OptionSet` event with the option name as
pattern (so we don't invalidate on every option change in the editor):

```lua
-- shiftwidth.lua
update = { "BufEnter", "OptionSet shiftwidth" }

-- encoding.lua  (depends on both fileencoding and the global encoding fallback)
update = { "BufEnter", "OptionSet fileencoding", "OptionSet encoding" }
```

`shiftwidth` shows `Spaces: 2` (priority 20, hl `accent3`). `encoding` shows
`UTF-8` (priority 15, hl `accent4`). We deliberately gave them different
colours since they sit next to each other.

## Implementation Notes

### Drift from Original Plan

| Original plan | What we shipped |
|--------------|-----------------|
| Engine cache with global/buffer/window scopes + invalidation on declared events | **Re-introduced as opt-in.** Components that declare `update` get cached (keyed by `scope`); components that omit `update` keep "run every render" semantics. Drove this back in because `update` was a half-truth otherwise — the bar redraws on every cursor move regardless, so declaring `update = { "FileType" }` did not actually gate when the provider re-ran. See § "Why we (re)introduced opt-in result caching". |
| `lua/beast/libs/statusline/highlight.lua` | Renamed to `hlgroup.lua` (engine) + new `highlights.lua` (ColorScheme refresh hook, 9 lines) |
| `section.lua` (fragment assembly) | Merged into `util.lua` along with `IGNORED_FILETYPES`, `is_file_buffer`, `file_bound`, width helpers |
| `components.lua` single file | `components/` directory with one file per component |
| `condition = function(ctx) return ctx.buftype == "" end` | Switched to `IGNORED_FILETYPES` lookup. Filtering by buftype was too aggressive (broke on `nofile` real files); only `beast-*` filetypes are excluded. |
| Components hide on transient buffers | Components using `file_bound` keep showing their last value on `beast-*` buffers — better UX, the right side of the bar doesn't collapse every time you open the explorer. |
| `add()` / `remove()` API | Just `setup(opts)` + `render()`. Adding components dynamically wasn't needed. |
| `on_click` field | Not implemented. Add when needed. |
| `cache.hl_groups` in init.lua | Lives in `hlgroup.lua` instead (closer to use). |
| `git_commit` shipped sync via `vim.fn.system` wrapped in `file_bound` (which doesn't actually cache for file buffers — the wrapper only short-circuits on transient buffers) | **Refactored** to push-mirrored async via `vim.system` + per-bufnr cache + `in_flight` debounce + `BufDelete` cleanup. Bench (1000 renders × 3 runs, headless, real file buffer): full-bar render dropped from **~5070 µs → ~10 µs** (**~500× faster**, **~9× faster than lualine** at ~88 µs in the same setup). |

### Why we (re)introduced opt-in result caching

The library originally shipped with **no engine cache**: every render re-ran every
visible component. The decision was driven by the observation that most providers
are sub-µs (`vim.bo` reads), so caching saved microseconds in exchange for three
keyed cache tables, cleanup hooks, and invalidation logic — perceived not worth
the complexity.

What changed: we hit the limits of that model when reasoning about `update`.
Before this change, `update` only triggered `redrawstatus`; the provider re-ran
on *every* render anyway. So `update = { "FileType" }` was a half-truth — yes
the bar redraws when FileType fires, but the bar also redraws on every cursor
move, mode change, BufWritePost, etc. The component's value was effectively
recomputed continuously, and `update` was a documentation hint at best. The two
type definitions in the codebase even drifted apart: one called `update`
"autocmds that should trigger redrawstatus", the other called it "autocmds that
invalidate this component's cache" — the second was a lie until now.

The new contract makes `update` an actual gate:

- **Component declares no `update`** → provider runs every render (today's
  behaviour, no caching, no surprises). Compatible with third-party components
  that pre-date this change.
- **Component declares `update = { ... }`** → engine caches the provider's
  result keyed by `scope`. When any event in the list fires, the engine clears
  all entries for that component and calls `redrawstatus`. The next render is
  the only one that re-runs the provider.

Three things change as a result:

1. **`update` is now load-bearing.** A component that wants to keep showing
   stale data after a relevant event has to either keep `update` empty (re-run
   every time, no cache) or list the right events. There's no third option.
2. **`scope` is no longer just metadata.** It's the cache key, so picking
   `buffer` vs `window` actually matters now.
3. **The expensive providers don't change behaviour.** `git_branch` and
   `git_commit` already own their own state via the push-mirrored pattern; the
   engine cache stores their cheap reads as a freebie but the heavy work still
   happens in their own handlers (libuv watcher / `vim.system` async).

The `_filetype = nil` vs `keep` bug that originally argued *against* caching is
not reintroduced — that bug lived inside `util.file_bound`, where the
3-state return contract (`string` / `false` / `nil`) is now in place. The
engine cache stores whatever `file_bound` returned; it doesn't reinterpret it.

Performance impact is small but real: the bench fell from ~10 µs/render to
~6–8 µs/render after the migration, because cheap providers now hit the cache
on renders triggered by unrelated events. The bigger win is correctness and
mental clarity — the `update` field finally means what its docstring says.

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
- Cheap file-bound components use `util.file_bound` for transient-buffer visibility:
  `position`, `filetype`, `shiftwidth`, `encoding`
- Push-mirrored components manage their own state + handlers:
  - `git_branch` — libuv `fs_event` watcher on `.git/HEAD`
  - `git_commit` — `vim.system` async + per-bufnr cache + `BufEnter`/`BufWritePost`
    triggers + `BufDelete` cleanup
- Both git components fire `User BeastStatuslineGitChanged` to drive redraw; the engine
  subscribes via `update`.

### Phase 3: Wrap-up (deferred)

- ADRs (see [ADR Required](#adr-required))
- Codemap regeneration

### Phase 4: Opt-in result caching (this change) ✅

- `init.lua` — add cache table (global / buffer / window buckets), gated lookup
  in `eval_component`, per-event invalidation autocmd, BufWipeout/WinClosed
  cleanup that clears entries (not just `redrawstatus`).
- `eval_component` semantics:
  - `condition` returns false → return nil, do not cache.
  - `pcall(provider)` errors → return nil, **do not cache** (so a transient
    error doesn't stick the component to "hidden").
  - `provider` returns `{}` (hide) → cache the empty result.
  - `provider` returns fragments → cache them.
- Component migrations:
  - `mode` → `update = { "ModeChanged" }`, scope `global` (already correct)
  - `position` → `update = { "CursorMoved", "CursorMovedI", "BufEnter" }`, scope `window`
  - `filetype` → `update = { "BufEnter", "FileType" }`, scope `buffer`
  - `shiftwidth` → `update = { "BufEnter", "OptionSet shiftwidth" }`, scope `buffer`
  - `encoding` → `update = { "BufEnter", "OptionSet fileencoding", "OptionSet encoding" }`, scope `buffer`
  - `diagnostics` — already correct
  - `git_branch`, `git_commit` — unchanged (push-mirrored)
- Bench: `scripts/bench-statusline.lua` should show a drop from ~10 µs to ~6–8 µs
  per render. Hard threshold (1 ms) unchanged; soft target (50 µs) unchanged.

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

- **Process spawn cost in `git_commit`** → mitigated by `vim.system` async + per-bufnr
  cache + `in_flight` debounce. The render path is read-only.
- **First-render lag for `git_commit`** → first time a file is focused the bar renders
  without commit info for ~10–30 ms until `git log` returns and fires the User redraw
  event. Acceptable trade-off; the alternative is blocking the bar for that same time.
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
- [x] Full-bar render < 1 ms; **measured 6.41 µs/call** (1000 renders × 3 runs, headless)
  after Phase 4 opt-in caching — **~14.8× faster than lualine** in the same setup
  (lualine 94.77 µs/call). Pre-Phase-4 was ~10 µs/call (~9× lualine); the cache
  shaved ~40% off the render path. Provider cost ≤ 10 µs for every component; no
  provider performs I/O. The async push-mirrored pattern in `git_commit` (see worked
  example) eliminates the prior ~5 ms/call cost from `vim.fn.system`.
- [x] Opt-in result cache: components that declare `update` re-run only on cache-miss
  or when a declared event fires. Components that omit `update` keep "run every
  render" semantics. Bench dropped to **6.41 µs/call** after migration; soft target ≤ 50 µs
  in `scripts/bench-statusline.lua`. `pcall` failures are not cached.

## Related ADRs

The decisions below are documented as separate ADRs:

- [ADR-009](../ADRs/009-native-statusline-replaces-heirline.md) — Native `%!` Statusline
  Replaces Heirline
- [ADR-010](../ADRs/010-no-engine-level-statusline-cache.md) — No Engine-Level Statusline
  Cache (lualine-style re-evaluate every render; components own their own state)
  — ***superseded by [ADR-013](../ADRs/013-opt-in-statusline-result-caching.md)***:
  opt-in caching is now available when components declare `update`. The
  "components own their own state" half still holds for push-mirrored providers
  (`git_branch`, `git_commit`).
- [ADR-011](../ADRs/011-file-bound-provider-wrapper.md) — `file_bound` Provider Wrapper
  for Transient UI Buffers (and `IGNORED_FILETYPES = beast-*` only)
- [ADR-012](../ADRs/012-compound-fragment-component-model.md) — Compound-Fragment
  Component Model
- [ADR-013](../ADRs/013-opt-in-statusline-result-caching.md) — Opt-In Result Caching
  with Event-Gated Invalidation (this Phase 4)

The push-mirrored data model (state-mirror + autocmd/watcher writes + `vim.system` async)
is consistent with ADR-010's stance — components own their own state, the engine has no
cache. It's documented in detail in **Component Data Classes** above; if a third
async component lands, extracting `util.async_provider({ key, compute, update })` may be
worth its own ADR.
