<!-- Generated: 2026-06-10 | Files scanned: 246 | Token estimate: ~2950 -->

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
├── init.lua     ← toast(msg, level, opts), update(record), dismiss/dismiss_id, setup()
├── config.lua   ← level, timeout, width, position, progress block
├── state.lua    ← State class (views[], next_id)
├── stack.lua    ← push/update/dismiss, layout management
├── record.lua   ← Record factory
├── progress.lua ← LspProgress → in-place toast adapter (bar + spinner)
└── ui.lua       ← create/render/close views
```

API: `Toast(message, level, opts)`

---

## key — Keybinding Cheatsheet, Manager & Press-and-Wait Hint

```
key/
├── init.lua             ← proxy to core, setup()
├── config.lua           ← readonly config, cheatsheet + hint dimensions
├── core.lua             ← safe_set, managed keymaps registry (+ BeastKeysChanged emit)
├── api.lua              ← show/hide/query operations
├── highlights.lua       ← BeastKey* groups (incl. BeastKeyHint*)
├── builtin.lua          ← default keymaps (scroll, pin, etc.)
├── cheatsheet/          ← full-screen keymap browser
│   ├── init.lua         ← public M.open/M.refresh + controller + actions
│   ├── state.lua        ← active main/action views, lines, augroup
│   ├── main.lua         ← MainView (backdrop + main float) create/layout/render/close
│   └── action.lua       ← ActionView (top-right action overlay)
└── hint/                ← Helix-style press-and-wait hint (replaces which-key)
    ├── init.lua         ← M.setup/M.start, register_trigger, suspend_and_feed
    ├── index.lua        ← split_keys, prefix tree, walk, reachable, visible_children
    ├── window.lua       ← HintView, measure, open_or_update, close
    └── loop.lua         ← walk_state, render, modal getchar loop
```

API: `Key.safe_set(mode, lhs, rhs, opts)`, `Key.managed`. Hint is enabled by
default via `config.hint.enabled = true`; opt out with
`Key.setup({ hint = { enabled = false } })`.

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

## autopairs — Insert-Mode Autopairs (native, no plugin)

```
autopairs/
├── init.lua       ← setup/enable/disable/toggle/is_installed; state owner (registry, installed)
├── config.lua     ← frozen-config metatable; default pair table () [] {} "" '' ``
├── pairs.lua      ← pure: neigh_matches, is_symmetric, iter_active
├── actions.lua    ← open/close/closeopen/bs/cr — return keystroke strings (pre-decoded termcodes)
├── skip.lua       ← skip_next / skip_ts / skip_unbalanced / markdown vetoes
├── keymap.lua     ← install/uninstall <expr> mappings via Key.safe_set; per-mode + per-keystroke ctx
└── health.lua     ← :checkhealth provider (API contract, mapping presence, config dump)
```

API: `autopairs.setup(opts)`, `autopairs.enable()`, `autopairs.disable()`,
`autopairs.toggle()` (flips `vim.g.beast_autopairs_disable`), `autopairs.is_installed()`.
Per-buffer opt-out: `vim.b.beast_autopairs_disable = true`.
Loaded via: `packer.lazy()` on `InsertEnter` + `<leader>up` toggle.

Tests: `tests/test-autopairs-engine.lua` (53), `tests/test-autopairs-skip.lua` (28).

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
with `event` / `keys` / `filetype` / `module` triggers, highlight registration,
and `defer` (vim.schedule). The `module` trigger registers a `package.searchers`
hook so a direct `require("beast.libs.X")` from a keymap body triggers
`setup(lib)` before returning — closes the half-init hole when keys aren't
the only entry point.

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

## lsp — LSP Infra over `vim.lsp.config` / `vim.lsp.enable` (no nvim-lspconfig)

```
lsp/
├── init.lua          ← setup, register(name, cfg), unregister(name), capabilities, add_capabilities, on_attach, :BeastLspInfo
├── config.lua        ← diagnostics defaults (Icon.diagnostics.*), inlay_hints/codelens/fold toggles, read-only metatable
├── capabilities.lua  ← base() + contributors + get(); first_client_seen flag for late-add warning
├── diagnostics.lua   ← vim.diagnostic.config(cfg.diagnostics)
├── attach.lua        ← single LspAttach autocmd on BeastVim-lsp augroup; servers map + subscribers list; apply_fold/inlay_hints/codelens
├── keys.lua          ← Key.safe_set per buffer; cond gating via client:supports_method
└── health.lua        ← :checkhealth beast.libs.lsp (version, init, servers + cmd[1] PATH, contributors, attached clients, toggle status)
```

API: `Lsp.setup(opts)`, `Lsp.register(name, cfg)`, `Lsp.unregister(name)`, `Lsp.capabilities()`, `Lsp.add_capabilities(contrib)`, `Lsp.on_attach(fn)`
`cfg` is a `vim.lsp.Config` augmented with `keys` (with optional `cond` LSP-method gating), `on_attach`, and `enabled` (preflight `fun(): boolean`; false skips `vim.lsp.config`/`vim.lsp.enable` but still records dispatcher extras).
`cfg.capabilities` defaults to a **snapshot taken at `register()` time** (Neovim's `vim.lsp` validator strictly requires a `table`). To pick up contributors registered later (e.g. blink.cmp on InsertEnter), `register()` also installs a `before_init` hook that re-resolves `M.capabilities()` and assigns it to the outgoing `initialize` request — so any server that hasn't started yet still receives late additions. Caller-supplied `before_init` is chained, not replaced. Contributors added after the first `LspAttach` emit a one-shot WARN via `vim.notify` (already-attached clients won't see the new contribution).
Loaded **eagerly** from `beast/init.lua` between `confirm.setup()` and `packer.setup` — `vim.lsp.enable` must run before the first `FileType` autocmd. Global: `_G.Lsp`. Dispatch order: per-server keys → per-server on_attach → apply_fold/inlay_hints/codelens → global subscribers. Per-server configs live in external `BeastVim/<Lang>` repos (see ADR-030).
Bench: `scripts/bench-lsp.lua` measures capabilities resolution (50-contributor stress, 1 ms threshold). Tests: `tests/test-lsp.lua` (19 assertions covering register/unregister/capabilities snapshot+`before_init`/toggles/warning).

---

## view — Buffer + Window Wrapper Toolkit

```
view/
├── init.lua    ← Beast.View instance class + Beast.View.Module
│                 View(buf, win), :is_valid, :close, View:extend(init)
├── buf.lua     ← View.buf.new(filetype), View.buf.delete({ buf, force })
└── win.lua     ← View.win.wo, View.win.find_normal()
```

API: `View(buf, win)`, `View:extend(init)` for subclasses (every UI lib's
`*View`), `View.buf.new(filetype)`, `View.buf.delete({ buf, force })` —
smart delete with confirm prompt. `View.win.wo(win, k, v)` cross-version-
safe local opt setter. `View.win.find_normal()` finds the most recent
non-beast-UI window (used by explorer + finder to target file opens).

NOTE: legacy `Buffer` global removed — call `View.buf.delete(...)` directly.

---

## starter — Native Intro Screen Extensions

```
starter/
├── init.lua    ← setup(cfg), VimEnter autocmd, key-hint row renderer
└── config.lua  ← keys: { { verb, key, desc }, ... }
```

API: `starter.setup({ keys = { { verb = "press", key = "<leader>p", desc = "to manage plugins" }, ... } })`
Loaded **eagerly** from `beast/init.lua` (must register VimEnter autocmd before VimEnter fires).
Opt-in: only renders the BeastVim key rows when the user explicitly provides
`cfg.starter.keys` — otherwise falls through to the bare native intro.

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

## statuscolumn — Native `%!` Statuscolumn

```
statuscolumn/
├── init.lua       ← setup(), render() (hot path, pcall-wrapped), producer dispatch, autocmds
├── config.lua     ← segments (slot lists), git, fold, ft_ignore, bt_ignore
├── ffi.lua        ← cdef for display_tick, fold_info, find_window_by_handle (pcall-guarded)
├── cache.lua      ← per-(win,tick,buf) sign-map + per-line interned strings
├── number.lua     ← format(win,lnum,relnum,virtnum) — hybrid &nu/&rnu support
├── signs.lua      ← collect(buf) once per (win,tick); classify by namespace then name pattern
├── fold.lua       ← icon(win,lnum,virtnum,show_open) via FFI fold_info; fillchars glyphs
├── highlights.lua ← BeastStc* groups (Number/Diag*/Git*/Fold) link to existing defaults
└── health.lua     ← :checkhealth — modules, FFI, wiring, segments, highlights, inline bench
```

API: `statuscolumn.setup(opts)`, `statuscolumn.render()` (via `%!v:lua`)
Slot syntax: `segments = { {"diagnostic"}, {"number"}, {"git"}, {"fold"} }`
  — each entry is a slot; each slot is a producer priority list.
  Producers: `number | diagnostic | git | fold` (fixed enum, ADR-019).
Per-buffer opt-out: `vim.b[buf].beast_statuscolumn_disabled = true`.
Loaded via: `packer.lazy()` on VimEnter (deferred)

### Performance
- Cache key: `(win, display_tick, buf)` → sign map; `(lnum, virtnum, relnum)` → string.
- `display_tick` from FFI bumps once per redraw; one extmark walk per tick.
- Bench `scripts/bench-statuscolumn.lua`: hit ~1.7 µs, miss ~1.8 µs, 200-line redraw ~330 µs.
- Zero plugin dependencies (ADR-020): gitsigns/mini.diff/vim.diagnostic detected by extmark namespace + name patterns.

---

## git — Native Git Hunk Signs / Navigation / Preview / Stage / Reset

```
git/
├── init.lua       ← state, attach/detach, debounced recompute, single-flight, autocmds, public surface
├── config.lua     ← debounce_ms, keymaps, icons, ft_ignore, bt_ignore, blame{ enabled, delay_ms, ... } (frozen, ADR-003)
├── repo.lua       ← resolve(buf) + get_base/get_head/get_path_data/intent_to_add/get_username via vim.system
├── diff.lua       ← compute_hunks(base, current) via vim.text.diff (fallback vim.diff), histogram + linematch
├── hunks.lua      ← expand_signs / expand_staged_signs / find_at_buffer_line / index_to_buffer_delta
├── signs.lua      ← namespaces { unstaged, staged }; place_unstaged / place_staged (priority 6 vs 5)
├── patch.lua      ← pure: format(ref, target, hunks, path_data) → unified-zero patch lines (mini.diff pattern)
├── apply.lua      ← async: vim.system `git apply --cached --unidiff-zero [--reverse] -` on stdin
├── actions.lua    ← stage_hunk (toggle), unstage_hunk, reset_hunk; with_path_data covers untracked via intent-to-add
├── nav.lua        ← nav_hunk("next"|"prev", { wrap, foldopen, target }) — `''` mark + `zv`; target=unstaged|staged|all
├── preview.lua    ← Beast.View subclass; <leader>gp opens diff float, auto-close on CursorMoved
├── blame.lua      ← async `git blame --incremental` parser; run(ctx, { lnum?, contents?, ignore_whitespace?, revision?, untracked? }, cb)
├── current_line_blame.lua ← cursor-driven virt_text; namespace beast_git_blame; debounced via Util.debounce; cursor-race guard
├── blame_view.lua ← Beast.View subclass; <leader>gB opens left side window with full-file blame; scrollbind-synced; <CR>=show commit, r=reblame parent, R=reset
├── highlights.lua ← BeastGit{Add,Change,Delete,TopDelete,Changedelete} + BeastGitStaged* + BeastGitCurrentLineBlame + BeastGitBlameView{Sha,Author,Date}
└── health.lua     ← :checkhealth — git bin, diff backend, namespaces, attached count, staged-tier hl groups, blame config + user.name
```

API: `git.setup(opts)`, `git.attach(buf)`, `git.get_hunks(buf)`, `git.get_staged_hunks(buf)`,
`git.nav_hunk(dir, opts)`, `git.preview_hunk()`, `git.stage_hunk(buf, lnum)`,
`git.unstage_hunk(buf, lnum)`, `git.reset_hunk(buf, lnum)`, `git.repeat_action()`,
`git.refresh(buf, { base?, head? })`, `git.blame_line(opts?)`, `git.blame(opts?)`, `git.toggle_current_line_blame()`.
Default buffer-local keymaps (when `config.keymaps=true`): `]c` / `[c` next/prev, `<leader>gp` preview, `<leader>gb` blame line, `<leader>gB` blame file, `<leader>gtb` toggle blame.
Statuscolumn integration: extmarks classified by namespace pattern `^beast_git_signs_(unstaged|staged)$` — staged tier rendered via `BeastStcGitStaged{Add,Change,Delete}` desaturated palette blends (ADR-020).
Loaded via: `packer.lazy()` on `BufReadPost` (deferred).

### Two-tier diff model
- `unstaged_hunks = diff(base=index, buffer)` — live edits, repaint per keystroke
- `staged_hunks   = diff(head, base=index)` — queued for next commit, repaint on stage/commit/FocusGained
- Staged signs translated INDEX→BUFFER via `index_to_buffer_delta` (end-exclusive arithmetic handles abutting hunks)
- Render priority: unstaged=6 > staged=5; live edits visually override staged regions

### Blame
- `current_line_blame.lua` paints virt_text in namespace `beast_git_blame` (extmark id=1, replaced on debounced `CursorMoved`/`CursorMovedI`/`BufEnter`/`WinResized`/`FocusGained`). Cleared on `InsertEnter`/`BufLeave`/`OptionSet{fileformat,bomb,eol}`.
- Cursor-race guard: captured `start_lnum` is re-checked after both the blame and `get_username` async hops; mismatch → recurse `update(buf)` for the new line.
- `blame.lua` is the shared engine; `M.blame_line()` (one-shot info notify) and `M.blame()` / `blame_view.lua` (full-file side window) both call only `blame.run(ctx, opts, cb)`.
- Full-file blame view (`blame_view.lua`): Beast.View subclass, singleton, opens a left vertical split with `<sha> <author> <relative-date>` per row; scrollbind-synced (prior source scrollbind captured + restored on close). Buffer-local keymaps: `<CR>` opens commit diff float (`git show --stat --patch <sha>`, filetype `git`), `r` reblames `<sha>^`, `R` resets to HEAD, `q`/`<Esc>` close. Per-instance augroup `BeastGitBlameView_<bufnr>` closes the view on either window's WinClosed or source-buf BufWipeout/BufUnload.
- Untracked buffers are skipped in cursor blame (would just paint NC on every line); explicit `blame_line` reports the unresolved state.
- Bench `scripts/bench-git-blame.lua`: single-line ~40ms, full-file ~60ms on a 624-line fixture (dominated by `vim.system` → git process startup; threshold 80ms).

### Performance
- 200ms debounce on `nvim_buf_attach.on_lines` (more precise than TextChanged*); single-flight per buffer (running/dirty bitset).
- Bench `scripts/bench-git-wezterm.sh`: 50ms debounce median 52.59ms, 1ms debounce median 2.82ms (5k-line fixture, real wezterm pane).
- Pure-Lua diff via `vim.text.diff` — no subprocess per recompute; `git show :file` / `git show HEAD:file` only on attach + stage + FocusGained.
- ADRs: 022 (native lib vs gitsigns.nvim), 023 (vim.text.diff backend), 024 (distinct namespace for coexistence).

---



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

---

## window — Auto-Width + Maximize/Restore Splits

```
window/
├── init.lua       ← setup(opts), maximize/maximize_vertically/maximize_horizontally/equalize,
│                    enable/disable/toggle, user commands, WinEnter maximize-guard
├── config.lua     ← readonly singleton (autowidth, animation, ignore.{buftype,filetype})
├── state.lua      ← per-tab maximized snapshot (keyed by tabpage), augroup handles,
│                    cursor_virtcol cache, animation handle slot
├── win.lua        ← bare-winid helpers: get/set width/height, is_floating, is_ignored,
│                    get_wanted_width (textwidth + cfg.autowidth.winwidth, ft-aware,
│                    supports fractional w: 0<w<1 = %columns, 1<w<2 = %textwidth)
├── frame.lua      ← Frame layout tree from vim.fn.winlayout(): autowidth, maximize_window,
│                    equalize_windows; fixed-axis caching; longest-row/column queries.
│                    Plain-Lua metatable class (no middleclass)
├── layout.lua     ← orchestrator returning WinResizeData[]:
│                    autowidth(curwin), maximize_win(win, do_w, do_h), equalize_wins(do_w, do_h)
├── resize.lua     ← apply(data) via nvim_win_set_width/height (pcall);
│                    merge(width_data, height_data) by winid
├── animate.lua    ← split-resize tween built on Beast.Animate.tween;
│                    captures (w0, h0, dw, dh); snap-to-final on completion;
│                    single-flight (cancel + restart on new run())
├── autocmds.lua   ← BufWinEnter/WinEnter/WinNew/VimResized/WinClosed/TabLeave
│                    driving layout.autowidth; single-flight via state.resizing_request;
│                    vim.defer_fn(setup_layout, 10) on WinEnter so BufWinEnter wins
│                    the race for new buffers
└── health.lua     ← :checkhealth — modules, config, augroups, animation status, current layout
```

API: `window.setup(opts)`, `window.maximize()`, `window.maximize_vertically()`,
`window.maximize_horizontally()`, `window.equalize()`, `window.enable/disable/toggle()`.
User commands: `BeastWindowMaximize{,Vertically,Horizontally}`, `BeastWindowEqualize`,
`BeastWindowEnableAutowidth/DisableAutowidth/ToggleAutowidth`.
Per-buffer opt-out: `vim.b[buf].beast_window_disabled = true`.
Per-session opt-out: `vim.g.beast_window_disabled = true`.
Loaded via: `packer.lazy()` on `WinNew` + `<leader>z` / `<leader>z=` keys (deferred).

### How autowidth picks a width

1. Build a `Frame` tree from `vim.fn.winlayout()`.
2. Find the leaf for the current window.
3. Ask it for `wanted_width = textwidth + cfg.autowidth.winwidth` (filetype-aware).
4. If the tree can fit it, grow that leaf and shrink non-fixed siblings toward
   `winminwidth` (proportional by `get_longest_row` weight).
5. If not, recursively `maximize_window` the leaf in its parent row.
6. `THRESHOLD = 1` "breathing" suppression keeps ±1-cell jitter at bay.

Ports the layout core from `anuvyklack/windows.nvim`, dropping `middleclass` and
`animation.nvim` deps. Animation reuses the shared `beast.libs.animate.tween` primitive.
