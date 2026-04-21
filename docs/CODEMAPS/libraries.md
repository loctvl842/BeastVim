<!-- Generated: 2026-04-21 | Files scanned: 25 | Token estimate: ~1100 -->

# Libraries & Components

Detailed component architecture for each BeastVim library.

## Key (Global Keymapping System)

**Purpose**: Centralized keymapping with action dispatch, group tracking, and safe registration.

**Public API**:
```
Key.setup(opts)                     — initialize keymapping system
Key.safe_set(mode, key, fn, opts)   — register keymap with validation
Key.bind(mode, key, fn, opts)       — internal bind (used by safe_set)
```

**Architecture**:
```
init.lua           ← entry point, exports M
├── state.lua      ← State class (groups, handlers registry)
├── core.lua       ← bind(mode, key, fn, opts) → vim.keymap.set
├── builtin.lua    ← built-in actions (move_cursor, etc)
├── api.lua        ← API methods (bind, setup)
└── ui.lua         ← UI mode state (insert, normal, visual, etc)
```

**Key Flow**:
1. User calls `Key.safe_set("n", "<leader>e", explorer.toggle, {...})`
2. State validates and stores handler
3. Binds via `vim.keymap.set()` with group metadata
4. Keypress triggers handler function

**Defaults**: Key.setup({}) (no opts required)

---

## Notify (Notification Stack)

**Purpose**: Display styled notifications with automatic fade-out, animation, and stack management.

**Public API**:
```
notify.setup(opts)              — initialize config
notify.notify(msg, level, opts) — queue notification
notify.dismiss()                — dismiss all notifications
vim.notify = notify             — override global vim.notify
```

**Architecture**:
```
init.lua        ← entry point, __call metamethod
├── state.lua   ← State class (stack, timers)
├── stack.lua   ← Stack operations (push, dismiss, render)
├── record.lua  ← Notification record factory
├── config.lua  ← defaults, live cfg, normalizers (level, message)
├── ui.lua      ← window creation, buffer setup, rendering
├── animate.lua ← pure animation (ease_in, ease_out, run)
└── test.lua    ← test utilities
```

**Record Fields**:
```lua
{
    id        = unique string,
    message   = normalized string,
    level     = "INFO" | "WARN" | "ERROR",
    created   = timestamp,
    expires   = timestamp,
}
```

**Notification Flow**:
1. User calls `notify("message", "INFO", {...})`
2. State.schedule() handles vim_starting/fast_event edge cases
3. Record.new() creates immutable record
4. Stack.push(record) adds to stack
5. ui.render() creates window with extmarks
6. Animation runs (fade in, hold, fade out)
7. Timer dismisses on expiry

**Animation**: 
- Fade-in: `ease_out` (fast start, slow end)
- Fade-out: `ease_in` (slow start, fast end)
- Duration configurable, default 3s

**Config Defaults**:
```lua
{
    level = "INFO",
    timeout = 3000,  -- milliseconds
    position = "top-right",
    width = 40,
}
```

---

## Explorer (File Tree Browser)

**Purpose**: Interactive file tree with git status, async refresh, cut/copy/paste, and keyboard navigation.

**Public API**:
```
explorer.setup(opts)    — initialize with config
explorer.toggle(cwd)    — open/close explorer
explorer(cwd)           — shorthand for toggle (via __call)
```

**Architecture**:
```
init.lua         ← entry point, manages state lifecycle
├── state.lua    ← State class (tree, view, clipboard, mode)
├── config.lua   ← defaults, normalizers (style, icons, git)
├── tree.lua     ← Tree data structure (recursive nodes with git status)
├── ui.lua       ← scratch buffer creation, window config
├── render.lua   ← tree rendering logic (expand/collapse, filtering)
├── keymaps.lua  ← keyboard navigation ("j", "k", "l", "h", etc)
├── autocmds.lua ← auto-refresh on BufWritePost, DirChanged
├── prompt.lua   ← rename/create prompts
└── actions/     ← discrete actions
    ├── open.lua                  — open file/dir
    ├── rename.lua                — rename file
    ├── delete.lua                — delete file/dir
    ├── create.lua                — create file/dir
    ├── cut_to_clipboard.lua       — cut operation
    ├── copy_to_clipboard.lua      — copy operation
    ├── paste_from_clipboard.lua   — paste operation
    ├── navigate_up.lua            — go to parent
    ├── show_hidden.lua            — toggle hidden files
    └── set_root.lua               — change explorer root
```

**Tree Structure** (recursive):
```lua
{
    path       = absolute path,
    name       = basename,
    is_dir     = boolean,
    expanded   = boolean,
    git_status = "M" | "?" | nil,
    children   = { Tree, Tree, ... },
}
```

**State Fields**:
```lua
State = {
    tree       = Tree (root),
    view       = Beast.Explorer.View (buf+win),
    clipboard  = { path, operation="cut"|"copy" },
    mode       = "normal" | "rename" | "create",
    augroup    = integer (autocmd group),
}
```

**Keymaps** (configurable):
- `j`, `k` — move cursor up/down
- `l` — expand or open (default action)
- `h` — collapse or go up
- `a` — create new file/dir
- `d` — delete
- `r` — rename
- `x` — cut
- `c` — copy
- `v` — paste
- `.` — show hidden files toggle

**Git Status**: Async via `vim.loop.spawn("git")`

**Autocmds**:
- `BufWritePost` — refresh if file changed
- `DirChanged` — refresh if cwd changed
- Lazy-mounted on first open (not at require time)

**Config Defaults**:
```lua
{
    style = "classic",
    width = 40,
    side = "left",
    show_hidden = false,
    icons = true,
    git = true,
    icon = { dir_open = "󰝰", dir_closed = "󰉋" },
    mappings = { ["l"] = "open" },
}
```

---

## Confirm (Yes/No Dialog)

**Purpose**: Simple confirmation prompt for binary decisions.

**Public API**:
```
confirm(question, callback)  — show dialog, call callback(yes|no)
```

**Architecture**:
```
init.lua  ← entry point
└── ui.lua ← window creation, prompt handling
```

**Flow**:
1. User calls `confirm("Delete this file?", function(yes) ... end)`
2. `ui.create()` creates scratch buffer with question
3. Waits for `y` or `n` keypress
4. Closes window and calls callback with result
5. Returns immediately

**Scratch Buffer Setup**:
```lua
buftype = "nofile"
bufhidden = "wipe"
swapfile = false
filetype = "beastvim-confirm"
```

---

## Animate (Pure Animation Engine)

**Purpose**: Shared animation math for any library (currently used by Notify).

**Location**: `libs/animate.lua` (shared, not in a separate library)

**Public API**:
```
animate.run(win, from, to, duration, on_done, opts)
```

**Easing Functions**:
- `ease_out(t)` — fast start, slow end (for movement)
- `ease_in(t)` — slow start, fast end (for fade-out)
- `blend_delay(t, delay, blend_duration)` — hold constant during delay

**Parameters**:
- `win` — window integer (Neovim)
- `from` — start value (e.g., 0 for opacity)
- `to` — end value (e.g., 100)
- `duration` — milliseconds
- `on_done` — callback when animation completes
- `opts` — easing function name, blend delay, etc.

**Implementation**: Uses `vim.defer_fn()` to drive frame updates

---

## View Base Class

**Location**: `libs/view.lua` (shared base class)

**Purpose**: Unified abstraction for buffer+window pairs.

**Public API**:
```
View:extend(init_fn)  — create subclass
view:is_valid()       — check if buf+win still exist
view:close()          — close window and wipe buffer
```

**Constructor**: `View(buf, win)` → returns view instance

**All libraries that open windows subclass this** (Notify, Explorer, Confirm).

---

## Utilities

**Location**: `util/init.lua`

**Provides**:
- `wo(win, key, value)` — Neovim version-safe window option setter
- Helper functions for common operations

**Usage**: `Util.wo(win, "wrap", false)` works across Neovim versions.
