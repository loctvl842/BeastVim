<!-- Generated: 2026-04-21 | Files scanned: 32 | Token estimate: ~850 -->

# Code Patterns & Conventions

Standard patterns used throughout BeastVim.

## Type Naming

All types use the `Beast.Namespace.TypeName` prefix:

```lua
---@class Beast.Key.State
---@class Beast.Notify.Record
---@class Beast.Notify.View : Beast.View
---@class Beast.Explorer.Config
---@class Beast.Explorer.Options
```

Pattern: `Beast.` (global) + `LibraryName.` + `TypeName`

---

## Module Structure

Every library follows the same dependency order:

```
init.lua        ← public API only, exports M
├── state.lua   ← State class (if library needs mutable state)
├── stack.lua   ← orchestrate collection of views (if applicable)
│   └── win.lua ← operations on single window (if applicable)
│       ├── view.lua    ← type definition (subclass of Beast.View)
│       ├── config.lua  ← defaults, live cfg, normalizers
│       └── animate.lua ← pure math, no domain knowledge
├── record.lua  ← pure data factory (if applicable)
└── config.lua  ← config proxy with live cfg
```

**Key Rule**: Dependencies flow downward only. No circular dependencies allowed.
`init.lua` is the only file allowed to require multiple siblings.

---

## Config Pattern

Every library with configuration follows this pattern:

```lua
-- config.lua
local defaults = {
    level = "INFO",
    timeout = 3000,
    width = 40,
}

local cfg = vim.deepcopy(defaults)

local M = {}
M.cfg = cfg  -- live reference, other modules read M.cfg directly

function M.setup(opts)
    cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
    M.cfg = cfg  -- update the reference
end

return M
```

**Important**: Other modules require config once at the top and read `config.cfg.*` inline.
Never cache `config.cfg` into a local variable, as `setup()` replaces the table.

---

## State Ownership

**Rule**: Module-level mutable state lives only in `init.lua`.
Every other file is stateless — it receives state as a function argument and returns results.

```lua
-- init.lua only
local state = stack.State:new()
local augroup = nil

-- Don't store mutable state in other files
-- Instead, pass state to functions that need it
```

This means you can always trace where state changes by reading `init.lua` alone.

---

## View Subclassing

All UI components subclass `Beast.View` from `libs/view.lua`:

```lua
local View = require("beast.libs.view")

---@class Beast.Foo.View : Beast.View
---@field ns integer
---@field record Beast.Foo.Record
local FooView = View:extend(function(obj, ns, record)
    obj.ns = ns
    obj.record = record
end)

return FooView
```

Call as constructor: `FooView(buf, win, ns, record)`

Methods provided by base class:
- `view:is_valid()` — check if buf+win still exist
- `view:close()` — close window and wipe buffer

---

## Scratch Buffer Creation

**Pattern** (used in Notify, Explorer, Confirm, Key):

```lua
local buf = vim.api.nvim_create_buf(false, true)
vim.bo[buf].buftype   = "nofile"
vim.bo[buf].bufhidden = "wipe"
vim.bo[buf].swapfile  = false
vim.bo[buf].filetype  = "beastvim-mylib"
```

**Note**: Extraction to `Util.scratch_buf(filetype)` is pending (5 instances ≥ threshold).

---

## Record / Data Factory

Pure data is built in `record.lua`. A record is an immutable table with no methods:

```lua
-- record.lua
function M.new(id, message, level, opts)
    return {
        id      = id,
        message = config.normalize_message(message),
        level   = config.normalize_level(level or "INFO"),
        created = vim.fn.localtime(),
    }
end
```

**Key Points**:
- No windows, no state, no side effects
- Same input always produces same output
- Never mutated after creation
- Created by `init.lua` or stack/state functions

---

## Autocmd Lifecycle

Autocmds are registered lazily on first use via a guard, not at require time:

```lua
-- autocmds.lua
local augroup

local function ensure_autocmds()
    if augroup then return end
    augroup = vim.api.nvim_create_augroup("BeastFoo", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        callback = function() ... end,
    })
end

-- call inside M.open() or M.toggle() etc.
function M.mount()
    ensure_autocmds()
    -- ...
end
```

**Benefits**: Avoids side effects from simply loading the module.

---

## Animation Pattern

Animation lives in its own file (`animate.lua`) as a pure function:

```lua
-- animate.lua (pure math, no domain knowledge)
function M.run(win, from, to, duration, on_done, opts)
    local easing = opts.easing or "ease_out"
    -- drive frames with vim.defer_fn()
end
```

The caller (e.g., `ui.lua`) owns the domain knowledge:

```lua
-- ui.lua (knows the semantics)
function Win.fade_in(view)
    animate.run(view.win, 0, 100, 500, function()
        -- animation done
    end, { easing = "ease_out" })
end
```

**Easing Functions**:
- `ease_out(t)` — fast start, slow end (for movement)
- `ease_in(t)` — slow start, fast end (for opacity fade)
- `blend_delay(t, delay, duration)` — hold constant during delay phase

---

## Code Style

### Early Returns
Use guard clauses and early returns to flatten nesting:

```lua
function Win.render(view)
    -- stylua: ignore
    if not view:is_valid() then return end
    
    -- main logic here
end
```

The `-- stylua: ignore` comment keeps one-liners on a single line.

### Local Functions
Prefer named local functions over inline callbacks:

```lua
-- Good
local function handle_keypress(key)
    if key == "q" then ... end
end

-- Avoid (for complex logic)
keypress_handlers = {
    q = function() ... deeply nested logic ... end
}
```

### Naming
- `userProfile` not `usr`
- `validationErrors` not `errs`
- `isValid()` not `valid()`
- Full names, even if longer

### Metamethods
The `__call` metamethod makes a module callable (drop-in for `vim.notify`):

```lua
setmetatable(M, {
    __call = function(self, ...)
        return self.notify(...)
    end,
})
```

### API Safety
Use `pcall()` around Neovim API calls when the window/buffer might have been closed externally:

```lua
local ok, conf = pcall(vim.api.nvim_win_get_config, win)
if not ok then
    -- window was closed
    return
end
```

---

## Shared Modules Registry

Intentionally shared across libraries:

| Module | Path | Purpose |
|--------|------|---------|
| `Beast.View` | `beast/libs/view.lua` | Base class for buf+win pairs. Subclass this if you open windows. |
| `Util.wo` | `beast/util/init.lua` | Version-safe window option setter. Use instead of `vim.wo[win]` directly. |

---

## Known DRY Opportunities

Patterns that repeat (awaiting extraction):

### 1. Scratch Buffer Creation (5 instances)
Duplicated in: `notify/ui.lua`, `explorer/ui.lua`, `explorer/prompt.lua`, `confirm/ui.lua`, `key/ui.lua`

**Extraction trigger**: Reached threshold of 4 libraries.
**Action**: Extract to `Util.scratch_buf(filetype)` in `beast/util/init.lua`.

### 2. Read-Only Config Metatable (2 instances)
Duplicated in: `notify/config.lua`, `explorer/config.lua`

**Extraction trigger**: When a 3rd library needs the same metatable pattern.
**Extraction**: `Util.config_proxy(defaults, methods)` in `beast/util/init.lua`.

### 3. Lazy Autocmd Guard (2 instances)
In: `explorer/autocmds.lua` (state.augroup), `key/ui.lua` (mount_autocmds)

**Extraction trigger**: When a 3rd library adds autocmds.
**Standard shape**:
```lua
local function ensure_autocmds(group_name, register_fn)
    if state.augroup then return end
    state.augroup = vim.api.nvim_create_augroup(group_name, { clear = true })
    register_fn(state.augroup)
end
```

### 4. Animation Engine (1 instance)
Currently in: `notify/animate.lua`

**When another library needs animation**: Move to `beast/libs/animate.lua` (top-level shared).
