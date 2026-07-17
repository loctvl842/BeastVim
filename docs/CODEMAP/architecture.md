<!-- Generated: 2026-06-10 | Files scanned: 246 | Token estimate: ~1100 -->

# Architecture

## Entry Point

```
init.lua → require("beast").setup()
```

## Module Tree

```
lua/beast/
├── init.lua              ← top-level setup; registers globals + wires every
│                           lib through packer.lazy()
├── option.lua            ← vim options
├── icon.lua              ← icon definitions (Beast.Icon)
├── profile.lua           ← lightweight profiler (per-fn count/total/self stats)
├── hl_reload.lua         ← M.highlight_modules registry + apply_highlights /
│                           reload_highlights + ColorScheme autocmd dispatcher
├── theme/
│   ├── init.lua          ← Theme.get / Theme.refresh / Theme.is_builtin_colorscheme()
│   ├── highlights.lua    ← BeastTheme* base groups (builtin-only)
│   └── blink.lua         ← blink.cmp highlight overrides
├── util/
│   ├── init.lua          ← Util.wo, Util.mod, Util.hrtime, find_normal_win, ...
│   ├── colors.lua        ← Util.colors.{set_hl, blend, lighten, inspect}
│   └── root.lua          ← project root detection
├── libs/
│   ├── _meta.lua         ← ---@meta-only: Beast.Lib.Meta type contract
│   ├── view/             ← Beast.View instance + Beast.View.Module
│   │   ├── init.lua      ← View(buf, win), View:extend(init)
│   │   ├── buf.lua       ← View.buf.new / View.buf.delete
│   │   └── win.lua       ← View.win.wo / View.win.find_normal()
│   ├── animate.lua       ← shared animation engine (pure math, M.tween)
│   ├── async.lua         ← cooperative coroutine scheduler (uv check loop)
│   ├── autopairs/        ← native insert-mode autopairs (no plugin)
│   ├── breadcrumb/       ← winbar breadcrumb (filepath + treesitter context)
│   ├── confirm/          ← vim.fn.confirm drop-in (lazy via module trigger)
│   ├── explorer/         ← file explorer (split panel + sticky headers + git)
│   ├── finder/           ← fuzzy finder (files, buffers, grep, help, …)
│   ├── git/              ← native git signs / preview / stage / blame
│   ├── indent/           ← indent guides + scope (decoration provider)
│   ├── key/              ← keybinding registry, cheatsheet, press-and-wait hint
│   ├── lsp/              ← Lsp.register / capabilities / on_attach dispatcher
│   ├── notify/           ← floating notification stack
│   ├── packer/           ← plugin loader + packer.lazy() (event/keys/
│   │                       filetype/module/cmd/path triggers)
│   ├── scroll/           ← smooth viewport scrolling
│   ├── starter/          ← native intro screen extensions (key hint rows)
│   ├── statuscolumn/     ← native %! statuscolumn
│   ├── statusline/       ← native %! statusline + per-lib health.lua
│   ├── tabline/          ← native %! tabline
│   ├── toast/            ← toast notification stack
│   ├── treesitter/       ← parser install + scope queries
│   └── window/           ← auto-width + maximize/restore splits
└── plugins/
    ├── init.lua           ← plugin spec imports
    ├── colorscheme.lua    ← colorscheme plugin spec
    └── development.lua    ← dev-only plugin specs
```

## Globals Registered at Setup

| Global | Module | Purpose |
|--------|--------|---------|
| `Util` | beast.util | Window opts, scratch buf, colors, `mod()` fast loader |
| `Theme` | beast.theme | Theme palette (accent1…, dimmed1…); replaces old `Palette` |
| `Key` | beast.libs.key | Keymap registration + viewer |
| `View` | beast.libs.view | View instance constructor + `.buf`/`.win` submodules |
| `Icon` | beast.icon | Icon lookup |
| `Toast` | beast.libs.toast | Toast notifications (registered when toast loads) |
| `Lsp` | beast.libs.lsp | LSP infra: register, capabilities, on_attach |
| `gh` | (closure) | `gh("user/repo") → "https://github.com/user/repo"` for plugin specs |

Note: legacy `Buffer` global removed — use `View.buf.delete` instead.

## Setup Flow

```
beast.setup(opts)
  1.  require beast.libs.packer + beast.option
  2.  Register globals: Util, Theme, Key, View, Icon
  3.  packer.lazy("beast.theme", VimEnter+defer) → Theme.setup() +
        hl_reload.setup() + Theme.refresh() + reload_highlights()
  4.  packer.lazy notify / toast (VimEnter+defer; toast sets _G.Toast)
  5.  packer.lazy confirm (module trigger: beast.libs.confirm)
  6.  packer.lazy statusline (VimEnter+defer) — uses components registry
  7.  packer.lazy breadcrumb / tabline / statuscolumn (VimEnter+defer)
  8.  packer.lazy git (event-driven) — exposes ]c/[c/<leader>g* keymaps
  9.  packer.lazy explorer (VimEnter+defer + <leader>e)
  10. packer.lazy indent (VimEnter+defer; decoration provider)
  11. packer.lazy treesitter (FileType)
  12. packer.lazy finder (keys: <leader>f/b/F/h/c)
  13. packer.lazy scroll (event)
  14. packer.lazy window (keys: <leader>zz/<leader>z=)
  15. packer.lazy autopairs (InsertEnter)
  16. packer.lazy key (VimEnter) — eager Key.setup + <leader>d/<leader>n/<leader>p
  17. Lsp.setup(cfg.lsp) — EAGER (must register vim.lsp.enable before FileType)
        + Lsp.on_attach binds gd/gr/gD/gi via finder picker
  18. packer.setup(cfg.packer) — git-clone + lazy-load plugins
  19. starter.setup(cfg.starter) — EAGER (registers VimEnter autocmd)
```

## Lazy Lib Loading (`packer.lazy`)

Every lib above (except `theme.setup`'s eager pieces, `lsp`, and `starter`)
loads via `packer.lazy(mod, opts)`. Trigger types:

| Trigger | Field | Sync? | Use case |
|---------|-------|-------|----------|
| event | `event` | per-event `defer` flag | VimEnter, InsertEnter, FileType |
| keys | `keys` | always sync | user-initiated, must load before keystroke |
| filetype | `filetype` | always sync | render-critical |
| module | `module` | always sync | direct `require("beast.libs.X")` from keymap bodies |

`module` is the newest addition — closes the half-init hole where a keymap
body's `require()` could return the lib before `setup()` ran. See
`lua/beast/libs/packer/triggers/module.lua`.

## Shared Modules

```
Beast.View / Beast.View.Module (view/init.lua + buf.lua + win.lua)
  └── extended by: notify, toast, explorer, key, finder
                   (InputView, ListView, PreviewView, ...)

animate.lua  (M.tween primitive)
  └── used by: notify/ui.lua, toast/ui.lua, scroll, indent

async.lua    (coroutine scheduler, 10 ms time budget per tick)
  └── used by: finder, explorer, git

Util.colors.set_hl
  └── used by: every lib with highlights.lua

Theme.get / Theme.refresh
  └── used by: statusline/hlgroup.lua, tabline/icons.lua,
               all libs' highlights.lua
```

## ColorScheme Refresh Pipeline

```
:colorscheme X
  → ColorScheme autocmd (registered by hl_reload.setup)
    → Theme.refresh()
      → M.reload_highlights()
        ├── for each module in M.highlight_modules:
        │     skip if parent lib not loaded
        │     skip builtin-only highlights (treesitter) on third-party schemes
        │     mod = Util.mod(m)               ← fast loader, bypasses package.loaded
        │     merge mod.get() into `merged`
        │     queue mod.post_apply (if defined)
        ├── apply: single nvim_set_hl batch pass
        └── post:  run queued post_apply hooks (redrawstatus, icon cache, …)
```

Each `<lib>/highlights.lua` exposes a pure `M.get(): table<string, hl>` and
optional `M.post_apply()`. See ADR-026 for the contract.

`M.highlight_modules` includes: `beast.theme.highlights`, `beast.theme.blink`,
plus `<lib>.highlights` for confirm, explorer, finder, key, notify, packer,
statusline, breadcrumb, tabline, toast, indent, treesitter, statuscolumn, git.
Builtin-only (gated by `Theme.is_builtin_colorscheme()`): treesitter,
theme.highlights, theme.blink.

## Patterns

- **State ownership**: only `init.lua` per library holds mutable state
- **Config**: readonly metatable with `setup(opts)` merge
- **Highlights**: `Beast<Lib>*` namespaced groups in `highlights.lua` (ADR-026)
- **Lib metadata**: every `lua/beast/libs/<lib>/init.lua` exposes `M.meta`
  matching `Beast.Lib.Meta` (`_meta.lua`)
- **Netrw replacement**: explorer auto-opens on directory BufEnter
- **vim.notify override**: notify.setup() replaces `vim.notify`
- **Statusline / Tabline = `%!`**: native, no third-party framework (ADR-009)
- **Transient UI buffers**: `beast-*` filetype convention
- **Secure-mode safety**: deferred redraws via `vim.schedule` (avoids E12)
- **Per-lib health checks**: `:checkhealth beast.libs.<lib>`
- See AGENTS.md §§ *Shared Modules Registry*, *Type Naming*, *View Pattern*
  for the long form.
