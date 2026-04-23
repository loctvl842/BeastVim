<!-- Generated: 2026-04-23 | Files scanned: 50 | Token estimate: ~950 -->

# BeastVim Architecture

A Neovim plugin written in Lua providing UI components built on floating windows, prompt buffers, and event-driven rendering.

## Project Overview

- **Language**: Lua
- **Framework**: Neovim plugin
- **Pattern**: Component-based UI with composable modules
- **Entry Point**: `init.lua` → `lua/beast/init.lua` (entry point for global setup)

## System Architecture

```
init.lua (bootstrap)
  ↓
lua/beast/
  ├── init.lua            (global setup, config merge)
  ├── option.lua          (Neovim options configuration)
  ├── util/
  │   └── init.lua        (shared utilities: wo setter, helpers)
  └── libs/               (plugin libraries)
      ├── view.lua        (base View class for buf+win pairs)
      ├── animate.lua     (pure animation math engine)
      ├── key/            (keymapping system)
      ├── notify/         (notification stack UI)
      ├── explorer/       (file tree explorer)
      ├── confirm/        (confirmation dialogs)
      └── lazy_loader/    (lazy loading system)
```

## Library Structure Pattern

Each library follows the same dependency order:

```
init.lua        ← public API, owns module-level state
├── stack.lua   ← orchestrates collection of views
│   └── win.lua ← operations on a single window
│       ├── view.lua    ← type definition
│       ├── config.lua  ← defaults, live config
│       └── animate.lua ← pure math
└── record.lua  ← pure data factory
    └── config.lua
```

**Rule**: Dependencies flow downward only. No circular dependencies.

## Core Libraries

### 1. **Key** (`libs/key/`)
Global keymapping system with action-driven architecture and centralized config.

**Files**:
- `init.lua` — public API (setup, safe_set, bind)
- `config.lua` — centralized config with defaults, live cfg, readonly metatable
- `state.lua` — keymap state (groups, handlers)
- `core.lua` — binding logic
- `builtin.lua` — built-in actions
- `api.lua` — exported API
- `ui.lua` — UI state management, action dispatcher

**Entry**: `Key.safe_set(mode, key, fn, opts)` → registers keymaps with group tracking

**Config Pattern**: `config.lua` uses readonly metatable with methods table dispatch. Actions in `ui.lua` are keyed by string names (e.g. "close", "cycle_mode") looked up via actions metatable.

### 2. **Notify** (`libs/notify/`)
Notification stack with animated floating windows.

**Files**:
- `init.lua` — public API (setup, notify, dismiss)
- `state.lua` — State class (manages notification stack)
- `stack.lua` — Stack operations (push, dismiss, render)
- `record.lua` — Notification record factory
- `config.lua` — config proxy with live cfg
- `ui.lua` — window creation and rendering
- `test.lua` — test utilities

**Flow**: `notify(msg, level, opts)` → creates Record → Stack.push → ui.render → window displayed

### 2b. **Toast** (`libs/toast/`)
Single-line notification toasts with staggered queuing.

**Files**:
- `init.lua` — public API (setup, toast, dismiss)
- `state.lua` — State class (views, queue, next_id, draining)
- `stack.lua` — Stack operations (push, drain, remove, reflow, dismiss)
- `record.lua` — Toast record factory
- `config.lua` — config proxy with live cfg
- `ui.lua` — window creation, rendering, animations
- `test.lua` — stress test utilities

**Flow**: `toast(msg, level, opts)` → Record → Stack.push → drain with stagger → ui.create/render → window displayed

### 3. **Explorer** (`libs/explorer/`)
File tree browser with async git status, keyboard navigation.

**Files**:
- `init.lua` — public API (setup, toggle)
- `state.lua` — Explorer state (tree, view, clipboard)
- `config.lua` — config proxy with normalizers
- `tree.lua` — file tree data structure (recursive)
- `ui.lua` — window creation, buffer setup
- `render.lua` — tree rendering (path expansion, filtering)
- `autocmds.lua` — auto-refresh on file events
- `keymaps.lua` — navigation keymaps
- `actions/` — individual actions (open, rename, delete, cut/paste, etc.)
- `prompt.lua` — rename/create prompts

**Flow**: `toggle(cwd)` → creates/restores Tree → ui.create → render.apply → keymaps/autocmds

### 4. **Confirm** (`libs/confirm/`)
Confirmation dialog for yes/no prompts.

**Files**:
- `init.lua` — public API (confirm)
- `ui.lua` — window and buffer creation

**Flow**: `confirm(question, callback)` → ui.create → waits for y/n input → callback

### 5. **Lazy Loader** (`libs/lazy_loader/`)
Deferred module loading with lazy initialization.

**Files**:
- `init.lua` — public API
- `state.lua` — loader state

**Purpose**: Avoid side effects at require time, only initialize on first use

## Shared Patterns

### View Base Class
All UI components extend `Beast.View` (from `libs/view.lua`):

```lua
local View = require("beast.libs.view")
---@class Beast.Foo.View : Beast.View
local FooView = View:extend(...)
```

Methods: `is_valid()`, `close()`, constructor call: `FooView(buf, win, ...)`

### Type Naming Convention
All types use `Beast.Namespace.TypeName` prefix:
```
Beast.Key.State
Beast.Notify.Record
Beast.Explorer.Config
```

### Config Pattern
Every library has config with defaults, live cfg, and setup():
```lua
local defaults = { ... }
local cfg = vim.deepcopy(defaults)
local M = {}
M.cfg = cfg
function M.setup(opts)
    cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
    M.cfg = cfg
end
```

### State Ownership
Module-level mutable state lives only in `init.lua`. Other files are stateless.

## Neovim APIs Used

- `vim.api.nvim_create_buf()` — create scratch buffers
- `vim.api.nvim_open_win()` — create floating/split windows
- `vim.api.nvim_buf_set_lines()` — set buffer content
- `vim.api.nvim_buf_set_extmark()` — apply highlights via namespace
- `vim.api.nvim_create_namespace()` — create extmark namespace
- `vim.api.nvim_create_augroup()` — autocmd groups
- `vim.api.nvim_create_autocmd()` — register autocmds
- `vim.keymap.set()` — keybindings (wrapped via Key library)

## Code Statistics

- **Total lines of Lua**: ~222
- **Total files**: 32 (includes libraries, utils, test files)
- **Libraries**: 6 (key, notify, toast, explorer, confirm, lazy_loader)
- **Dependencies**: None external (pure Neovim plugin)
