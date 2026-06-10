<!-- Generated: 2026-06-08 | Files scanned: 180 | Token estimate: ~1060 -->

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
├── profile.lua           ← startup profiling
├── palette/
│   ├── init.lua          ← theme palette (resolves accent1, …), is_builtin_colorscheme()
│   └── highlights.lua    ← BeastPalette* base groups
├── util/
│   ├── init.lua          ← Util.wo, Util.create_scratch_buf, Util.hrtime
│   ├── colors.lua        ← Util.colors.set_hl
│   └── root.lua          ← project root detection
├── libs/
│   ├── view.lua          ← Beast.View base class (buf+win pair)
│   ├── animate.lua       ← shared animation engine (pure math)
│   ├── buf.lua           ← Beast.View.Buf (buffer delete, scratch buf)
│   ├── confirm/          ← vim.fn.confirm drop-in UI
│   ├── explorer/         ← file explorer (split panel + sticky headers + git status)
│   ├── finder/           ← fuzzy finder (files, buffers, grep, help, colorschemes)
│   ├── indent/           ← indent guides + scope highlighting (decoration provider)
│   ├── breadcrumb/       ← winbar breadcrumb (filepath + treesitter context)
│   ├── key/              ← keybinding viewer/manager
│   ├── notify/           ← floating notification stack
│   ├── packer/           ← plugin loader with lazy triggers + packer.lazy()
│   ├── statusline/       ← native %! statusline (+ per-lib health.lua for :checkhealth)
│   ├── tabline/          ← native %! tabline
│   ├── toast/            ← toast notification stack
│   ├── lsp/              ← LSP infra: register(name, cfg), capabilities, LspAttach dispatch
│   └── treesitter/       ← treesitter setup, parser install, scope queries
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
| `Theme` | beast.theme | Theme palette (resolves accent1, …) |
| `Lsp` | beast.libs.lsp | LSP infra: register, capabilities, on_attach |

## Setup Flow

```
beast.setup(opts)
  1. require("beast.option")
  2. Register globals: Util, Theme, Key, Buffer, Icon
  3. Register ColorScheme autocmd → Theme.refresh() + reload_highlights()
  4. Key.setup() + default keymaps
  5. notify.setup() + toast.setup() → Toast global
  6. confirm.setup()
  7. Lsp.setup(cfg.lsp or {}) → eager (vim.lsp.enable must run before FileType)
  8. packer.setup() → git-clone + lazy-load plugins
  9. statusline.setup() → native %! with component specs
 10. packer.lazy("beast.libs.breadcrumb") → deferred VimEnter (winbar)
 11. packer.lazy("beast.libs.tabline") → deferred VimEnter
 12. packer.lazy("beast.libs.explorer") → deferred VimEnter + <leader>e
 13. packer.lazy("beast.libs.indent") → deferred VimEnter (decoration provider)
 14. packer.lazy("beast.libs.treesitter") → deferred FileType
 15. packer.lazy("beast.libs.finder") → deferred keys (<leader>f/b/g/c/h)
 16. Theme.refresh() + reload_highlights()
```

## Lazy Lib Loading (`packer.lazy`)

Explorer, tabline, treesitter, and finder load via `packer.lazy(mod, opts)`, not `require()` in setup.
Triggers: `event`, `keys`. Options: `defer` (vim.schedule), `highlights` (auto-registers
in `M.highlight_modules`), `setup(lib)` callback.

## Shared Modules

```
Beast.View (view.lua)
  └── extended by: notify, toast, explorer, key, finder (InputView, ListView, PreviewView)

animate.lua
  └── used by: notify/ui.lua, toast/ui.lua, scroll (easings inline)

Util.create_scratch_buf
  └── used by: confirm, explorer, key, notify, toast

Util.colors.set_hl
  └── used by: all libs with highlights.lua

Theme.get / Theme.refresh
  └── used by: statusline/hlgroup.lua, tabline/icons.lua, all libs' highlights.lua
```

## ColorScheme Refresh Pipeline

```
:colorscheme X
  → ColorScheme autocmd
    → Theme.refresh()
      → M.reload_highlights()
        ├── collect: for each module in M.highlight_modules
        │     skip if parent lib not loaded
        │     skip builtin-only highlights (treesitter) when colorscheme is third-party
        │     mod = Util.mod(m)                ← fast loader, bypasses package.loaded
        │     merge mod.get() into `merged`
        │     queue mod.post_apply (if defined)
        ├── apply: vim.api.nvim_set_hl(0, group, hl) for every entry in merged
        └── post:  run queued post_apply hooks (redrawstatus, icon cache reset, …)
```

Each `<lib>/highlights.lua` exposes a pure `M.get(): table<string, hl>` and
optionally `M.post_apply()` for non-set_hl side effects (statusline cache
clear, breadcrumb redraw, tabline icon cache + redrawtabline). The dispatcher
applies all highlights in a single batched `nvim_set_hl` pass.

Lib `setup()` calls `require("beast").apply_highlights("X.highlights")` for the
first-load apply, which reuses the same get → set_hl → post_apply pipeline for
a single module.

`M.highlight_modules` includes: palette, confirm, explorer, finder, key,
notify, packer, statusline, breadcrumb, tabline, toast, indent, treesitter,
statuscolumn, git. Builtin-only (gated by `Theme.is_builtin_colorscheme()`):
treesitter.

## Patterns

- **State ownership**: only `init.lua` per library holds mutable state
- **Config**: readonly metatable with `setup(opts)` merge
- **Highlights**: `Beast<Lib>*` namespaced groups in `highlights.lua`
- **Netrw replacement**: explorer auto-opens on directory BufEnter
- **vim.notify override**: notify.setup() replaces `vim.notify`
- **Statusline = `%!`**: component-based, file_bound caching, priority truncation
- **Tabline = `%!`**: event-driven cache, 3-state highlights, anchor-based truncation
- **Transient UI buffers**: `IGNORED_FILETYPES` table (beast-* only)
- **Secure-mode safety**: statusline defers `redrawstatus` via `vim.schedule` (avoids E12)
- **Per-lib health checks**: `<lib>/health.lua` exposes `M.check()` for `:checkhealth beast.libs.<lib>`
