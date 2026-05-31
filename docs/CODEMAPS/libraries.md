<!-- Generated: 2026-05-31 | Files scanned: 173 | Token estimate: ~2680 -->

# Libraries

## explorer — File Explorer (split panel)

```
explorer/
├── init.lua       ← open/close/toggle, setup, replace_netrw
├── config.lua     ← style, width, side, icons, git, sticky, mappings
├── state.lua      ← tree, view, sticky, source_win, augroup, watchers, git_root/job/timer
├── tree.lua       ← filesystem tree with flat cache, unwatch_subtree()
├── git.lua        ← async git status engine (vim.system, porcelain v1, propagation)
├── ui.lua         ← create split window, focus_path, render, flush
├── render.lua     ← draw tree nodes to buffer (git name colors + virt_text badges)
├── watch.lua      ← fs_event watchers per expanded dir, 100ms debounce
├── sticky.lua     ← floating ancestor headers (cursor-anchored, git colors)
├── prompt.lua     ← inline input prompt (create/rename)
├── keymaps.lua    ← mount action keymaps
├── autocmds.lua   ← BufEnter/WinClosed/WinScrolled/CursorMoved/BufWritePost/FocusGained + git refresh
├── highlights.lua ← BeastExplorer* groups (incl. Git{Added,Modified,Deleted,Untracked,Conflict,Renamed,Ignored})
└── actions/       ← one file per action
    ├── open.lua, split_open.lua, system_open.lua
    ├── create.lua, delete.lua, rename.lua
    ├── trash.lua, _trash_cmd.lua (OS-specific trash command resolver)
    ├── set_root.lua, navigate_up.lua, show_hidden.lua
    ├── copy_to_clipboard.lua, cut_to_clipboard.lua
    └── paste_from_clipboard.lua
```

API: `explorer.open(dir)`, `explorer.close()`, `explorer.toggle(cwd)`
Config: `git = { enable = true, badges = true }` (backward-compat: `git = true/false`)
Loaded via: `packer.lazy()` on VimEnter (deferred) + `<leader>e` keymap

### Git Status Integration (`git.lua`)

Async `git status --porcelain=v1 --ignored` via `vim.system`. Parses output,
stamps `node.git_status` on tree nodes, propagates to parent dirs (highest-priority
child wins). Debounced refresh on BufWritePost + FocusGained. Badges: M, A, D, U, R, C, !.

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
├── score.lua      ← scoring algorithm (bonus tables, gap penalties)
├── topk.lua       ← top-K min-heap for fast ranking
├── queue.lua      ← priority queue helper
├── format.lua     ← per-source display formatters (filename, live_grep, help_tags, …)
├── match_hl.lua   ← fuzzy match highlight extmarks (list + preview)
├── action.lua     ← open, open_help, open_split, open_vsplit, copy_path
├── keymaps.lua    ← input/list/preview pane keymaps + printable-char redirect
├── autocmds.lua   ← picker lifetime autocmds (BufEnter, WinClosed)
├── highlights.lua ← BeastFinder* groups
├── layout.lua     ← window layout calculations
├── fzf.lua        ← external fzf integration
├── pipeline/
│   ├── match.lua  ← streaming match pipeline
│   └── stream.lua ← async stream processing
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

---

## breadcrumb — Winbar Breadcrumb

```
breadcrumb/
├── init.lua       ← render(), setup(), _invalidate()
├── config.lua     ← separator, icons, depth limit
├── context.lua    ← treesitter-based symbol context extraction
├── filepath.lua   ← filepath segment builder
└── highlights.lua ← BeastBreadcrumb* groups
```

API: `breadcrumb.render()` — returns winbar string (via `%!v:lua`)
Loaded via: `packer.lazy()` on VimEnter (deferred, winbar)

---

## indent — Indent Guides & Scope Highlighting

```
indent/
├── init.lua       ← setup(opts), decoration provider (on_win)
├── config.lua     ← exclude_filetypes, colors, scope opts
├── guide.lua      ← indent guide rendering (extmarks)
├── highlights.lua ← BeastIndent* groups
└── scope/
    ├── init.lua       ← scope detection dispatch (treesitter or indent)
    ├── indent.lua     ← indent-based scope detection
    └── treesitter.lua ← treesitter-based scope detection
```

API: `indent.setup(opts)` — registers decoration provider
Loaded via: `packer.lazy()` on VimEnter (deferred)

---

## scroll — Smooth Viewport Scrolling

```
scroll/
├── init.lua    ← setup/enable/disable/toggle, autocmds, M.check (hot path), M._tick (timer)
├── config.lua  ← animate + animate_repeat profiles, filter
└── state.lua   ← Beast.Scroll.State class (per-window: view/current/target, timer, _wo)
```

API: `scroll.setup(opts)`, `scroll.enable()`, `scroll.disable()`, `scroll.toggle()`,
`scroll.is_enabled()`. Per-buffer opt-out: `vim.b[buf].beast_scroll_disabled = true`.
Per-session opt-out: `vim.g.beast_scroll_disabled = true`.

### Algorithm

`WinScrolled` → per-winid `State.get` → snap view back to `current` via `winrestview`
→ tween toward `target` with `vim.uv.new_timer()` issuing micro `<C-e>` / `<C-y>`
batches. Two profiles: `animate` (200 ms total, 10 ms step) and `animate_repeat`
(50 ms total, 5 ms step, used when a new scroll starts within 100 ms of the previous
— keeps held `j`/`k` smooth without backlog). Mouse wheel detected via `vim.on_key`
and skipped (terminal handles it). Folds accounted for via `nvim_win_text_height`.

Ports the design of `snacks.nvim`'s `snacks.scroll` natively — no plugin dependency.
