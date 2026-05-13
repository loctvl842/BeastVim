<!-- Generated: 2026-05-13 | Files scanned: 114 | Token estimate: ~980 -->

# Architecture

## Entry Point

```
init.lua → require("beast").setup()
```

## Module Tree

```
lua/beast/
├── init.lua              ← top-level setup, wires all libs + globals,
│                           registers M.highlight_modules for ColorScheme refresh
├── option.lua            ← vim options
├── icon.lua              ← icon definitions
├── palette.lua           ← theme palette (resolves accent1, …)
├── util/
│   ├── init.lua          ← Util.wo, Util.create_scratch_buf, Util.hrtime
│   ├── colors.lua        ← Util.colors.set_hl
│   └── root.lua          ← project root detection
├── libs/
│   ├── view.lua          ← Beast.View base class (buf+win pair)
│   ├── animate.lua       ← shared animation engine (pure math)
│   ├── buf.lua           ← Beast.Buf (buffer delete, scratch buf)
│   ├── confirm/          ← vim.fn.confirm drop-in UI
│   ├── explorer/         ← file explorer (split panel + sticky headers)
│   ├── key/              ← keybinding viewer/manager
│   ├── notify/           ← floating notification stack
│   ├── packer/           ← plugin loader with lazy triggers + packer.lazy()
│   ├── statusline/       ← native %! statusline (replaces heirline statusline)
│   ├── tabline/          ← native %! tabline (replaces heirline tabline)
│   └── toast/            ← toast notification stack
└── plugins/
    ├── init.lua           ← plugin spec imports
    └── colorscheme.lua    ← colorscheme plugin spec
```

## Globals Registered at Setup

| Global | Module | Purpose |
|--------|--------|---------|
| `Util` | beast.util | Window opts, scratch buf, colors |
| `Key` | beast.libs.key | Keymap registration + viewer |
| `Buffer` | beast.libs.buf | Buffer delete helper |
| `Icon` | beast.icon | Icon lookup |
| `Toast` | beast.libs.toast | Toast notifications |
| `Palette` | beast.palette | Theme palette (resolves accent1, …) |

## Setup Flow

```
beast.setup(opts)
  1. require("beast.option")
  2. Register globals: Util, Palette, Key, Buffer, Icon
  3. Register ColorScheme autocmd → Palette.refresh() + reload_highlights()
  4. Key.setup() + default keymaps
  5. notify.setup() + toast.setup() → Toast global
  6. confirm.setup()
  7. packer.setup() → git-clone + lazy-load plugins
  8. statusline.setup() → native %! with component specs
  9. packer.lazy("beast.libs.tabline") → deferred VimEnter
 10. packer.lazy("beast.libs.explorer") → deferred VimEnter + <leader>e
 11. Palette.refresh() + reload_highlights()
```

## Lazy Lib Loading (`packer.lazy`)

Explorer and tabline load via `packer.lazy(mod, opts)`, not `require()` in setup.
Triggers: `event`, `keys`. Options: `defer` (vim.schedule), `highlights` (auto-registers
in `M.highlight_modules`), `setup(lib)` callback.

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

Palette.get / Palette.refresh
  └── used by: statusline/hlgroup.lua, tabline/icons.lua, all libs' highlights.lua
```

## ColorScheme Refresh Pipeline

```
:colorscheme X
  → ColorScheme autocmd
    → Palette.refresh()
      → M.reload_highlights()
        → for each module in M.highlight_modules:
            skip if parent lib not loaded
            package.loaded[m] = nil
            require(m)
```

`M.highlight_modules` starts with: confirm, key, packer, notify, statusline.
Lazy libs (tabline, explorer) register dynamically via `packer.lazy(opts.highlights)`.

## Patterns

- **State ownership**: only `init.lua` per library holds mutable state
- **Config**: readonly metatable with `setup(opts)` merge
- **Highlights**: `Beast<Lib>*` namespaced groups in `highlights.lua`
- **Netrw replacement**: explorer auto-opens on directory BufEnter
- **vim.notify override**: notify.setup() replaces `vim.notify`
- **Statusline = `%!`**: component-based, file_bound caching, priority truncation
- **Tabline = `%!`**: event-driven cache, 3-state highlights, anchor-based truncation
- **Transient UI buffers**: `IGNORED_FILETYPES` table (beast-* only)
