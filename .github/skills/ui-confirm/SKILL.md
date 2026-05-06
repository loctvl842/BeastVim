---
name: ui-confirm
description: Replace vim.fn.confirm with a modern async confirmation UI using vim.ui.select with fallback support
---

# Confirm UI Skill (Better UX than vim.fn.confirm)

## Goal

Implement a reusable confirmation utility that replaces `vim.fn.confirm()` with a modern UI.

The new API must:

- Use `vim.ui.select()` (primary)
- Fall back to `vim.fn.confirm()` if needed
- Support async flow (callback-based)
- Return consistent values (1,2,3 like confirm)
- Be minimal and dependency-free

---

## Why

`vim.fn.confirm()` is:

- blocking ❌
- ugly ❌
- not configurable ❌

We want:

- async ✔
- nicer UI (dressing.nvim / snacks.nvim compatible) ✔
- customizable labels ✔

---

## API Design

```lua
---@class beastvim.ui.confirm.Opts
---@field prompt string
---@field choices? string[]  -- default: { "Yes", "No", "Cancel" }
---@field default? integer   -- default choice index
---@field format_item? fun(item: string): string

---@param opts beastvim.ui.confirm.Opts
---@param cb fun(choice: integer)  -- 1-based like vim.fn.confirm
function M.confirm(opts, cb) end
```

---

## Behavior

### Default choices

```lua
{ "Yes", "No", "Cancel" }
```

Return values must match `vim.fn.confirm`:

| Choice  | Return |
| ------- | ------ |
| Yes     | 1      |
| No      | 2      |
| Cancel  | 3      |
| Esc/nil | 0      |

---

## Implementation (core)

```lua
local M = {}

function M.confirm(opts, cb)
  opts = opts or {}
  local choices = opts.choices or { "Yes", "No", "Cancel" }

  -- Prefer modern UI
  if vim.ui and vim.ui.select then
    vim.ui.select(choices, {
      prompt = opts.prompt or "Confirm",
      format_item = opts.format_item,
    }, function(choice)
      if not choice then
        cb(0)
        return
      end

      for i, item in ipairs(choices) do
        if item == choice then
          cb(i)
          return
        end
      end

      cb(0)
    end)

    return
  end

  -- Fallback to vim.fn.confirm
  local buttons = table.concat(
    vim.tbl_map(function(c)
      return "&" .. c
    end, choices),
    "\n"
  )

  local choice = vim.fn.confirm(opts.prompt or "Confirm", buttons, opts.default or 1)
  cb(choice)
end

return M
```

---

## Usage Example

```lua
local confirm = require("beastvim.ui.confirm")

confirm.confirm({
  prompt = "Save changes?",
}, function(choice)
  if choice == 1 then
    print("Yes")
  elseif choice == 2 then
    print("No")
  else
    print("Cancel")
  end
end)
```

---

## UX Enhancements (optional but encouraged)

Agent SHOULD support:

### 1. Icons

```lua
choices = {
  "💾 Save",
  "🗑 Discard",
  "❌ Cancel",
}
```

---

### 2. Highlight formatting

```lua
format_item = function(item)
  if item:match("Save") then
    return "💾 " .. item
  end
  return item
end
```

---

### 3. Smart defaults

- If prompt contains "delete" → default = No
- If prompt contains "save" → default = Yes

---

### 4. Promise-style wrapper (optional)

```lua
function M.confirm_sync(opts)
  local result
  local done = false

  M.confirm(opts, function(choice)
    result = choice
    done = true
  end)

  vim.wait(10000, function() return done end)
  return result or 0
end
```

---

## Constraints

- DO NOT block UI (no heavy loops)
- DO NOT depend on external plugins
- MUST work without `dressing.nvim`
- MUST fallback safely to `vim.fn.confirm`

---

## Quality Checklist

- Works in plain Neovim (no plugins)
- Works with dressing.nvim automatically
- Esc returns 0
- Choices map correctly to index
- Async callback always called
- No crashes if vim.ui.select is missing

---

## Mental Model

This is a thin abstraction:

```
vim.fn.confirm  →  vim.ui.select wrapper
blocking        →  async
ugly            →  extensible UI
```
