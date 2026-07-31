---
name: packer-delete-plugin
description: Delete a plugin from the Packer UI with the 'x' key
generated: 2026-07-31
---

# Summary

From the Packer UI, the user can move the cursor onto a plugin and press `x` to delete it immediately. Removed plugins are tracked in a new "Deleted" section on the Packer home page for the rest of the session.

---

# Problem

The Packer UI can show, load, and profile plugins, but it has no way to remove one. To get rid of a plugin today the user has to leave the UI entirely and edit files by hand. There's no in-UI action for the most basic plugin-manager operation: taking a plugin away.

## Why now

Install/update/load already happen inside the Packer UI. Delete is the missing counterpart, and without it the UI can't be used as a complete plugin manager.

---

# Target Behavior

```
STATE 1 — Home page, before deleting anything:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Total: 42 plugins · 3 libraries   Sort: Name                │
│                                                                │
│   Loaded (28 plugins, 3 libraries)                            │
│      ✓ blink.cmp                (12.4ms)                      │
│      ✓ gitsigns.nvim              (3.1ms)                     │
│    󰂖 ✓ explorer                   (1.8ms)                     │
│      ...                                                      │
│                                                                │
│   Not Loaded (14 plugins)                                     │
│      ○ neotest                     event BufReadPost          │
│      ○ vim-dadbod                  cmd :DB                    │
│      ...                                                      │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load   S Sort   x Delete   P Profile   ? Help   q Close  │
└──────────────────────────────────────────────────────────────┘

STATE 2 — Cursor moved onto "vim-dadbod", right before pressing x:

│   Not Loaded (14 plugins)                                     │
│      ○ neotest                     event BufReadPost          │
│      ○ vim-dadbod                  cmd :DB   ← cursor here    │

STATE 3 — Immediately after pressing x:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Total: 41 plugins · 3 libraries   Sort: Name                │
│                                                                │
│   Loaded (28 plugins, 3 libraries)                            │
│      ...                                                      │
│                                                                │
│   Not Loaded (13 plugins)                                     │
│      ○ neotest                     event BufReadPost          │
│      ...                                                      │
│                                                                │
│   Deleted (1)                                                 │
│      vim-dadbod                                                │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load   S Sort   x Delete   P Profile   ? Help   q Close  │
└──────────────────────────────────────────────────────────────┘
```

---

# Scenarios

## 1 — Delete a plugin that isn't loaded

```
Step 1: The user opens the Packer UI and moves the cursor to a row in "Not Loaded" (e.g. vim-dadbod).
  The cursor sits on that plugin's line.

Step 2: The user presses x.
  The row disappears from "Not Loaded" right away. A "Deleted" section
  appears (or grows) near the bottom of the page, listing "vim-dadbod".
  A short notification confirms the plugin was removed.

Step 3: The user keeps browsing the list.
  Every other row is unaffected. The plugin counts at the top update to
  reflect one fewer plugin.
```

## 2 — Delete a plugin that is currently loaded

```
Step 1: The user moves the cursor to a row in "Loaded" (e.g. gitsigns.nvim).
  The cursor sits on that plugin's line.

Step 2: The user presses x.
  The row disappears from "Loaded" and appears under "Deleted". A
  notification confirms the removal.

Step 3: The user keeps working in the same Neovim session.
  Nothing about the currently running session breaks — the plugin's
  code keeps working until Neovim is restarted, at which point it's
  gone for good (unless it's still declared in the user's plugin list).
```

## 3 — Cursor is on a library row, not a plugin

```
Step 1: The user moves the cursor onto a row marked with the library
badge (a Beast-internal library such as "explorer", not a git plugin).
  The cursor sits on that row.

Step 2: The user presses x.
  Nothing is deleted. A short message explains that libraries can't be
  removed this way. The row stays exactly where it was.
```

## 4 — Cursor isn't on a plugin row at all

```
Step 1: The user moves the cursor onto a blank line, a section header,
or a row inside "Deleted".
  The cursor sits on a non-plugin line.

Step 2: The user presses x.
  Nothing happens except a short "nothing to delete here" message.
```

## 5 — Deletion fails

```
Step 1: The user presses x on a plugin row, but the removal can't
complete (e.g. a file-system error).
  The row briefly attempts to delete.

Step 2: The result.
  The plugin stays exactly where it was (Loaded or Not Loaded) — it is
  not added to "Deleted". An error notification explains what went
  wrong.
```

---

# Behavior Rules

- `x` only acts on plugin rows inside "Loaded" or "Not Loaded". It has no effect on library rows or any other line.
- Deletion is immediate — there is no confirmation prompt.
- A deleted plugin's row is removed from wherever it was and added to a new "Deleted" section on the same home page.
- "Deleted" only reflects plugins removed during the current Neovim session. It starts empty every time Neovim (re)starts — it is not saved anywhere.
- The "Deleted" section only appears once at least one plugin has been deleted this session; it's absent otherwise.
- If a deletion fails, the plugin is left untouched in its original section and an error is shown — it never ends up in "Deleted".
- Deleting a plugin removes it from disk only. It does not edit the user's own plugin list, so a still-declared plugin can reappear after a restart.
- The action bar and the `?` help screen both list the `x` / Delete action alongside the existing ones.

---

# Success Criteria

- [ ] Pressing `x` on a plugin row (loaded or not loaded) deletes it immediately, no confirmation needed.
- [ ] The deleted plugin's row disappears from its original section right away.
- [ ] A "Deleted" section on the home page lists every plugin removed so far this session.
- [ ] Pressing `x` on a library row or a non-plugin line does nothing and shows a clear message.
- [ ] A failed deletion leaves the plugin in place and reports the error, instead of silently losing it.
- [ ] The action bar and help screen show the new `x` Delete action.

---

# Out of Scope

- Undo / restore for a deleted plugin — not requested; the user can reinstall it the normal way if needed.
- Automatically editing the user's plugin config to drop the entry — deletion only touches what's on disk.
- Persisting the "Deleted" list across Neovim restarts.
- Bulk delete (multiple plugins at once).
