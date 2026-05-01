<!-- Generated: 2026-05-01 | Files scanned: 82 | Token estimate: ~900 -->

# Architecture

## Entry Point

```
init.lua → require("beast").setup()
```

## Module Tree

```
lua/beast/
├── init.lua              ← top-level setup, wires all libs + globals
├── option.lua            ← vim options
├── icon.lua              ← icon definitions
├── util/
│   ├── init.lua          ← Util.wo, Util.create_scratch_buf, Util.hrtime
│   ├── colors.lua        ← Util.colors.set_hl
│   └── root.lua          ← project root detection
├── libs/
│   ├── view.lua          ← Beast.View base class (buf+win pair)
│   ├── animate.lua       ← shared animation engine (pure math)
│   ├── buf.lua           ← Beast.Buf (buffer delete, scratch buf)
│   ├── explorer/         ← file explorer (split panel)
│   ├── notify/           ← floating notification stack
│   ├── toast/            ← toast notification stack
│   ├── key/              ← keybinding viewer/manager
│   ├── confirm/          ← vim.fn.confirm drop-in UI
│   └── packer/           ← plugin loader with lazy triggers
└── plugins/
    ├── init.lua           ← plugin spec imports
    ├── colorscheme.lua    ← colorscheme plugin spec
    └── bars/              ← statusline, tabline, winbar
```

## Globals Registered at Setup

| Global | Module | Purpose |
|--------|--------|---------|
| `Util` | beast.util | Window opts, scratch buf, colors |
| `Key` | beast.libs.key | Keymap registration + viewer |
| `Buffer` | beast.libs.buf | Buffer delete helper |
| `Icon` | beast.icon | Icon lookup |
| `Toast` | beast.libs.toast | Toast notifications |

## Data Flow

```
User action
  → Key.safe_set (keymap)
    → Library public API (toggle/open/notify)
      → State mutation (init.lua only)
        → UI render (ui.lua)
          → Neovim API (buf/win/extmark)
```

## Shared Modules

```
Beast.View (view.lua)
  └── extended by: notify, toast, explorer, key

animate.lua
  └── used by: notify/ui.lua, toast/ui.lua

Util.create_scratch_buf
  └── used by: confirm, explorer, key, notify, toast

Util.colors.set_hl
  └── used by: all libs with highlights.lua
```

## Patterns

- **State ownership**: only `init.lua` per library holds mutable state
- **Config**: readonly metatable with `setup(opts)` merge
- **Highlights**: `Beast<Lib>*` namespaced groups in `highlights.lua`
- **Netrw replacement**: explorer auto-opens on directory BufEnter
- **vim.notify override**: notify.setup() replaces `vim.notify`
