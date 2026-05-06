<!-- Generated: 2026-05-02 | Files scanned: 100 | Token estimate: ~1100 -->

# Libraries

## explorer — File Explorer (split panel)

```
explorer/
├── init.lua       ← open/close/toggle, setup, replace_netrw
├── config.lua     ← style, width, side, icons, mappings
├── state.lua      ← tree, view, source_win, augroup
├── tree.lua       ← filesystem tree with flat cache
├── ui.lua         ← create split window, focus_path
├── render.lua     ← draw tree nodes to buffer
├── prompt.lua     ← inline input prompt (create/rename)
├── keymaps.lua    ← mount action keymaps
├── autocmds.lua   ← BufEnter/WinClosed handlers
├── highlights.lua ← BeastExplorer* groups
└── actions/       ← one file per action
    ├── open.lua, create.lua, delete.lua, rename.lua
    ├── set_root.lua, navigate_up.lua, show_hidden.lua
    ├── copy_to_clipboard.lua, cut_to_clipboard.lua
    └── paste_from_clipboard.lua
```

API: `explorer.open(dir)`, `explorer.close()`, `explorer.toggle(cwd)`

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
├── init.lua         ← setup(specs), normalize, load pipeline
├── config.lua       ← pack_dir, auto_install, ui options
├── state.lua        ← plugins registry, loaded status
├── import.lua       ← spec importer (handles { import = "..." })
├── operation.lua    ← git clone, pull, install operations
├── ui.lua           ← floating dashboard (loaded/not loaded/ops)
├── highlights.lua   ← BeastPacker* groups
├── profile.lua      ← per-plugin (packadd_ms/config_ms) + per-phase (pack_add/early_cs) timing
└── triggers/        ← lazy-load trigger handlers
    ├── event.lua, cmd.lua, keys.lua
    ├── module.lua, filetype.lua, path.lua
```

API: `packer.setup(opts)` — auto-installs + lazy-loads plugins. `opts.colorscheme = { name, plugin }` eagerly applies a colorscheme before `vim.pack.add`. Read `require("beast.libs.packer.profile").phases.{pack_add,early_cs}` for phase timings (`ms`, `calls`, `min`, `max`).

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
│                       (laststatus=3 → vim.o.columns width fix)
├── hlgroup.lua       ← deterministic `BeastStl_<hash>` group names from
│                       {fg,bg,bold,…} specs; palette alias resolution;
│                       ensure(spec) lazy-creates groups; clear_all() wipes cache
├── highlights.lua    ← ColorScheme refresh hook; runs hlgroup.clear_all() +
│                       redrawstatus (no static Beast<Lib>* groups defined)
├── util.lua          ← fragment width, assemble, IGNORED_FILETYPES (beast-*),
│                       is_file_buffer, file_bound provider wrapper
├── truncate.lua      ← cross-region priority drop until total fits width
└── components/
    ├── init.lua      ← barrel + ComponentSpec/Fragment/HighlightSpec types
    ├── mode.lua      ← global, ModeChanged, compound (NORMAL + colored bg)
    ├── git_branch.lua    ← buffer, libuv fs_event on .git/HEAD,
    │                       emits User BeastStatuslineGitChanged
    ├── git_commit.lua    ← file_bound, `git log -1 --format=%an (%cr)`
    ├── diagnostics.lua   ← buffer, DiagnosticChanged, compound (E/W/I/H)
    ├── position.lua      ← file_bound, named-files only ("Ln N, Col N")
    ├── filetype.lua      ← file_bound, capitalized first letter
    ├── shiftwidth.lua    ← file_bound, "Spaces: N"
    └── encoding.lua      ← file_bound, "UTF-8"
```

API: `stl.setup({ left = {...}, right = {...} })` — components are tables.

Component spec:
```lua
{
  provider  = function(ctx) return { { text = "x", hl = {fg="accent1"} } } end,
  condition = function(ctx) return ctx.is_active end,        -- optional
  update    = { "BufEnter", "User BeastStatuslineGitChanged" },  -- optional
  scope     = "buffer",     -- "global"|"buffer"|"window" (declarative)
  priority  = 50,           -- truncation priority
  separator = " ",          -- override default separator after this comp
}
```

`util.file_bound(compute)` — wraps a provider so it only computes on real
file buffers; remembers the last value; on transient `beast-*` UI buffers,
returns the last value so the right side of the bar doesn't collapse.
Compute returns: `string` = update / `false` = clear / `nil` = keep previous.

See `docs/dev-specs/statusline-library.md` for the full design doc.
