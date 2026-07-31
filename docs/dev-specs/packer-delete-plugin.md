---
name: packer-delete-plugin
description: Wire an 'x' delete action into the Packer UI backed by vim.pack.del
generated: 2026-07-31
---

> PM Spec: [docs/pm-specs/packer-delete-plugin.md](../pm-specs/packer-delete-plugin.md)

# Summary

Add a per-row `x` action to the Packer UI that deletes the plugin under the cursor via `vim.pack.del()`, immediately and without confirmation, and track deleted names in a new "Deleted" section on the home page for the rest of the session.

---

# Context

## Problem

The Packer UI (`lua/beast/libs/packer/ui.lua`) can show, load, and profile plugins, but has no delete action — `config.ui.actions` has no entry for it, and nothing in the codebase calls `vim.pack.del()`. There is also no place in `state.lua` to remember what's been removed, so even once deletion works there's nowhere to list it.

### Solution

A new `x` keymap on the main view calls a new `_actions_handler.delete_plugin`, which resolves the plugin under the cursor (reusing the existing `get_plugin_at_cursor()` helper) and calls `vim.pack.del({name}, {force = true})`. The existing `PackChanged` "delete" branch in `packer/init.lua` (already present, currently dead code) does the bookkeeping; it gains one line to push the name onto a new `state.deleted_plugins` list. `ui.lua`'s main-view renderer grows a "Deleted" section that reads that list, and the help screen and action bar get a matching entry.

---

# Research

### Repo Search
- Searched for: `del`, `remove`, `uninstall`, `delete` inside `lua/beast/libs/packer/*.lua`.
- Found: `operation.lua` only tracks `"install"|"update"|"load"` kinds — no delete/uninstall kind exists there, and it isn't needed (see below). `packer/init.lua`'s `PackChanged` autocmd already has a full `elseif kind == "delete"` branch (lines 336-342) that nils `state.plugins[name]` / `state.loaded_plugins[name]`, clears operation status, and calls `ui().refresh()` — but nothing calls `vim.pack.del()` anywhere, so this branch is currently unreachable dead code.
- Also found `lua/beast/libs/packer/test.lua`, a manual UI test helper referencing a stale shape (`state.lazy_plugins`, `state.load_profiles`, `ui.create`/`ui.render`) that doesn't match the current `state.lua`/`ui.lua` APIs, and isn't referenced by any command. Pre-existing dead code, unrelated to this feature — not touched.
- Reuse opportunity: Yes — the `PackChanged` "delete" handling, `get_plugin_at_cursor()`, the `_actions_handler` / `config.ui.actions` pattern (used by `load_plugin`, `sort`, etc.), and the `Toast`/`vim.notify` conventions already used in `ui.lua` are all reused as-is.

### Built-in / Existing Lib Check
- Checked: `vim.pack.del(names, opts)` in `$VIMRUNTIME/lua/vim/pack.lua` (Neovim 0.12.2, the version this repo targets).
- Found: `vim.pack.del()` is exactly the operation needed — it removes plugin directories from disk and fires `PackChangedPre`/`PackChanged` (`kind = "delete"`) synchronously via `nvim_exec_autocmds`. Two behaviors matter:
  - It refuses to delete a plugin considered "active" (added to the session via `vim.pack.add()`) unless `opts.force = true`. Beast's `packer/init.lua` calls `vim.pack.add(vim_pack_specs, {...})` once for the *entire* spec list at startup, so every plugin visible in the UI — "Loaded" and "Not Loaded" alike, since "Not Loaded" only means Beast's own lazy `require()`/config hasn't run — is already "active" from `vim.pack`'s point of view. Without `force = true`, `vim.pack.del()` raises an error ("Some plugins are active and were not deleted...") on nearly every call. Passing `force = true` is required for the PM spec's "immediate delete, no confirmation" behavior to work at all, not an optional hardening.
  - On success it already calls `vim.notify("vim.pack: Removed plugin '<name>'", INFO)` itself. The PM spec's "a short notification confirms the plugin was removed" is satisfied by Neovim itself — no new Toast needed for the success path.
  - Its one non-exceptional failure path ("Nothing to remove") just warns and returns without deleting and without raising a Lua error, so a caller can't rely solely on `pcall` succeeding to mean "it worked."
- Decision: **Use** `vim.pack.del()` directly with `force = true`, wrapped in a `pcall` plus a post-call check of `state.plugins[name]` (still non-nil means the delete didn't actually happen) to catch that silent-failure path.

---

# Architecture Changes

- `lua/beast/libs/packer/state.lua` — add `M.deleted_plugins = {}` (array of names, most-recent first) to the state table.
- `lua/beast/libs/packer/init.lua` — one-line addition inside the existing `elseif kind == "delete"` branch of the `PackChanged` autocmd (~line 336-342): record the deleted name.
- `lua/beast/libs/packer/config.lua` — add a `deleted` trash icon to `ui.icons`; add an `x` / Delete entry to `ui.actions` (`views = { "main" }`).
- `lua/beast/libs/packer/ui.lua` — new `_actions_handler.delete_plugin`; new "Deleted" section in `Main._render_main`; new help line in `Main._render_help`.

## Implementation Phases

## Phase 1: Core delete action — wire `x` to an actual, working deletion

1. **Add `deleted_plugins` to state** (File: `lua/beast/libs/packer/state.lua`)
   - Action: Add `deleted_plugins = {}, ---@type string[] Names of plugins deleted this session, most-recent first` to the `M` table declaration alongside the other `---@type` fields.
   - Why: Somewhere durable (for the session) to remember what was removed, since the `PackChanged` handler nils the plugin's entry out of `state.plugins` entirely.
   - Depends on: None
   - Risk: Low

2. **Record the name on delete** (File: `lua/beast/libs/packer/init.lua`, inside the `PackChanged` autocmd's `elseif kind == "delete"` branch)
   - Action: Add `table.insert(state.deleted_plugins, 1, name)` alongside the existing `state.plugins[name] = nil` / `state.loaded_plugins[name] = nil` / `operation().status[name] = nil` / `ui().refresh()` lines. Insert at position 1 so the list stays most-recent-first.
   - Why: This branch already exists and already fires on every successful `vim.pack.del()` — it's the single correct place to capture the name before it's discarded.
   - Depends on: Step 1
   - Risk: Low

3. **Add the `x` action entry** (File: `lua/beast/libs/packer/config.lua`)
   - Action: In `defaults.ui.actions`, insert a new entry right after the `S` / Sort entry:
     ```lua
     {
       keys = { "x" },
       label = "Delete",
       key_hl = "DiagnosticError",
       label_hl = "Comment",
       on_press = "delete_plugin",
       views = { "main" },
     },
     ```
   - Why: `mount_keymaps()` in `ui.lua` iterates `config.ui.actions` to set up buffer-local keymaps and the action-bar footer automatically — adding the entry here is sufficient to get both the keybinding and its footer label for free.
   - Depends on: None
   - Risk: Low

4. **Implement `_actions_handler.delete_plugin`** (File: `lua/beast/libs/packer/ui.lua`, placed directly after `_actions_handler.load_plugin`)
   - Action:
     ```lua
     function _actions_handler.delete_plugin()
       local name, kind = get_plugin_at_cursor()
       if not name then
         vim.notify("No plugin under cursor", vim.log.levels.WARN, { title = "BeastVim" })
         return
       end
       if kind == "lib" then
         Toast(name .. " is a library and can't be deleted", vim.log.levels.WARN, { title = "BeastVim" })
         return
       end

       local ok, err = pcall(vim.pack.del, { name }, { force = true })
       if not ok or state.plugins[name] then
         vim.notify("Failed to delete " .. name .. (err and (": " .. tostring(err)) or ""), vim.log.levels.ERROR, { title = "BeastVim" })
       end
     end
     ```
   - Why: `get_plugin_at_cursor()` already distinguishes plugin vs. library rows and returns `nil` for anything else (including, once Phase 2 lands, rows inside "Deleted" — those names are no longer in `state.plugins`/`state.libs`). `force = true` is required per the Research section. The `state.plugins[name]` re-check catches `vim.pack.del()`'s silent "Nothing to remove" path. No manual `ui().refresh()` call is needed — the `PackChanged` handler (Step 2) already does it, synchronously, before `vim.pack.del()` returns.
   - Depends on: Steps 1-3
   - Risk: Medium — this is the one call that bypasses `vim.pack`'s own "active plugin" guard rail; verify manually against a real plugin (Testing Strategy, scenario 1-2) before considering this phase done.

## Phase 2: "Deleted" section + help text — make it visible

1. **Add the trash icon** (File: `lua/beast/libs/packer/config.lua`)
   - Action: Add `deleted = "󰆴 ", -- trash / deleted` to `ui.icons`.
   - Why: Consistent with how every other row type (loaded, pending, lib) gets its own icon constant instead of an inline literal.
   - Depends on: None
   - Risk: Low

2. **Render the "Deleted" section** (File: `lua/beast/libs/packer/ui.lua`, in `Main._render_main`, appended immediately after the existing "Not Loaded" block's trailing blank-line insert)
   - Action:
     ```lua
     if #state.deleted_plugins > 0 then
       table.insert(lines_segments, {
         { text = "  Deleted ", hl = "BeastPackerH2" },
         { text = "(" .. #state.deleted_plugins .. ")", hl = "BeastPackerComment" },
       })
       for _, name in ipairs(state.deleted_plugins) do
         table.insert(lines_segments, {
           { text = "    " .. config.ui.icons.deleted, hl = "BeastPackerError" },
           { text = name, hl = "BeastPackerComment" },
         })
       end
       table.insert(lines_segments, { new_line })
     end
     ```
   - Why: Matches the section style already used for "Loaded"/"Not Loaded" (`BeastPackerH2` header + count, indented rows). Only renders when non-empty, per the PM spec ("Deleted" section is absent until the first deletion). No new highlight groups needed — `BeastPackerH2`, `BeastPackerComment`, and `BeastPackerError` all already exist in `highlights.lua`.
   - Depends on: Phase 1 (there must be a way to populate `state.deleted_plugins`), Step 1 of this phase (icon)
   - Risk: Low

3. **Add the help line** (File: `lua/beast/libs/packer/ui.lua`, in `Main._render_help`)
   - Action: Insert `table.insert(lines_segments, { { text = "  x - Delete plugin under cursor", hl = "BeastPackerComment" } })` next to the existing `<CR>` line.
   - Why: Keeps the `?` help screen exhaustive, matching every other action already listed there.
   - Depends on: None
   - Risk: Low

---

# Testing Strategy

No existing headless test suite covers `packer/ui.lua` (only the unrelated, already-broken `test.lua` manual helper, which is not touched by this work). Verification is manual against the real UI, per the PM spec's scenarios:

- Manual: Open the Packer UI with `<leader>p` (wired in `lua/beast/init.lua:395`).
  1. Move the cursor to a plugin row under "Not Loaded", press `x` → row disappears, `Total:` count decrements by one, a `vim.pack: Removed plugin '<name>'` notification appears, and a "Deleted (1)" section appears listing it (PM Scenario 1).
  2. Move the cursor to a plugin row under "Loaded", press `x` → same result; nothing else in the running session breaks (PM Scenario 2).
  3. Move the cursor to a row with the library badge (`󰂖`), press `x` → nothing is removed, a warning toast explains libraries can't be deleted this way, the row is unchanged (PM Scenario 3).
  4. Move the cursor to a blank line, a section header, or (after step 1) a row inside "Deleted", press `x` → "No plugin under cursor" warning, nothing changes (PM Scenario 4).
  5. Press `?` → help screen lists the new `x` action.
  6. Confirm the action bar shows `x Delete` on the main view, and does *not* show it on the Profile (`P`) or Help (`?`) views.
- No bench required — this doesn't touch a hot path (startup, rendering loop, or lazy-load trigger); it's a synchronous, user-initiated one-shot action.

# Success Criteria

- [x] Pressing `x` on a plugin row (loaded or not loaded) deletes it immediately, no confirmation needed.
- [x] The deleted plugin's row disappears from its original section right away.
- [x] A "Deleted" section on the home page lists every plugin removed so far this session, most recent first.
- [x] Pressing `x` on a library row or a non-plugin line does nothing and shows a clear message.
- [x] A failed deletion leaves the plugin in place and reports the error, instead of silently losing it.
- [x] The action bar and help screen show the new `x` Delete action.

---

## Completed

**2026-07-31** — Both phases implemented and verified against a real, disposable `vim.pack`-managed plugin (a throwaway local git repo, not any of the user's actual installed plugins) driven end-to-end through the real UI buffer and keymap.

- `79736a5` feat(packer): add x keybinding to delete plugin from UI
- `6845340` feat(packer): show a Deleted section for plugins removed this session (fixed an icon/name spacing inconsistency flagged by code review before committing)

Verification: `stylua --check` clean on all four touched files after each phase. No headless test suite exists for `packer/ui.lua` (only the pre-existing, unrelated, already-broken `test.lua` manual helper — untouched). Manual E2E pass (headless Neovim, real `vim.pack.add`/`vim.pack.del`, real UI buffer + `nvim_feedkeys`) confirmed: deleting a plugin actually removes its directory from disk, updates `state.plugins`/`state.deleted_plugins`, and re-renders the "Deleted" section live; pressing `x` on a library row or a blank line leaves `state.plugins` untouched; the `?` help screen documents the new key.
