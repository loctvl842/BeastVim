<!-- Generated: 2026-05-17 | Files scanned: 151 | Token estimate: ~2100 -->

# Libraries

## explorer — File Explorer (split panel)

```
explorer/
├── init.lua       ← open/close/toggle, setup, replace_netrw
├── config.lua     ← style, width, side, icons, sticky, mappings
├── state.lua      ← tree, view, sticky, source_win, augroup
├── tree.lua       ← filesystem tree with flat cache
├── ui.lua         ← create split window, focus_path, render
├── render.lua     ← draw tree nodes to buffer
├── sticky.lua     ← floating ancestor headers (cursor-anchored)
├── prompt.lua     ← inline input prompt (create/rename)
├── keymaps.lua    ← mount action keymaps
├── autocmds.lua   ← BufEnter/WinClosed/WinScrolled/CursorMoved handlers
├── highlights.lua ← BeastExplorer* groups
└── actions/       ← one file per action
    ├── open.lua, create.lua, delete.lua, rename.lua
    ├── set_root.lua, navigate_up.lua, show_hidden.lua
    ├── copy_to_clipboard.lua, cut_to_clipboard.lua
    └── paste_from_clipboard.lua
```

API: `explorer.open(dir)`, `explorer.close()`, `explorer.toggle(cwd)`
Loaded via: `packer.lazy()` on VimEnter (deferred) + `<leader>e` keymap

### Sticky ancestor headers (`sticky.lua`)

Floating overlay pinning ancestor directories above the visible region.
View subclass: `Beast.Explorer.StickyView : Beast.View`.
Pin rule iterates to fixed point; sets `scrolloff` to keep cursor below float.

---

## finder — Fuzzy Finder

```
finder/
├── init.lua       ← open(source, opts), setup()
├── config.lua     ← width, height, preview_ratio, debounce, matcher opts
├── query.lua      ← Query class: layout, source loading, batch flush, rematch
├── filter.lua     ← Filter class: pattern + cwd state
├── matcher.lua    ← fuzzy matching (smartcase, scoring, positions)
├── format.lua     ← per-source display formatters (filename, live_grep, help_tags, …)
├── match_hl.lua   ← fuzzy match highlight extmarks (list + preview)
├── action.lua     ← open, open_help, open_split, open_vsplit, copy_path
├── keymaps.lua    ← input/list/preview pane keymaps + printable-char redirect
├── autocmds.lua   ← picker lifetime autocmds (BufEnter, WinClosed)
├── highlights.lua ← BeastFinder* groups
├── source/
│   ├── init.lua       ← lazy registry (__index → require source.<name>)
│   ├── files.lua      ← async (fd/rg/find via uv.spawn)
│   ├── buffers.lua    ← sync (getbufinfo)
│   ├── live_grep.lua  ← live async (rg with pattern)
│   ├── colorschemes.lua ← sync (rtp-only globpath)
│   └── help_tags.lua  ← sync (rtp-only tag parsing)
└── ui/
    ├── init.lua     ← barrel (input, list, preview, backdrop)
    ├── input.lua    ← prompt buffer + debounced TextChanged
    ├── list.lua     ← rendered items + cursor + selection prefix
    ├── preview.lua  ← file preview with filetype detection
    └── backdrop.lua ← fullscreen dim overlay
```

API: `finder.open("files", opts)`, `finder.open("live_grep")`, `finder.open("help_tags")`
View subclasses: `Beast.Finder.InputView`, `Beast.Finder.ListView`, `Beast.Finder.PreviewView`
Loaded via: `packer.lazy()` on keys (`<leader>f/b/g/c/h`)

### Query lifecycle

```
Query:new(source_name, opts)
  → calc_layout(has_preview) → create input/list/preview views
  → mount keymaps → load source (sync or async batch)
  → rematch → render list → schedule_preview
```

Sources: `files` (async, fd/rg/find), `buffers` (sync), `live_grep` (live async),
`colorschemes` (sync, rtp-only), `help_tags` (sync, rtp-only — loaded plugins only).

---

## tabline — Native `%!` Tabline

```
tabline/
├── init.lua           ← setup(), render(), autocmds, click handlers, nav helpers
├── config.lua         ← max_name_width, min_cell_width, sidebar_filetypes, etc.
├── context.lua        ← build per-render ctx: buffers, names, icons, diags, sidebar
├── buffers.lua        ← list() via getbufinfo, is_sidebar_buf, sidebar_title
├── name.lua           ← O(N) unique-name disambiguation, truncate_text
├── truncate.lua       ← estimate_cell_width, fit_around_anchor (anchor-based)
├── icons.lua          ← lazy per-(color × state) highlight groups
├── highlights.lua     ← BeastTl* static groups (3-state: Selected/Visible/Normal)
└── sections/
    ├── cell.lua         ← single buffer cell (two click regions: body + close)
    ├── buffer_list.lua  ← truncation orchestrator with smart marker reserve
    ├── offset.lua       ← centered sidebar title
    └── tabpages.lua     ← right-aligned tab indicators with %nT click regions
```

API: `tabline.setup(opts)`, `tabline.render()` (via `%!v:lua`),
`tabline.goto_buffer(n)`, `tabline.cycle_next/prev()`, `tabline.move_next/prev()`
Loaded via: `packer.lazy()` on VimEnter (deferred)

---

## notify — Floating Notification Stack

```
notify/
├── init.lua     ← notify(msg, level, opts), dismiss(), setup()
├── config.lua   ← level, timeout, width, position
├── state.lua    ← State class (views[], next_id)
├── stack.lua    ← push/dismiss, layout management
├── record.lua   ← Record factory (id, message, level, timeout)
└── ui.lua       ← create/render/close/fade views
```

API: `notify(message, level, opts)` — also `vim.notify` override

---

## toast — Toast Notification Stack

```
toast/
├── init.lua     ← toast(msg, level, opts), dismiss(), setup()
├── config.lua   ← level, timeout, width, position
├── state.lua    ← State class (views[], next_id)
├── stack.lua    ← push/dismiss, layout management
├── record.lua   ← Record factory
└── ui.lua       ← create/render/close views
```

API: `Toast(message, level, opts)`

---

## key — Keybinding Viewer & Manager

```
key/
├── init.lua       ← proxy to core, setup()
├── config.lua     ← readonly config, UI dimensions
├── core.lua       ← safe_set, managed keymaps registry
├── api.lua        ← show/hide/query operations
├── state.lua      ← active view, mode, filter
├── ui.lua         ← floating window + backdrop
├── highlights.lua ← BeastKey* groups
└── builtin.lua    ← default keymaps (scroll, pin, etc.)
```

API: `Key.safe_set(mode, lhs, rhs, opts)`, `Key.managed`

---

## confirm — vim.fn.confirm Drop-In

```
confirm/
├── init.lua       ← run(msg, choices, default, type), setup()
├── config.lua     ← disabled flag
├── ui.lua         ← modal loop, button rendering
└── highlights.lua ← BeastConfirm* groups
```

API: `confirm(msg, "&Yes\n&No", 1)` → integer (0=dismissed, 1..N=choice)

---

## packer — Plugin Loader

```
packer/
├── init.lua         ← setup(specs), normalize, load pipeline, packer.lazy()
├── config.lua       ← pack_dir, auto_install, ui options
├── state.lua        ← plugins registry, loaded status
├── import.lua       ← spec importer (handles { import = "..." })
├── operation.lua    ← git clone, pull, install operations
├── ui.lua           ← floating dashboard (loaded/not loaded/ops)
├── highlights.lua   ← BeastPacker* groups
├── profile.lua      ← per-plugin + per-phase timing
└── triggers/        ← lazy-load trigger handlers
    ├── event.lua, cmd.lua, keys.lua
    ├── module.lua, filetype.lua, path.lua
```

API: `packer.setup(opts)`, `packer.lazy(mod, opts)` — deferred lib loading
with event/keys triggers, highlight registration, and `defer` (vim.schedule).

---

## treesitter — Treesitter Setup & Parser Management

```
treesitter/
├── init.lua       ← setup(opts), enable() (highlight + fold)
├── config.lua     ← ensure_installed list
├── install.lua    ← async parser install via vim.system
├── parsers.lua    ← parser status queries
└── scope.lua      ← scope-based queries
```

API: `treesitter.setup(opts)`, `treesitter.enable()`
Loaded via: `packer.lazy()` on FileType (deferred)

---

## buf — Buffer Utilities

```
libs/buf.lua  ← M.delete(opts), M.new(filetype)
```

API: `Buffer.delete({ buf, force })` — smart delete with confirm prompt

---

## statusline — Native `%!` Statusline

```
statusline/
├── init.lua          ← setup(), render(), state owner, autocmd registration
├── config.lua        ← defaults (left/center/right, separator, priority, marker)
├── context.lua       ← build per-render ctx from g:statusline_winid
├── hlgroup.lua       ← deterministic BeastStl_<hash> groups, palette alias resolution
├── highlights.lua    ← ColorScheme refresh hook (clear_all + redrawstatus)
├── util.lua          ← fragment width, assemble, IGNORED_FILETYPES, file_bound
├── truncate.lua      ← cross-region priority drop until total fits width
└── components/
    ├── init.lua          ← barrel + types
    ├── mode.lua, git_branch.lua, git_commit.lua
    ├── diagnostics.lua, position.lua, filetype.lua
    ├── shiftwidth.lua, encoding.lua
```

API: `stl.setup({ left = {...}, right = {...} })` — components are tables.
`util.file_bound(compute)` — caches per real-file buffer, persists on transient UI buffers.
