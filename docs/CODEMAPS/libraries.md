<!-- Generated: 2026-05-01 | Files scanned: 82 | Token estimate: ~950 -->

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
├── profile.lua      ← load timing/reason tracking
└── triggers/        ← lazy-load trigger handlers
    ├── event.lua, cmd.lua, keys.lua
    ├── module.lua, filetype.lua, path.lua
```

API: `packer.setup(specs)` — auto-installs + lazy-loads plugins

---

## buf — Buffer Utilities

```
libs/buf.lua  ← M.delete(opts), M.new(filetype)
```

API: `Buffer.delete({ buf, force })` — smart delete with confirm prompt
