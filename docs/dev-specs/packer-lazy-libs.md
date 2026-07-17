---
name: packer-lazy-libs
description: "`packer.lazy()` — Lazy Loading for Beast Libraries"
generated: 2026-05-13
---

# Problem

All beast libraries are eagerly required during `beast.setup()`, adding
their full require chain to the critical startup path. Today's health check
shows **tabline costs ~8.2 ms** and **explorer costs ~3.4 ms** — together
over 11 ms of startup time for features that aren't needed until first
screen render or first key press.

Packer already has a clean, trigger-based lazy loading system for plugins.
Its triggers (`event`, `keys`, `cmd`, `filetype`, `path`) all accept a
generic `load_fn(name, reason)` parameter — they don't know or care that
`load_fn` is `state.load` (which calls `packadd`). We can pass a different
`load_fn` that does `require(mod) + setup()` instead.

# Proposed API

```lua
-- In packer/init.lua (public)
function M.lazy(mod, opts)
```

### Signature

| Param | Type | Description |
|-------|------|-------------|
| `mod` | `string` | Lua module path (e.g. `"beast.libs.tabline"`) |
| `opts.event` | `string\|string[]` | Event trigger(s) — same as plugin lazy.event |
| `opts.keys` | `KeySpec[]` | Key trigger(s) — same as plugin lazy.keys |
| `opts.filetype` | `string\|string[]` | Filetype trigger(s) |
| `opts.setup` | `fun(lib: table)` | Called after `require(mod)` — receives the loaded module |
| `opts.highlights` | `string?` | Highlight module to register for ColorScheme reload |

Triggers not included: `cmd` (libs don't define user commands), `path`
(libs don't match file patterns), `module` (libs are the module — circular).
Can be added later if needed.

### Usage in `beast/init.lua`

```lua
-- Before (eager — 8.2 ms on startup)
local tabline = require("beast.libs.tabline")
tabline.setup({ ... })

-- After (deferred to UIEnter)
packer.lazy("beast.libs.tabline", {
  event = "UIEnter",
  highlights = "beast.libs.tabline.highlights",
  setup = function(tabline)
    tabline.setup({
      max_name_width    = 30,
      min_cell_width    = 18,
      sidebar_filetypes = { ["neo-tree"] = "EXPLORER", ["beast-explorer"] = "EXPLORER" },
      show_close_button = true,
      show_modified     = true,
      show_diagnostics  = true,
    })
  end,
})

-- Before (eager — 3.4 ms on startup)
local explorer = require("beast.libs.explorer")
explorer.setup(cfg.explorer)
Key.safe_set("n", "<leader>e", explorer.toggle, { ... })

-- After (deferred to key press)
packer.lazy("beast.libs.explorer", {
  keys = {{
    "<leader>e",
    function() require("beast.libs.explorer").toggle() end,
    desc = "Toggle explorer panel",
    group = "Explorer",
  }},
  highlights = "beast.libs.explorer.highlights",
  setup = function(explorer) explorer.setup(cfg.explorer) end,
})
```

# Design

### How `packer.lazy()` works internally

```
packer.lazy(mod, opts)
  │
  ├─ Create load_lib(name, reason):
  │    if already_loaded → return
  │    lib = require(mod)
  │    opts.setup(lib)
  │    register opts.highlights into beast.highlight_modules
  │    mark loaded
  │
  ├─ Create pseudo-spec: { name = mod }
  │
  └─ Wire triggers (reuse existing trigger modules as-is):
       opts.event    → event_trigger.setup(spec, events, load_lib)
       opts.keys     → keys_trigger.setup(spec, keys, load_lib)
       opts.filetype → filetype_trigger.setup(spec, filetypes, load_lib)
```

The triggers don't need any changes — they already accept any `load_fn`.

### Key trigger flow (explorer example)

```
1. packer.lazy() registers temp <leader>e via keys_trigger.setup()
2. User presses <leader>e
3. Temp keymap fires:
   a. Delete temp mapping
   b. load_lib() → require("beast.libs.explorer") + setup()
   c. vim.schedule:
      - Set real keymap: <leader>e → explorer.toggle (rhs function)
      - Execute rhs() immediately (opens explorer on this press)
4. Subsequent <leader>e presses hit the real keymap directly
```

### Highlight modules & ColorScheme reload

Current `reload_highlights()` eagerly re-requires all highlight modules,
including ones for libs that haven't loaded yet. Fix: guard each reload
with a `package.loaded` check on the parent module.

```lua
function M.reload_highlights()
  for _, mod_name in ipairs(M.highlight_modules) do
    local parent = mod_name:gsub("%.highlights$", "")
    -- stylua: ignore
    if not package.loaded[parent] then goto continue end
    package.loaded[mod_name] = nil
    pcall(require, mod_name)
    ::continue::
  end
end
```

When `load_lib` runs, it appends `opts.highlights` to `M.highlight_modules`
(if not already there) so subsequent ColorScheme changes pick it up.

### Type definition

```lua
---@class Beast.Packer.LazyLibOpts
---@field event? string|string[]
---@field keys? Beast.KeymapSpec|Beast.KeymapSpec[]
---@field filetype? string|string[]
---@field setup fun(lib: table)
---@field highlights? string
```

# Scope

### In scope (Phase 1)

| Task | File | Description |
|------|------|-------------|
| Add `M.lazy()` | `packer/init.lua` | New public method, ~25 lines |
| Guard `reload_highlights` | `beast/init.lua` | Skip unloaded parent modules |
| Migrate tabline | `beast/init.lua` | `event = "UIEnter"` |
| Migrate explorer | `beast/init.lua` | `keys = { "<leader>e" ... }` |
| Remove from static highlights | `beast/init.lua` | Remove tabline/explorer from list (registered dynamically) |
| Verify startup improvement | — | Re-run health check, compare |

### Out of scope

- Lazy loading for statusline (renders on first screen — keep eager)
- Lazy loading for notify/toast (`_G.Toast` used by packer itself — keep eager)
- Lazy loading for key/buf (globals, used everywhere — keep eager)
- Lazy loading for confirm (only 0.64 ms — not worth the complexity yet)
- Adding `cmd` / `path` / `module` triggers (YAGNI — add when needed)
- Refactoring trigger modules themselves (they work as-is)

### Libs assessment

| Lib | Startup cost | Candidate? | Trigger | Notes |
|-----|-------------|-----------|---------|-------|
| tabline | 8.2 ms | ✅ Yes | `UIEnter` | No dependents at startup |
| explorer | 3.4 ms | ✅ Yes | `keys` | Only accessed via `<leader>e` |
| statusline | 2.1 ms | ❌ No | — | Must render on first screen |
| notify | 2.6 ms | ❌ No | — | `vim.notify` replacement, needed early |
| toast | 2.6 ms | ❌ No | — | `_G.Toast` used by packer |
| confirm | 0.6 ms | ❌ Later | — | Small savings, not worth it now |
| key | 0.6 ms | ❌ No | — | `_G.Key` used everywhere |
| packer | 5.1 ms | ❌ No | — | Loads plugins, must run early |

### Expected improvement

- **Tabline**: ~8.2 ms removed from critical path
- **Explorer**: ~3.4 ms removed from critical path
- **Total**: ~11.6 ms saved → startup should drop from ~52 ms (excluding
  cold outlier) to ~40 ms

# Risks

1. **Tabline flash**: If `UIEnter` fires after the first screen render,
   users see the default tabline momentarily. Mitigation: `UIEnter` fires
   before the first redraw in practice. If flashing occurs, switch to
   `VimEnter` or set `vim.o.showtabline = 0` until loaded.

2. **Explorer keymap conflict**: If another plugin or config binds
   `<leader>e` before packer.lazy registers, the temp keymap may not take
   precedence. Mitigation: packer.lazy should run after all other keymaps
   are set up (it already does — packer.setup runs late in beast.setup).

# Success Criteria

1. `packer.lazy()` API works for `event` and `keys` triggers
2. Tabline loads on `UIEnter`, not at startup
3. Explorer loads on first `<leader>e` press, not at startup
4. ColorScheme changes still reload highlights correctly for both eager and lazy libs
5. Health check shows startup mean improvement of ≥ 8 ms
6. No visible UI flash or delay on first use
