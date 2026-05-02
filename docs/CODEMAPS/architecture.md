<!-- Generated: 2026-05-02 | Files scanned: 100 | Token estimate: ~950 -->

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
│   ├── packer/           ← plugin loader with lazy triggers
│   └── statusline/       ← native %! statusline (replaces heirline statusline)
└── plugins/
    ├── init.lua           ← plugin spec imports
    ├── colorscheme.lua    ← colorscheme plugin spec
    └── bars/              ← heirline tabline + winbar (statusline now native)
```

## Globals Registered at Setup

| Global | Module | Purpose |
|--------|--------|---------|
| `Util` | beast.util | Window opts, scratch buf, colors |
| `Key` | beast.libs.key | Keymap registration + viewer |
| `Buffer` | beast.libs.buf | Buffer delete helper |
| `Icon` | beast.icon | Icon lookup |
| `Toast` | beast.libs.toast | Toast notifications |
| `Palette` | beast.plugins.bars.palette | Theme palette (resolves accent1, …) |

## Data Flow

```
User action
  → Key.safe_set (keymap)
    → Library public API (toggle/open/notify)
      → State mutation (init.lua only)
        → UI render (ui.lua / render path)
          → Neovim API (buf/win/extmark)

Neovim redraw (statusline)
  → %! evaluates → statusline.render(ctx)
    → context.build (g:statusline_winid)
    → providers per region → fragments
    → truncate.fit → util.assemble → string
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

Palette.get / Palette.refresh
  └── used by: statusline/hlgroup.lua, all libs' highlights.lua
```

## ColorScheme Refresh Pipeline

```
:colorscheme X
  → ColorScheme autocmd
    → Palette.refresh()              -- fresh palette snapshot
      → M.reload_highlights()        -- registry in beast/init.lua
        → for each "*.highlights" module:
            package.loaded[m] = nil
            require(m)                -- module body runs with new palette
```

`M.highlight_modules` includes: confirm, explorer, key, packer, notify, statusline.

What "module body runs" means per lib:

- **explorer / key / confirm / packer / notify** — `highlights.lua` calls
  `nvim_set_hl` directly to (re)define each `Beast<Lib>*` group from `Palette`.
- **statusline** — `highlights.lua` is two-phase: `hlgroup.clear_all()` wipes
  the dynamic `BeastStl_<hash>` cache, then `redrawstatus` causes
  `hlgroup.ensure(spec)` to lazily re-create groups during the next render
  with the fresh palette. No static `BeastStatusline*` groups exist —
  components reference colours via inline specs (`{ fg = "accent3" }`).

## Patterns

- **State ownership**: only `init.lua` per library holds mutable state
- **Config**: readonly metatable with `setup(opts)` merge
- **Highlights**: `Beast<Lib>*` namespaced groups in `highlights.lua`
- **Netrw replacement**: explorer auto-opens on directory BufEnter
- **vim.notify override**: notify.setup() replaces `vim.notify`
- **Statusline = `%!`**: lualine-style cheap render (no engine cache);
  components own internal caching (`file_bound`, libuv watchers)
- **Transient UI buffers**: `IGNORED_FILETYPES` table (beast-* only) in
  statusline/util.lua — file-bound components stay visible on these
