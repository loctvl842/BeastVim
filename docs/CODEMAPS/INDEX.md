<!-- Generated: 2026-04-23 | Files scanned: 50 | Token estimate: ~400 -->

# BeastVim Codemaps

Quick-reference architecture documentation for the BeastVim Neovim plugin. Regenerate with `/tec-update-codemaps` when structure changes significantly.

## Overview

BeastVim is a Lua-based Neovim plugin providing **composable UI components** built on floating windows and event-driven rendering. Each library follows consistent patterns for state management, configuration, and component lifecycle.

## Quick Links

- **[architecture.md](architecture.md)** — System overview, library inventory, dependency structure
- **[libraries.md](libraries.md)** — Detailed component APIs, data flows, and configuration for each library (Key, Notify, Explorer, Confirm, Animate)
- **[patterns.md](patterns.md)** — Code conventions, type naming, module structure, shared patterns, DRY opportunities
- **[health-config.md](../tec-config/health-config.md)** — Library health status, checkhealth support, stress tests, metrics & thresholds

## Project Stats

- **Language**: Lua
- **Framework**: Neovim plugin (no external dependencies)
- **Total files**: 50 (libraries, utils, configs, tests)
- **Total lines**: ~2,800
- **Libraries**: 6 active (Key, Notify, Toast, Explorer, Confirm, Lazy Loader)
- **Shared utilities**: 2 (View base class, Util helpers)

## How to Navigate

1. **Starting here for the first time?** → Read architecture.md first for the high-level system diagram
2. **Need to understand a specific library?** → Jump to libraries.md, find your library section
3. **Adding new code?** → Check patterns.md for conventions before writing
4. **Extending the system?** → Read patterns.md "Known DRY Opportunities" to see what's pending extraction

## Key Architecture Principles

- **Component-based**: Every library is a self-contained module with public API + internal implementation
- **Dependency rule**: Dependencies flow downward; no circular dependencies
- **State ownership**: All mutable state lives in `init.lua` of each library
- **View subclassing**: All UI components extend `Beast.View` base class
- **Lazy initialization**: Autocmds and resources initialize on first use, not at require time
- **Config-driven**: Every library with options follows the same config pattern (defaults → live cfg → setup)

## File Structure at a Glance

```
lua/beast/
├── init.lua          ← Main entry point, global setup
├── option.lua        ← Neovim options configuration
├── util/
│   └── init.lua      ← Shared utilities (wo setter, helpers)
└── libs/
    ├── view.lua      ← Base class for all UI components
    ├── animate.lua   ← Shared animation engine
    ├── key/          ← Global keymapping system
    ├── notify/       ← Notification stack with animations
    ├── explorer/     ← File tree browser
    ├── confirm/      ← Yes/no confirmation dialogs
    └── lazy_loader/  ← Lazy module initialization
```

## Design Decisions & Patterns

### Global Util Injection
**Pattern**: `_G.Util = require("beast.util")` injected in `lua/beast/init.lua:18`

**Rationale**: Neovim convention for global utility modules. Makes helpers like `Util.wo()` available everywhere without import boilerplate. While some modules (e.g., `lazy_loader/ui.lua`) explicitly require it, most rely on global injection for brevity.

**Applies to**: `key/ui.lua`, `notify/ui.lua`, `toast/ui.lua`, `explorer/ui.lua` (unguarded use of `Util.wo()`)

---

### Unguarded Window API Calls
**Pattern**: Direct `vim.api.nvim_win_set_config()` calls without `pcall` after validity checks

**Rationale**: BeastVim style accepts the rare edge case where a window becomes invalid between `is_valid()` check and API call. Guards are only used on **first creation** (`nvim_open_win`), not on subsequent mutations. Simplifies code without sacrificing robustness for typical use cases.

**Applies to**: `key/ui.lua:Main.layout()`, other libraries' window layout functions

---

### Void Functions Without Return Annotations
**Pattern**: Functions like `config.setup(opts)` omit `---@return nil` annotation

**Rationale**: BeastVim convention is to annotate only meaningful returns. Void functions are self-evident from implementation (no `return` statement = void). Reduces annotation clutter.

**Applies to**: All `setup()` functions across config modules

---

## When to Update This

Update codemaps when:
- Adding a new library (add section to libraries.md)
- Refactoring module structure (update architecture.md)
- Extracting shared code (update patterns.md "DRY Opportunities")
- Major feature additions to existing libraries (update libraries.md section)

**Staleness threshold**: 30+ days without update is considered stale. Check the `Generated:` date at the top of each file.
