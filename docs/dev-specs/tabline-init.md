---
name: tabline-init
description: "Beast Tabline Library"
generated: 2026-05-13
---

# Dev Spec: Beast Tabline Library

## Summary

Native tabline library at `lua/beast/libs/tabline/` that **is intended to replace** the
heirline.nvim implementation at `lua/beast/plugins/bars/tabline/`. Renders the tabline
via Neovim's native `%!` evaluation (`vim.o.tabline = "%!v:lua...."`), keeps the visual
UX of the existing heirline-based design, and removes heirline's per-render reflection
/ component-tree overhead.

> **Out of scope**: this dev spec only builds the new library. It does **not** modify
> any file under `lua/beast/plugins/`. The cutover (replacing heirline as the tabline
> driver and rewiring keymaps in `bars/init.lua`) is owned by the user and will happen
> outside this dev spec on their own schedule.

The library follows BeastVim conventions (state in `init.lua`, frozen-by-metatable
config, lazy autocmds, `Beast.Tabline.*` types) and its render pipeline mirrors
bufferline.nvim's: a single Lua entrypoint produces a tabline format string assembled
from `%#Group#text%*` segments and native click handlers (`%@Func@text%X`).

**Public API:**

```lua
local tabline = require("beast.libs.tabline")
tabline.setup({
    max_name_width    = 24,
    sidebar_filetypes = { ["neo-tree"] = "EXPLORER", ["beast-explorer"] = "" },
    show_close_button = true,
    show_modified     = true,
    show_diagnostics  = true,
})
-- Buffer/tab navigation helpers (mapped from user keymaps)
tabline.goto_buffer(1)
tabline.cycle_next() / tabline.cycle_prev()
tabline.move_next() / tabline.move_prev()
```

`setup()` validates options, registers click-handler globals, wires autocmds, and sets
`vim.o.tabline = "%!v:lua.require'beast.libs.tabline'.render()"`. Neovim handles **when**
to redraw; `render()` only handles **what** to draw.

## Requirements

### Functional (parity with current heirline tabline)

- Render the tabline via `%!v:lua.require'beast.libs.tabline'.render()`
- Three sections, in fixed order: **offset → buffer list → tabpages**
- **Offset section**: when the first window of the tabpage is a sidebar
  (`neo-tree` / `NvimTree` / `beast-explorer`), render a centered title block whose
  width matches the sidebar window so buffer tabs start at the editor split.
- **Buffer list section**: for each listed buffer, render `[icon] [name] [diag/●] [×]`,
  with:
  - Disambiguating filename for duplicates (parent dir prefix)
  - Filename truncated to `max_name_width` (with leading `…`)
  - Highest-severity diagnostic count or modified `●`
  - Close-button `󰅖` on the active buffer (and a `  ` placeholder on inactive ones for
    layout stability)
  - Diagnostic-aware highlight (error → accent1, warn → accent2, info → accent5,
    hint → accent5, plain → accent3)
  - Active buffer underlined with `accent3`
  - Smart truncation around the active buffer (left/right hidden counts shown as
    ` <N> … ` markers)
- **Tabpages section**: when 2+ tabpages exist, right-aligned (`%=`) list of tab numbers
  (`%<N>T <N> %T`). Active tab uses active highlight, others use inactive.
- Clicks:
  - Left-click on a buffer tab → switch to that buffer
  - Middle-click on a buffer tab → close that buffer (uses `Buffer.delete`, the global
    set in `lua/beast/init.lua`)
  - Left-click on the close button → close the buffer
- "Effective active buffer" tracking: when focus is on a sidebar, the most recently
  focused **listed file** buffer keeps the active tab styling — sidebar focus does not
  blank the tabline highlight.
- Hide `[No Name]` buffers that have not been modified (avoids the "ghost" buffer that
  Neovim creates at startup).
- Helpers exposed on the public API for keymap integration:
  `goto_buffer(n)`, `cycle_next/prev()`, `move_next/prev()`.

### Non-Functional

- Render path must be cheap and bounded:
  - One pass over listed buffers per render (no nested calls to
    `vim.api.nvim_list_bufs` / `vim.diagnostic.get` per component, unlike the current
    heirline init function which calls them several times per render).
  - `vim.fn.strdisplaywidth` / `nvim_buf_get_name` results captured into render-local
    locals where they would otherwise be recomputed per-component.
- Highlight groups are **static** (defined once in `highlights.lua` like
  `notify` / `explorer` / `packer` / `key` / `confirm`):
  - `BeastTlBuffer{Selected,Visible}` (× diagnostic severity variants)
  - `BeastTlDiag{Error,Warn,Info,Hint}{Selected,Visible}`
  - `BeastTlTab{Selected,Visible}`, `BeastTlOffset`, `BeastTlTruncMarker`,
    `BeastTlModified`, `BeastTlCloseButton`, `BeastTlFill`
  - The only **lazy** helper is for icon coloring — see [Icon highlights](#icon-highlights).
- No `heirline` dependency in this library or anywhere on the tabline render path.
- Follows BeastVim library conventions:
  - State only mutated in `init.lua`
  - Frozen-by-metatable config in `config.lua`
  - Lazy autocmd registration via `ensure_autocmds()` guard
  - ColorScheme refresh via `M.highlight_modules` registry
  - Type prefix `Beast.Tabline.*`

### Out of Scope (deferred)

- Removing the heirline.nvim plugin spec — the user disables heirline themselves after
  the lib lands. The dev spec only stops *driving the tabline through heirline*; the
  plugin can keep loading so the existing statusline / winbar continue working until
  those are also migrated.
- Buffer pick-mode (jump to buffer by single key) — `bufferline.nvim`-style, not in the
  current heirline tabline either.
- Buffer groups / pinning — not in the current heirline tabline.
- Tab rename — not in the current heirline tabline.
- Tabline hover popup (filename preview) — not in the current heirline tabline.
- Migrating the **winbar** — separate dev spec.

## Research

### Repo Search

- Searched for: `tabline`, `redrawtabline`, `make_buflist`, `make_tablist`,
  `vim.o.tabline`, `Buffer.delete`, `is_sidebar_buf`, `get_unique_name`,
  `truncate_buffers`, `truncate_text`, `strdisplaywidth`
- Found:
  - **Existing heirline tabline** at `lua/beast/plugins/bars/tabline/`
    (`init.lua`, `components.lua`, `utils.lua`) — full reference for visual + behavioral
    parity. Algorithms in `utils.lua` (smart truncation around active buffer,
    `truncate_text`, `get_unique_name`) are sound and will be **reused**, ported as-is
    into the new lib's `truncate.lua` / `name.lua`.
  - **`beast.libs.statusline`** at `lua/beast/libs/statusline/` — the architectural
    blueprint for "native `%!` bar in BeastVim". Reuse:
    - The `setup() → ensure_autocmds() → vim.o.* = "%!..."` lifecycle
    - The `highlights.lua` pattern: clear/recreate on ColorScheme via
      `M.highlight_modules` registry in `lua/beast/init.lua`
    - The `config.lua` frozen-by-metatable pattern (read-only proxy,
      `setup(opts)` merges deep)
    - The `IGNORED_FILETYPES` idea (informs sidebar handling, but tabline keeps its own
      `sidebar_filetypes` map because the meaning differs — sidebars produce an offset
      header, not a "stay visible" rule)
    - The render pipeline shape: `build_ctx → assemble parts → table.concat`
  - **`Buffer.delete`** — set as a global in `lua/beast/init.lua:24`
    (`_G.Buffer = require("beast.libs.buf")`). Used by close-button click handlers.
    Note: the existing heirline tabline has **two latent bugs** here that this
    migration fixes:
    - `lua/beast/plugins/bars/tabline/components.lua:99` calls `Util.buf.delete` —
      but `Util` (`lua/beast/util/init.lua`) has no `.buf` field, so middle-click
      close was silently failing.
    - `lua/beast/plugins/bars/tabline/components.lua:223` calls
      `require("beast.util.buf").delete` — but the file is at `lua/beast/libs/buf.lua`,
      so left-click close was also failing.
    The new lib uses the `Buffer` global consistently in both regions.
  - **`Palette.get()`** at `lua/beast/util/palette.lua` — palette aliases
    (`accent1`, `text`, `dimmed3`, …) resolve via this. Reused by `highlights.lua`.
  - **`Util.colors.set_hl(prefix, groups)`** at `lua/beast/util/colors.lua:143` —
    declarative way to define a batch of highlights with a shared prefix; used by every
    other lib's `highlights.lua`. Will be used here too.
  - **`nvim-web-devicons`** — already required by the existing `tabline/utils.lua` for
    `get_icon_color`. Will be reused.
- Reuse opportunity: **Yes, heavily**.
  - The existing `utils.lua` algorithms (`truncate_buffers`, `truncate_text`,
    `get_unique_name`) are pure functions and will be ported with minor cleanup.
  - The existing `init.lua` helpers (`goto_buffer`, `cycle_next/prev`, `move_next/prev`,
    `last_active_bufnr` tracking) port as-is to the new public API.
  - Tabline's `highlights.lua` is structurally identical to the other Beast libs —
    only the group names change.

### Package Search

- Searched the Lua/Neovim ecosystem:
  - `bufferline.nvim` (~4400 LoC, full plugin) — closest match, but big feature surface
    we don't want (groups, pin, pick, hover, sort strategies, custom areas). Its
    `vim.o.tabline = "%!v:lua.nvim_bufferline()"` design and per-icon highlight
    composition are direct inspiration, but installing it would be a regression vs the
    leaner heirline tabline we already have.
  - `barbar.nvim` — even larger, animation-heavy, vimscript-tabline-string approach
    similar to ours but with much more state.
  - `tabby.nvim` — closer in size, but tab-page-centric (one entry per tabpage, not
    per buffer); doesn't match our buffer-tab UX.
  - `cokeline.nvim` — declarative components for buffer cells; nice abstraction but
    introduces a new component-tree concept we'd have to integrate.
- Decision: **Build native** under `beast/libs/tabline/`.
  - We already have a working visual design; the cost is migration, not redesign.
  - Reusing the statusline lib's conventions keeps the BeastVim libs uniform.
  - Bufferline.nvim's `vim.o.tabline = "%!..."` approach + heirline tabline's
    behaviour informs the design without taking either as a dependency.
  - No new third-party dependencies enter the codebase.

## Design Notes

### Render Pipeline

```
%! → tabline.render()
  1. ctx = build_render_ctx()          -- effective_active_buf, columns, sidebar_winid,
                                       -- sidebar_width, sidebar_title_or_nil,
                                       -- listed_buffers, names_by_buf,
                                       -- diag_by_buf (single global walk; see below)
  2. parts = {}
     parts ← offset.render(ctx)        -- "" or padded title for sidebar
     parts ← buffers.render(ctx)       -- truncation markers + buffer cells
     parts ← "%="                      -- right-align tabpages
     parts ← tabpages.render(ctx)      -- only if #tabpages >= 2
  3. parts ← "%#BeastTlFill#"          -- restore base hl after final cell
  4. return table.concat(parts)
```

The crucial difference vs the heirline tabline: **all per-buffer data
(unique names, diagnostic counts, modified flags) is computed once in step 1 and reused
across the buffers section**. The heirline implementation's `init` callbacks recomputed
each on every component evaluation.

### `Beast.Tabline.Context`

Built once per render in `context.lua`:

```lua
---@class Beast.Tabline.Context
---@field columns          integer                          vim.o.columns
---@field current_buf      integer                          nvim_get_current_buf()
---@field effective_active integer                          last listed-file buffer (sidebar-aware)
---@field sidebar_winid?   integer                          first window if it's a sidebar
---@field sidebar_width?   integer                          nvim_win_get_width
---@field sidebar_title?   string                           sidebar_filetypes[ft]
---@field listed_buffers   integer[]                        sorted, filtered (no [No Name])
---@field names_by_buf     table<integer, string>           unique disambiguated name per buf — eager
---@field diag_by_buf      table<integer, Beast.Tabline.DiagSummary>  built by single global vim.diagnostic.get() walk; nil entry == no diagnostics
---@field tabpages         integer[]                        nvim_list_tabpages()
---@field current_tabnr    integer                          nvim_get_current_tabpage()
---@field tabpages_width   integer                          exact width of the rendered tabpage list (0 if <2)
```

`names_by_buf` is computed via a **single O(N) pass** that batches all buffers (current
heirline implementation calls `get_unique_name` per buffer per render, repeating the
duplicate-detection scan inside each call → O(N²)).

Diagnostics are gathered via a **single global `vim.diagnostic.get()` walk per render**,
inspired by bufferline.nvim's `diagnostics.lua`:

```lua
---@class Beast.Tabline.DiagSummary
---@field severity integer        -- highest severity present (1=ERROR … 4=HINT)
---@field count    integer        -- total diagnostics on this buffer
---@field errors   table<integer, integer>  -- per-severity counts

local function build_diag_by_buf()
  local by_buf = {}
  for _, d in ipairs(vim.diagnostic.get()) do  -- nil = ALL buffers, one walk
    local entry = by_buf[d.bufnr]
    if not entry then
      entry = { severity = d.severity, count = 0, errors = {} }
      by_buf[d.bufnr] = entry
    end
    entry.count = entry.count + 1
    entry.errors[d.severity] = (entry.errors[d.severity] or 0) + 1
    if d.severity < entry.severity then entry.severity = d.severity end
  end
  return by_buf
end
```

Why this beats the per-buffer pattern:

- **One C-side call** instead of N (`vim.diagnostic.get(bufnr)` per cell). Bufferline
  proves this scales fine to 50+ buffers because LSP servers already debounce on the
  publish side.
- **No two-level cache**. The width estimator's binary "is diag column present?" check
  becomes `ctx.diag_by_buf[bufnr] ~= nil`. The cell renderer reads
  `ctx.diag_by_buf[bufnr]` directly for severity + count. No memoization closures, no
  dirty-bit cache to keep coherent.
- **Always fresh**. No stale entries to invalidate when buffers wipe, when servers
  reattach, or when `:DiagnosticReset` fires.

**Insert-mode skip** (matching bufferline): if
`vim.diagnostic.config().update_in_insert == false` *and* the editor is in insert mode,
`context.build` reuses the previous render's `diag_by_buf` (stashed on the module-level
`state` table). This skips the global walk during typing, which is when LSP traffic
peaks. Outside insert mode, every render re-walks.

`DiagnosticChanged` autocmd's only job is to call `vim.cmd("redrawtabline")` — no cache
invalidation, no dirty bits. The next render walks the fresh state.

`tabpages_width` is computed exactly from `ctx.tabpages` (each entry takes
`#tostring(n) + 3` cells for ` <n> ` plus 1 leading separator), so the buffer list's
available-width math doesn't drift when tabpages multiply.

### Section: Offset

Pure function in `sections/offset.lua`. Reads `sidebar_filetypes` from config; if the
first window's filetype matches, returns:

```lua
"%#BeastTlOffset#" .. centered_pad(title, sidebar_width) .. "%*"
```

Falls back to empty string when no sidebar is open. No state, no autocmds beyond what
the engine registers globally.

### Section: Buffers

Lives in `sections/buffer_list.lua`. Inputs: `ctx`. Steps:

1. Resolve the **anchor** = `ctx.effective_active` if it's in `listed_buffers`, else the
   first listed buffer.
2. Compute available width = `ctx.columns - (ctx.sidebar_width or 0) - ctx.tabpages_width
   - 2 * marker_reserve`. Note `ctx.tabpages_width` is **exact** (computed from the real
   `ctx.tabpages` list — not a fixed reserve), so opening many tabpages doesn't
   silently overlap the buffer list.
3. `truncate.fit_around_anchor(before, anchor, after, est_width_fn, available)` — a
   port of the existing `utils.truncate_buffers` algorithm. Returns
   `(visible_buffers, left_hidden_count, right_hidden_count)`.
4. **Anchor-overflow fallback**: if `est_width_fn(anchor, true) > available`, shrink the
   anchor's name down to whatever fits (icon + truncated name + `…`), then return
   `(visible = {anchor}, left, right)` with hidden counts set so the user sees
   ` <N> … <NAME> … <M> ` instead of an overflowing cell.
5. For each visible buffer, render a cell via `cell.render(buf, ctx)` (one function,
   single pass over fragments).
6. Prepend `" <N> … "` left-truncation marker if `left_hidden_count > 0`; append
   `" <N> … "` right marker if `right_hidden_count > 0`.

The buffer cell layout (matching the existing heirline component, minus broadcast cost):

```
[buffer click region] [close click region]
└─ %{bufnr}@v:lua.beast_tabline_buffer_click@   └─ %{bufnr}@v:lua.beast_tabline_close_click@
   icon name diag/●  %X                            close-glyph %X  sep
```

Two **adjacent, non-nested** click regions per cell:

| Region        | Format                                                                                    |
|---------------|-------------------------------------------------------------------------------------------|
| Buffer body   | `"%" .. bufnr .. "@v:lua.beast_tabline_buffer_click@" .. icon_name_diag .. "%X"`          |
| Close button  | `"%" .. bufnr .. "@v:lua.beast_tabline_close_click@" .. close_glyph .. "%X"`              |

Two regions are required because Neovim's tabline click callback receives only
`(minwid, clicks, button, mods)` — there is no "which sub-region" information. Nesting
`%@…%X` inside another `%@…%X` is **not a documented mechanism** (`%X`/`%T` terminates
the *current* label, not "the inner one"). Keeping the regions adjacent and separate is
the only correct way to disambiguate "click on cell" vs "click on close glyph".

The two global functions are registered once in `init.lua`'s `setup()` (see
[Click Handlers](#click-handlers)).

Highlight selection per cell:

| State                  | Group                        |
|------------------------|------------------------------|
| Active, no diagnostics | `BeastTlBufferSelected`      |
| Active + Error         | `BeastTlBufferSelectedError` |
| Active + Warn          | `BeastTlBufferSelectedWarn`  |
| Active + Info          | `BeastTlBufferSelectedInfo`  |
| Active + Hint          | `BeastTlBufferSelectedHint`  |
| Inactive variants      | `BeastTlBufferVisible*`      |
| Modified dot (active)  | `BeastTlModifiedSelected`    |
| Modified dot (inactive)| `BeastTlModifiedVisible`     |
| Close button           | `BeastTlCloseButton`         |

The modified dot needs **two** variants because the dot's bg must match its host cell
(`Selected` cell vs `Visible` cell have different bgs). A single `BeastTlModified` would
either visibly mismatch the cell bg on one of the two states, or force us to render the
dot inside the same fragment as the cell text (which we can't, because the dot's fg
differs).

These are all **static** groups, defined once in `highlights.lua`. No hash-based
generation à la statusline — exactly what the user asked for, mirroring the
`BufferLineSelected` / `BufferLineVisible` shape.

### Icon highlights

File icons need `{ fg = devicon_color, bg = active_or_inactive_bg }`. Devicon colors are
data-driven (one per filetype/extension), so we cannot statically pre-declare them all.
Solution (matching bufferline.nvim's approach): a tiny lazy helper in `icons.lua`:

```lua
-- icons.lua
local cache = {}
local function ensure(icon_color, is_active)
    local key = icon_color .. (is_active and "_S" or "_V")
    if cache[key] then return cache[key] end
    local name = "BeastTlIcon_" .. key:gsub("[^%w_]", "_")
    vim.api.nvim_set_hl(0, name, {
        fg = icon_color,
        bg = is_active and palette.background or palette.background_inactive,
    })
    cache[key] = name
    return name
end
```

- Bounded: one group per (devicon color × {active, inactive}). Real world ≈ 50–100
  groups total, hit on first render of each filetype.
- ColorScheme refresh: `highlights.lua` clears the cache and the groups before
  re-creating the static groups. Next render lazily rebuilds icon groups.
- This is the **only** dynamic-group code path in the lib; everything else is static.

### Section: Tabpages

Pure function in `sections/tabpages.lua`. Returns `""` unless `#tabpages >= 2`. Else
emits the right-aligned list with click regions:

```
%= [%<n>T %#BeastTlTab{Selected,Visible}# <n> %*] %T
```

The `%<n>T` … `%T` brackets are native tabline click regions Neovim handles for free —
no Lua callback needed.

### Highlights & ColorScheme

`highlights.lua` re-runs every time `lua/beast/init.lua`'s `M.reload_highlights()` is
invoked (i.e. on `ColorScheme`). Its body:

1. `icons.clear_cache()` — wipes per-color icon groups + cache table
2. `Util.colors.set_hl("BeastTl", { … })` — re-declares all static groups
3. `vim.cmd("redrawtabline")` — kick the tabline so groups are picked up immediately

`"beast.libs.tabline.highlights"` gets added to `M.highlight_modules` in
`lua/beast/init.lua` (alongside the existing 6 entries).

### Click Handlers

Two global functions are registered (under `_G`) in `init.lua` `setup()`. Both delete
paths use `vim.schedule` to avoid re-entrancy from the mouse-callback context (matches
what the existing heirline tabline does at
`lua/beast/plugins/bars/tabline/components.lua:95-100, 217-224`):

```lua
function _G.beast_tabline_buffer_click(bufnr, _, button, _)
    if button == "m" then
        vim.schedule(function() pcall(Buffer.delete, { buf = bufnr }) end)
    elseif button == "l" then
        vim.api.nvim_set_current_buf(bufnr)
    end
end

function _G.beast_tabline_close_click(bufnr, _, button, _)
    if button == "l" then
        vim.schedule(function() pcall(Buffer.delete, { buf = bufnr }) end)
    end
end
```

`Buffer` is the global exposed by `lua/beast/init.lua` (`Buffer = require("beast.libs.buf")`)
and is the same API the existing heirline tabline calls. Do **not** use `Util.buf` —
that namespace does not exist (`lua/beast/util/init.lua` does not expose a `.buf`
field).

Tab labels use Neovim's native `%<n>T … %T` so they don't need a Lua handler.

This keeps the click syntax in the format string trivial — two adjacent `%@…@…%X`
regions per cell — and avoids heirline's `on_click` subscription / dispatcher table
entirely.

### Public API helpers

`init.lua` exposes the existing keymap-bound helpers, ported from
`lua/beast/plugins/bars/tabline/init.lua` largely as-is:

- `M.goto_buffer(n)` — `nvim_set_current_buf` to the n-th listed buffer
- `M.cycle_next() / M.cycle_prev()` — `vim.cmd("bnext|bprevious")`
- `M.move_next() / M.move_prev()` — swap `b:buffer_order` between adjacent buffers,
  `redrawtabline`

The `b:buffer_order` mechanism stays — sorters that respect this var preserve the
user's manual ordering across redraws.

### Performance Wins vs Heirline

| Concern                                 | Heirline (current)                              | Beast.Tabline (new)                             |
|-----------------------------------------|-------------------------------------------------|-------------------------------------------------|
| Buffer list scan                        | 3+ times per render (init, truncate, cell init) | 1 time per render (in `context.build`)          |
| `get_unique_name`                       | O(N²): called per cell, scans all bufs          | O(N) once: built into a `names_by_buf` table    |
| Diagnostic counts                       | `vim.diagnostic.get(bufnr)` per cell, every render | Single `vim.diagnostic.get()` walk, bucketed by bufnr; insert-mode skip |
| Component-tree traversal                | Every render walks heirline's nested components | Single function, linear assembly                |
| Per-cell `init` + `provider` + `hl`     | 3 closures called per cell                      | 1 function `cell.render(buf, ctx)`              |
| Highlight resolution                    | Heirline computes & caches table-form HLs       | `%#GroupName#` literal in format string         |
| Click handler dispatch                  | Heirline's `make_click_callback` table          | Native `%@func@…%X`                             |
| Global-state broadcast on ColorScheme   | `heirline.statusline:broadcast(...)` walks tree | `vim.cmd("redrawtabline")` after cache clear    |

## Architecture

### File Layout

```
lua/beast/libs/tabline/
├── init.lua            ← public API, state owner, render(), autocmd registration,
│                         _G click handlers, setup() (idempotent)
├── config.lua          ← defaults + frozen-by-metatable + setup(opts)
├── context.lua         ← build_render_ctx() — single pass over buffers,
│                         single global vim.diagnostic.get() walk (insert-mode skip),
│                         exact tabpages_width
├── highlights.lua      ← static BeastTl* groups + icons.clear_cache + redrawtabline
├── icons.lua           ← lazy per-(devicon-color × active|inactive) groups + cache
├── name.lua            ← unique-name disambiguation (port of utils.get_unique_name),
│                         truncate_text helper
├── truncate.lua        ← fit_around_anchor(before, anchor, after, …) — port of
│                         utils.truncate_buffers — and the per-buffer width estimator
│                         (`estimate_cell_width(bufnr, ctx, is_anchor)`)
├── buffers.lua         ← buffer-list logic: filter, sort, anchor, hide [No Name]
└── sections/
    ├── init.lua        ← barrel
    ├── offset.lua      ← sidebar offset section
    ├── cell.lua        ← render(bufnr, ctx) → tabline format string for one cell;
    │                     emits two adjacent %@…@…%X regions (body + close)
    ├── buffer_list.lua ← orchestrates truncation + cell.render + truncation markers,
    │                     anchor-overflow fallback (shrink anchor if it alone overflows)
    └── tabpages.lua    ← right-aligned tabpage list
```

### Dependency Flow

```
init.lua  ──→ config, context, highlights, icons, sections.{offset,buffer_list,tabpages}
context.lua ──→ buffers, name, config
sections/buffer_list.lua ──→ sections/cell, truncate, config
sections/cell.lua ──→ icons, name, config
sections/offset.lua ──→ config
sections/tabpages.lua ──→ config
truncate.lua ──→ name, config
buffers.lua ──→ config (sidebar_filetypes lookup)
highlights.lua ──→ icons (cache clear) + Util.colors.set_hl + Palette.get
```

No file requires anything above it. `init.lua` is the only file that pulls multiple
siblings.

### Type Names (Beast.Tabline.\*)

```lua
---@class Beast.Tabline.Config
---@class Beast.Tabline.Context
---@class Beast.Tabline.DiagCounts
---@class Beast.Tabline.Section
```

### Config Defaults

```lua
local defaults = {
    -- Buffer cell appearance
    max_name_width = 24,
    show_close_button = true,
    show_modified = true,
    show_diagnostics = true,

    -- Sidebar offset
    -- ft → title to render in the offset block.
    -- Empty string keeps the offset width but renders nothing (used by beast-explorer).
    sidebar_filetypes = {
        ["neo-tree"]       = "EXPLORER",
        ["NvimTree"]       = "EXPLORER",
        ["beast-explorer"] = "",
    },

    -- Reserved cells for "<N> …" truncation markers on either side of the buffer list.
    -- (Tabpages width is computed *exactly* per render — never reserved.)
    truncation_marker_reserve = 8,
}
```

## Implementation Phases

### Phase 1: Minimal viable tabline — boots, renders a flat buffer list, click works

True minimum: a flat unbounded buffer list with click-to-switch and middle-click-close,
no offset, no tabpages, no truncation. After this phase, `:lua require("beast.libs.tabline").setup({})`
paints buffer cells and you can click between them.

1. **Create `config.lua`** (File: `lua/beast/libs/tabline/config.lua`)
   - Action: Define `defaults`, `cfg = vim.deepcopy(defaults)`, `methods.setup(opts)`
     using `vim.tbl_deep_extend("force", …)`. Wrap with the read-only metatable
     pattern (mirror `statusline/config.lua`). Re-running `setup()` must replace `cfg`
     cleanly without leaking state.
   - Why: Every other module reads `config.<key>` directly.
   - Depends on: None
   - Risk: Low

2. **Create `highlights.lua`** (File: `lua/beast/libs/tabline/highlights.lua`)
   - Action: Use `Util.colors.set_hl("BeastTl", { … })` to declare:
     `BufferSelected`, `BufferVisible`, `BufferSelected{Error,Warn,Info,Hint}`,
     `BufferVisible{Error,Warn,Info,Hint}`, `Diag{Error,Warn,Info,Hint}{Selected,Visible}`,
     `Tab{Selected,Visible}`, `Offset`, `OffsetSeparator`, **`ModifiedSelected`**,
     **`ModifiedVisible`**, `CloseButton`, `TruncMarker`, `Fill`. Source colors from
     `Palette.get()` matching the existing heirline `components.lua` `tab.*` table.
     Body must be safe to re-execute (no module-level side effects beyond
     `nvim_set_hl` calls + `icons.clear_cache()`).
   - Why: All static groups defined once, refreshed via `M.highlight_modules`.
   - Depends on: Step 1
   - Risk: Low

3. **Register in `M.highlight_modules`** (File: `lua/beast/init.lua`)
   - Action: Add `"beast.libs.tabline.highlights"` to the array.
   - Why: ColorScheme handler reloads it after `Palette.refresh()`.
   - Depends on: Step 2
   - Risk: Low

4. **Create `icons.lua`** (File: `lua/beast/libs/tabline/icons.lua`)
   - Action: Implement `M.ensure(icon_color, is_active) → group_name` with internal
     cache. Implement `M.clear_cache()` that pcall-clears all created groups and
     resets the cache.
   - Why: File icons need fg + bg merging, only feasible by creating groups on demand.
   - Depends on: None (palette read inside ensure)
   - Risk: Medium — needs to get the bg right relative to active/inactive states

5. **Create `name.lua`** (File: `lua/beast/libs/tabline/name.lua`)
   - Action: Port `get_unique_name` and `truncate_text` from
     `lua/beast/plugins/bars/tabline/utils.lua` verbatim, with two changes:
     (a) accept a `names_by_buf` accumulator table so the function can be called as
     part of a batched O(N) build, and
     (b) drop the per-call O(N) duplicate scan when batched.
   - Why: Disambiguation across buffers and ellipsis-truncation are pure helpers.
   - Depends on: None
   - Risk: Low

6. **Create `buffers.lua`** (File: `lua/beast/libs/tabline/buffers.lua`)
   - Action: Implement `list()` returning sorted listed buffers, hiding empty
     `[No Name]` buffers (no name + not modified). Implement `is_sidebar_buf(bufnr)`
     reading `config.sidebar_filetypes`. Honour `b:buffer_order` when set on every
     buffer (so `move_next/prev` ordering survives redraws).
   - Why: Used by `context.build` and by the offset/cell sections.
   - Depends on: Step 1 (sidebar_filetypes config)
   - Risk: Low

7. **Create `context.lua`** (File: `lua/beast/libs/tabline/context.lua`)
   - Action: Implement `M.build(state)` returning a `Beast.Tabline.Context`:
     list buffers → batch unique names → resolve sidebar window/title → build
     `diag_by_buf` via a single `vim.diagnostic.get()` walk and bucket per `bufnr`
     (see "Diagnostics" in Design Notes). Implement insert-mode skip: if
     `vim.api.nvim_get_mode().mode:find("^[iR]")` and
     `vim.diagnostic.config().update_in_insert == false`, reuse
     `state.last_diag_by_buf`; else stash the fresh result on `state.last_diag_by_buf`.
     `tabpages_width` defaults to `0` here; phase 2 fills it in.
   - Why: One render-time data assembly the whole pipeline shares; one C-call for all
     diagnostics rather than N per-buffer calls.
   - Depends on: Steps 5, 6
   - Risk: Low — `vim.diagnostic.get()` is O(total diags), which is what we already pay

8. **Create `sections/cell.lua`** (File: `lua/beast/libs/tabline/sections/cell.lua`)
   - Action: Implement `M.render(bufnr, ctx)` returning a tabline format string
     for one buffer cell. Composes:
     - **Region 1 (body)**: `"%" .. bufnr .. "@v:lua.beast_tabline_buffer_click@"` →
       padding + icon (using `icons.ensure(icon_color, is_active)`) + name +
       diag-count or `●` (modified) → `"%X"`
     - **Region 2 (close button)**: `"%" .. bufnr .. "@v:lua.beast_tabline_close_click@"`
       → `" 󰅖 "` on active, `"  "` placeholder on inactive (so layout doesn't shift) →
       `"%X "`
     - Highlight per state: lookup `(is_active, severity)` → static `BeastTlBuffer*`
       group. Diagnostic count uses `BeastTlDiag<sev><state>`. Modified dot uses
       `BeastTlModified{Selected,Visible}`.
   - Why: One function per cell, no closures, no broadcast.
   - Depends on: Steps 1, 4, 5, 7
   - Risk: Medium — most surface area; must match existing visual exactly

9. **Create `init.lua` skeleton** (File: `lua/beast/libs/tabline/init.lua`)
   - Action: `M.setup(opts)`, `M.render()`, state table (`last_active_bufnr`,
     `augroup`, `last_diag_by_buf: table<integer, Beast.Tabline.DiagSummary>?`),
     idempotent `ensure_autocmds()` guard (`if state.augroup then return end`).
     Autocmds:
     - `BufEnter` — track `last_active_bufnr` (skip sidebars + non-listed).
     - `DiagnosticChanged` — `vim.schedule(function() vim.cmd("redrawtabline") end)`.
       No cache to invalidate; `context.build` re-walks `vim.diagnostic.get()`. The
       `vim.schedule` collapses bursts (multiple LSP servers publishing in the same
       tick) into a single redraw — same coalescing trick bufferline uses.
     - `BufWinEnter`, `BufWinLeave`, `WinResized`, `WinClosed`, `BufAdd`, `BufDelete`,
       `BufModifiedSet` — `vim.schedule(redrawtabline)` for layout-changing events
       (matches the existing impl).
     - Set `vim.o.showtabline = 2` and
       `vim.o.tabline = "%!v:lua.require'beast.libs.tabline'.render()"`.
     - Register `_G.beast_tabline_buffer_click` and `_G.beast_tabline_close_click`
       (overwriting any prior values is safe; idempotent re-`setup()` just rebinds).
   - `M.render()` for phase 1: build ctx, iterate `ctx.listed_buffers`, concat
     `cell.render(bufnr, ctx)` for each, append `"%#BeastTlFill#"`. **No truncation,
     no offset, no tabpages yet.**
   - Why: Bootable end-to-end slice.
   - Depends on: Steps 1, 7, 8
   - Risk: Medium — the click globals and autocmd timing decide if the lib *feels*
     like the heirline tabline

After phase 1: tabline renders, switches buffers on click (region 1), closes on
middle-click on cell or left-click on close button (region 2), respects active
highlight, refreshes on diagnostics; truncation, offset, and tabpages still missing.

### Phase 2: Truncation + Width — buffer list survives narrow windows

10. **Create `truncate.lua`** (File: `lua/beast/libs/tabline/truncate.lua`)
    - Action: Implement `M.estimate_cell_width(bufnr, ctx, is_anchor)` (port of
      the heirline `estimate_width` helper, taking `ctx` instead of re-fetching
      state — uses `ctx.diag_by_buf[bufnr] ~= nil` for the binary "is diag column
      present?" check; never reads `count`/`severity` here). Implement
      `M.fit_around_anchor(before, anchor, after, est_fn, available)` (port of
      `truncate_buffers`). Return `(visible, left_hidden, right_hidden)`.
    - Why: Smart truncation around the anchor is already correct in the heirline
      impl; just lift it.
    - Depends on: Step 7
    - Risk: Low

11. **Create `sections/buffer_list.lua`** (File: `lua/beast/libs/tabline/sections/buffer_list.lua`)
    - Action: Implement `M.render(ctx)`:
      1. Compute `available = ctx.columns - (ctx.sidebar_width or 0) -
         ctx.tabpages_width - 2 * config.truncation_marker_reserve`.
      2. Anchor = `ctx.effective_active` if listed, else `ctx.listed_buffers[1]`.
      3. **Anchor-overflow fallback**: if
         `truncate.estimate_cell_width(anchor, ctx, true) > available`, render only
         the anchor with name truncated to `available - non_name_overhead`, and emit
         markers showing `len(before)` left and `len(after)` right. Skip the normal
         truncate call.
      4. Else call `truncate.fit_around_anchor(...)`, then render markers around
         `cell.render` calls.
    - Why: Coordinates the buffers section.
    - Depends on: Steps 8, 10
    - Risk: Medium — anchor-overflow fallback is new logic vs heirline impl

12. **Wire into `init.lua`'s `render()`** (File: `lua/beast/libs/tabline/init.lua`)
    - Action: Replace the flat-loop body of `M.render()` with `buffer_list.render(ctx)`.
    - Why: Drops phase 1's flat list in favour of truncation-aware layout.
    - Depends on: Step 11
    - Risk: Low

### Phase 3: Offset + Tabpages — visual parity with heirline tabline

13. **Create `sections/offset.lua`** (File: `lua/beast/libs/tabline/sections/offset.lua`)
    - Action: Implement `M.render(ctx)`. If `ctx.sidebar_winid`, return centered title
      string at `ctx.sidebar_width`, wrapped in `%#BeastTlOffset#…%*`. Empty-string
      title (e.g. `beast-explorer`) reserves width but emits only spaces.
    - Why: Aligns buffer list with the editor's split column.
    - Depends on: Step 12
    - Risk: Low

14. **Create `sections/tabpages.lua`** (File: `lua/beast/libs/tabline/sections/tabpages.lua`)
    - Action: Implement `M.render(ctx)`. If `< 2` tabpages, return `""`. Else build the
      right-aligned tab list using native `%<n>T …%T` regions and
      `BeastTlTab{Selected,Visible}` highlights.
    - Why: Tab nav surface.
    - Depends on: Step 12
    - Risk: Low

15. **Add exact tabpages_width computation** (File: `lua/beast/libs/tabline/context.lua`)
    - Action: Compute `ctx.tabpages_width` exactly from `ctx.tabpages` so
      `buffer_list.render` accounts for real tabpages width (not the phase-1 zero).
    - Why: Prevents the buffer list from overlapping the tabpages list.
    - Depends on: Step 14
    - Risk: Low

16. **Wire offset + tabpages into `init.lua` render()** (File: `lua/beast/libs/tabline/init.lua`)
    - Action: Update `M.render()` to assemble: `offset.render(ctx)` →
      `buffer_list.render(ctx)` → `"%="` → `tabpages.render(ctx)` →
      `"%#BeastTlFill#"`.
    - Why: Final layout.
    - Depends on: Steps 13, 14, 15
    - Risk: Low

### Phase 4: Public API helpers + smoke test — lib stands on its own

17. **Port navigation helpers** (File: `lua/beast/libs/tabline/init.lua`)
    - Action: Add `M.goto_buffer(n)`, `M.cycle_next/prev()`, `M.move_next/prev()`,
      `M.get_visible_buffers()`, `M.get_truncation_counts()`. Port from the
      existing heirline impl largely verbatim (functions are pure of heirline state).
      `move_next/prev` set `b:buffer_order` and `redrawtabline`.
    - Why: Public surface for the eventual cutover (which the user owns and is **not**
      part of this dev spec).
    - Depends on: Step 16
    - Risk: Low

18. **Lib smoke test in isolation** (File: N/A — verification only)
    - Action: With the existing heirline tabline still active, exercise the new lib
      out-of-band:
      - `:lua require("beast.libs.tabline").setup({})` — confirms no errors, autocmds
        register, `_G` click handlers register.
      - `:lua print(require("beast.libs.tabline").render())` — confirms render returns
        a non-empty format string (Note: `setup()` will overwrite `vim.o.tabline`, so
        the new lib *will* drive the tabline once setup runs. To roll back without a
        restart, save `vim.o.tabline` before calling `setup()` and restore it after).
      - Visually check: ≥10 buffers, click-to-switch, middle-click close, close-button
        click, narrow window truncation, sidebar offset, second tabpage, colorscheme
        swap → all match the existing heirline tabline.
      - Run nav helpers: `:lua require("beast.libs.tabline").goto_buffer(2)`, etc.
    - Why: No automated tests in repo; manual passes are the contract. The lib must be
      proven correct in isolation before the user does the cutover on their side.
    - Depends on: Step 17
    - Risk: Low

> **Out of scope for this dev spec**: any change under `lua/beast/plugins/`. The user
> will disable the heirline tabline driver and wire `bars/init.lua` to the new lib on
> their own schedule. Until they do, the new lib is fully built and verifiable but not
> the actual tabline driver — invoking `setup()` is opt-in.

## Testing Strategy

- **Unit tests**: none (no test framework in repo).
- **Manual verification**:
  - `:lua print(require("beast.libs.tabline").render())` — exercises the render path
    out-of-band.
  - Open ≥10 buffers; verify left/right truncation markers show counts when window is
    narrow.
  - Focus a `beast-explorer` window; confirm offset block renders and last-active
    file buffer keeps the active highlight.
  - Trigger LSP diagnostics on a buffer; confirm the cell flips to the matching
    severity color and shows the count.
  - `:bd` a buffer; confirm tabline updates without artifact.
  - Middle-click on a buffer cell → buffer closes (Buffer.delete confirm path
    works).
  - Click the close icon on the active buffer → closes via the same path.
  - Add a second tabpage; confirm right-aligned tab list appears, click switches tabs,
    `%T` regions work natively (no Lua handler).
  - Run `:colorscheme monokai-pro` (or any other) → verify groups rebuild and tabline
    re-renders correctly without restart.
  - Invoke nav helpers directly:
    `:lua require("beast.libs.tabline").goto_buffer(2)`,
    `:lua require("beast.libs.tabline").cycle_next()`,
    `:lua require("beast.libs.tabline").move_next()`. (User keymaps in `bars/init.lua`
    still point at the old heirline impl until the user's separate cutover; not tested
    here.)

## Risks & Mitigations

- **Risk**: Native `%@…@…%X` click syntax is fussier than heirline's `on_click` —
  malformed sequences silently break the cell layout. → **Mitigation**: keep the
  click-region helper centralized in `cell.lua`; emit two **adjacent, non-nested**
  regions (body + close); smoke-test all interactions during Phase 1.
- **Risk**: Icon group caching might leak groups across colorscheme changes if
  `clear_cache` doesn't fire. → **Mitigation**: `highlights.lua` calls
  `icons.clear_cache()` first; `M.reload_highlights()` re-requires the module so
  the body always runs.
- **Risk**: `vim.diagnostic.get()` (no args) walks all diagnostics across all buffers
  every render. → **Mitigation**: it's a single C-level walk over an array LSP
  servers already keep small (debounced on publish). Bufferline.nvim ships this exact
  approach to thousands of users. The width estimator only needs the binary
  `ctx.diag_by_buf[bufnr] ~= nil`; cells read severity/count by direct table index.
- **Risk**: Diagnostic walk during heavy LSP activity (typing) is wasteful since each
  keystroke can re-publish diagnostics. → **Mitigation**: insert-mode skip in
  `context.build` reuses `state.last_diag_by_buf` when
  `vim.diagnostic.config().update_in_insert == false`. Same trick bufferline uses
  (`diagnostics.lua:147-149`).
- **Risk**: `DiagnosticChanged` autocmd may fire many times per tick (multiple LSP
  servers, multiple namespaces). → **Mitigation**: handler calls
  `vim.schedule(redrawtabline)`; the scheduler collapses concurrent calls in the same
  tick into one redraw, same coalescing trick bufferline uses.
- **Risk**: Anchor buffer's own width exceeds available width on extremely narrow
  screens. → **Mitigation**: explicit anchor-overflow fallback in
  `sections/buffer_list.render` (Phase 2 step 11): shrink the anchor's name to fit and
  still emit truncation markers showing `len(before)` / `len(after)`.
- **Risk**: `tabpages_reserve` constant drifts from real tabpages width with many
  tabpages. → **Mitigation**: removed the reserve. `ctx.tabpages_width` is computed
  exactly from `ctx.tabpages` per render.
- **Risk**: `b:buffer_order` consumed by the existing `move_*` helpers but never read
  by our `buffers.list` sort. → **Mitigation**: in `buffers.list`, when **every**
  buffer carries a `b:buffer_order`, sort by it; otherwise fall back to
  `table.sort(bufs)`. This matches the silent contract the heirline impl had.
- **Risk**: Heirline keeps rendering the tabline until the user does their own cutover
  outside this dev spec. → **Mitigation**: the lib is opt-in — only calling `setup()`
  flips `vim.o.tabline`. Until then the lib is fully built but dormant. Step 18's
  smoke test instructions describe a manual-rollback recipe (stash + restore
  `vim.o.tabline`) so the user can sanity-check the lib without committing.
- **Risk**: `setup()` may re-run on `ColorScheme` later (when the user wires the lib
  through `bars/init.lua`'s `load()` reload path). → **Mitigation**: `setup()` is
  idempotent — `ensure_autocmds()` guards on `state.augroup`, config deep-merges
  cleanly, `vim.o.tabline` re-assignment is a no-op, and `_G` click handler rebinds
  are safe.
- **Risk**: Click delete callback runs in mouse-callback context; `Buffer.delete` may
  prompt or replace windows mid-callback. → **Mitigation**: both delete callbacks wrap
  the delete in `vim.schedule(function() pcall(Buffer.delete, …) end)` (matching the
  existing heirline tabline at
  `lua/beast/plugins/bars/tabline/components.lua:95-100, 217-224`).

## Success Criteria

- [ ] `:lua print(require("beast.libs.tabline").render())` returns a non-empty format
  string composed of `%#BeastTl*#…%*` segments and `%@…@…%X` click regions — works
  even when the lib is not driving the tabline
- [ ] After `setup()`, `vim.o.tabline` is `"%!v:lua.require'beast.libs.tabline'.render()"`
- [ ] All static groups (`BeastTl*`) exist after `:colorscheme X`; verifiable via
  `:hi BeastTlBufferSelected`
- [ ] No `heirline` require sits on the tabline render path (`grep -r 'heirline'
  lua/beast/libs/tabline/` returns nothing)
- [ ] No file under `lua/beast/plugins/` is modified by this dev spec (`git diff
  lua/beast/plugins/` is empty after Phase 4)
- [ ] Diagnostic, modified, sidebar, truncation, and tabpages behaviors match the
  heirline tabline pixel-for-pixel during the smoke test
- [ ] Nav helpers `goto_buffer`, `cycle_*`, `move_*` callable directly via
  `require("beast.libs.tabline").<helper>(...)` without errors
- [ ] ColorScheme change rebuilds highlights without restart (verified by running
  `M.reload_highlights()` after `:colorscheme X`)
- [ ] Render time per call < heirline tabline's render time, measurable via
  `:lua local s=vim.uv.hrtime(); require("beast.libs.tabline").render(); print((vim.uv.hrtime()-s)/1e6, "ms")`

## ADR Required

- **Native `%!` tabline driver replaces heirline.nvim for tabline** — same architectural
  decision class as the statusline migration; document together or as a sibling ADR.
- **Static `BeastTl*` highlight groups instead of dynamic hash-named groups** — explicit
  divergence from `beast.libs.statusline`'s `hlgroup.lua` pattern; rationale: tabline's
  state-space is small and finite (active/inactive × severity), so static groups +
  one lazy icon-color helper match bufferline.nvim's proven approach and keep the lib
  simpler.
- **Render-time `Beast.Tabline.Context` shared across sections** — establishes the
  pattern of one-time data assembly per render, reusable for a future winbar lib.
- **Tabline lib does NOT extract `hlgroup` shared module** — explicit decision not to
  hoist the dynamic group-creator from `beast.libs.statusline` into a shared module
  yet. Update the **DRY Opportunities** section in `BeastVim Library Conventions` to
  note that `hlgroup` remains statusline-specific.

## References

- bufferline.nvim: ~/.local/share/nvim/lazy/bufferline.nvim
- heirline.nvim: ~/.local/share/nvim/lazy/heirline.nvim

## Proposed Work Items

> Today: **2026-05-03** (Sun). Workdays: Mon–Fri only. Same-phase tasks may overlap on the same day; next phase starts after the prior phase's last day.

| #  | Title                                          | Type | Priority | Est. Hours | Start  | End    | Proposed Owner | Description                                                                                                                                                                       | Phase   |
|----|------------------------------------------------|------|----------|-----------:|--------|--------|----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| 1  | Create config module                           | Task | P1       | 1h         | May 4  | May 4  | loctvl842      | `lua/beast/libs/tabline/config.lua` — defaults + read-only metatable + idempotent `setup(opts)`. Mirror `statusline/config.lua`. Acceptance: re-running `setup()` replaces `cfg` cleanly. | Phase 1 |
| 2  | Create static highlight groups                 | Task | P1       | 2h         | May 4  | May 4  | loctvl842      | `lua/beast/libs/tabline/highlights.lua` — ~20 `BeastTl*` groups via `Util.colors.set_hl`. Body must be re-executable. Acceptance: `:hi BeastTlBufferSelected` resolves. | Phase 1 |
| 3  | Register highlights in reload registry         | Task | P1       | 0.5h       | May 4  | May 4  | loctvl842      | `lua/beast/init.lua` — append `"beast.libs.tabline.highlights"` to `M.highlight_modules`. Acceptance: `M.reload_highlights()` rebuilds tabline groups after `:colorscheme`. | Phase 1 |
| 4  | Create lazy icon-color module                  | Task | P1       | 2h         | May 4  | May 4  | loctvl842      | `lua/beast/libs/tabline/icons.lua` — `ensure(icon_color, is_active)` + `clear_cache()` with internal cache. Acceptance: file icons keep correct fg + cell bg in both states. | Phase 1 |
| 5  | Port unique-name + truncate_text helpers       | Task | P1       | 1h         | May 4  | May 4  | loctvl842      | `lua/beast/libs/tabline/name.lua` — port `get_unique_name`/`truncate_text` from `plugins/bars/tabline/utils.lua`; switch to batched O(N) accumulator. | Phase 1 |
| 6  | Create buffer-list module                      | Task | P1       | 1h         | May 4  | May 4  | loctvl842      | `lua/beast/libs/tabline/buffers.lua` — `list()`, `is_sidebar_buf(bufnr)`, honour `b:buffer_order` when set on every listed buffer. | Phase 1 |
| 7  | Create context builder                         | Task | P1       | 2h         | May 5  | May 5  | loctvl842      | `lua/beast/libs/tabline/context.lua` — `build(state)`. Single `vim.diagnostic.get()` walk → `diag_by_buf`. Insert-mode skip reuses `state.last_diag_by_buf`. | Phase 1 |
| 8  | Create cell renderer                           | Task | P1       | 4h         | May 5  | May 5  | loctvl842      | `lua/beast/libs/tabline/sections/cell.lua` — `render(bufnr, ctx)`. Two **adjacent, non-nested** `%@…@…%X` regions: body (buffer click) + close (close-button click). Static `BeastTlBuffer*`, `BeastTlDiag*`, `BeastTlModified*` groups. | Phase 1 |
| 9  | Create init.lua skeleton + autocmds            | Task | P1       | 3h         | May 6  | May 6  | loctvl842      | `lua/beast/libs/tabline/init.lua` — `setup(opts)`, `render()`, idempotent `ensure_autocmds()`. Register `_G.beast_tabline_buffer_click` and `_G.beast_tabline_close_click` (both wrap delete in `vim.schedule(pcall(Buffer.delete, …))`). Sets `vim.o.tabline`. | Phase 1 |
| 10 | Port truncation engine                         | Task | P1       | 2h         | May 7  | May 7  | loctvl842      | `lua/beast/libs/tabline/truncate.lua` — `estimate_cell_width(bufnr, ctx, is_anchor)` (uses `ctx.diag_by_buf[bufnr] ~= nil` binary check) and `fit_around_anchor(...)` (port of `truncate_buffers`). | Phase 2 |
| 11 | Buffer-list section with anchor-overflow       | Task | P1       | 3h         | May 7  | May 7  | loctvl842      | `lua/beast/libs/tabline/sections/buffer_list.lua` — `render(ctx)`. New anchor-overflow fallback: when anchor estimate > available, shrink anchor name to fit + emit markers `len(before)` / `len(after)`. | Phase 2 |
| 12 | Wire truncation into render()                  | Task | P1       | 0.5h       | May 7  | May 7  | loctvl842      | `lua/beast/libs/tabline/init.lua` — replace Phase 1's flat loop with `buffer_list.render(ctx)`. | Phase 2 |
| 13 | Create offset section                          | Task | P2       | 1h         | May 8  | May 8  | loctvl842      | `lua/beast/libs/tabline/sections/offset.lua` — `render(ctx)`: centered sidebar title at `ctx.sidebar_width`, wrapped in `%#BeastTlOffset#…%*`. Empty-string title reserves width only. | Phase 3 |
| 14 | Create tabpages section                        | Task | P2       | 1.5h       | May 8  | May 8  | loctvl842      | `lua/beast/libs/tabline/sections/tabpages.lua` — `render(ctx)`: native `%<n>T …%T` regions; returns `""` if `< 2` tabpages. | Phase 3 |
| 15 | Compute exact tabpages_width in context        | Task | P2       | 1h         | May 8  | May 8  | loctvl842      | `lua/beast/libs/tabline/context.lua` — fill `ctx.tabpages_width` exactly from `ctx.tabpages`. Removes the dropped `tabpages_reserve` constant. | Phase 3 |
| 16 | Wire offset+tabpages into render()             | Task | P2       | 0.5h       | May 8  | May 8  | loctvl842      | `lua/beast/libs/tabline/init.lua` — final assembly: `offset.render → buffer_list.render → "%=" → tabpages.render → "%#BeastTlFill#"`. | Phase 3 |
| 17 | Port nav helpers                               | Task | P1       | 2h         | May 11 | May 11 | loctvl842      | `lua/beast/libs/tabline/init.lua` — `goto_buffer(n)`, `cycle_next/prev`, `move_next/prev` (sets `b:buffer_order` + `redrawtabline`), `get_visible_buffers`, `get_truncation_counts`. | Phase 4 |
| 18 | Lib smoke test in isolation                    | Task | P1       | 2h         | May 11 | May 11 | loctvl842      | N/A — verification only. Run `setup()`, render(), nav helpers; visually verify against the existing heirline tabline. **No changes under `lua/beast/plugins/`** — cutover is out of scope. | Phase 4 |

**Total: 30h | Start: May 4 | End: May 11**
