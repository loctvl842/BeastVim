---
name: packer-update-plugin
description: Update a plugin from the Packer UI with the 'u' key
generated: 2026-07-31
---

> PM Spec: [docs/pm-specs/packer-update-plugin.md](../pm-specs/packer-update-plugin.md)

# Summary

Wire the `u` key in the Packer UI to call `vim.pack.update({name}, {force = true})` on the plugin under the cursor, reusing the existing `install`/`update` progress rendering that's already generic in `ui.lua` and `init.lua` but currently dead code (nothing triggers an update today). The only new pieces are the key binding, the action handler, and a dynamic "Updating"/"Installing" header label.

---

# Context

## Problem
`packer/ui.lua` can load and delete plugins from the dashboard, but has no action to pull a newer version of one. `vim.pack.update()` exists and Beast's own `operation.lua`/`init.lua`/`ui.lua` already type and render an `"update"` operation kind identically to `"install"` — but nothing in the codebase ever calls `vim.pack.update()`, so that code path has never run.

### Solution
Add a `u` action (mirroring the existing `x` delete action's shape) that calls `vim.pack.update({name}, {force = true})` on the plugin under the cursor. The existing `PackChangedPre`/`PackChanged` autocmd handlers and the "Operations" section renderer already handle `kind == "update"` the same way they handle `kind == "install"` — they just need something to actually fire the event. The one visible gap is the "Operations" header text, which is hardcoded to "Installing"; it needs to read "Updating" when every in-flight operation is an update. A second gap is silent no-ops: `vim.pack.update` doesn't fire any event or notification when a plugin is already current, so the handler must detect that itself and surface a message.

---

# Research

### Repo Search
- Searched `lua/beast/libs/packer/` for `update`, `del(`, `add(`: no existing code calls `vim.pack.update()` anywhere. The only `"update"` references are the already-generic `kind == "install" or kind == "update"` branches in `init.lua`'s `PackChangedPre`/`PackChanged` autocmds (~lines 284-311) and in `ui.lua`'s `_render_main` operations list (~lines 366-372), both written to handle either kind without modification.
- `operation.lua`'s `M.status[name]` entries persist across operations until `operation.clear_completed()` runs (only called from `ui.lua`'s `M.close()` and `init.lua`'s open path) — this means a stale `success`/`error` entry for a plugin can still be sitting in `operation.status` from an earlier `u` press in the same session, which matters for how "already up to date" is detected (see below).
- Reuse opportunity: **Yes** — install/update progress rendering, the refresh timer (`ui.lua:1245` `start_refresh_timer`, driven by `operation.any_in_progress()`), and the `PackChanged` state-sync are all already generic across `install`/`update`. Only the trigger (key → `vim.pack.update` call) and the header label are new.

### Built-in / Existing Lib Check
- Checked: `vim.pack.update(names?: string[], opts?: {force?, offline?, target?})` (`$VIMRUNTIME/lua/vim/pack.lua`, Neovim 0.12.2) — the only built-in API for this. With `opts.force = true` it skips the confirmation-buffer path and updates immediately (mirrors `opts.force = true` on `vim.pack.del`, already used by the delete action). The call is synchronous from the caller's perspective (`async.run(...):wait()` internally pumps the event loop), which is why the existing spinner/timer already animates correctly during the blocking `vim.pack.add()` install at startup — the same mechanism covers `vim.pack.update()` with no changes.
- Checked `get_plugin_at_cursor()` (`ui.lua`) — reused as-is, same as `delete_plugin`/`load_plugin`. A row in the "Deleted" section already resolves to "no plugin" since `state.plugins[name]` is nil there, so no extra guard is needed for that case.
- Decision: **Use** `vim.pack.update({name}, {force = true})` directly, wrapped in `pcall` following the exact pattern of the existing `_actions_handler.delete_plugin`.

---

# Architecture Changes

- `lua/beast/libs/packer/config.lua` — new `ui.actions` entry for `u` / Update, positioned right after the `x` / Delete entry.
- `lua/beast/libs/packer/ui.lua` — new `_actions_handler.update_plugin` (calls `vim.pack.update`, detects the "already up to date" no-op via an `operation.status[name].start_time` before/after comparison); dynamic "Updating"/"Installing" header label in `Main._render_main`; one new help line in `Main._render_help`.
- No changes to `state.lua`, `init.lua`, or `operation.lua` — the `"update"` kind's state tracking, event handling, and completion messaging (`"updated"`) already exist and are exercised for the first time by this feature.

## Implementation Phases

## Phase 1: Update action — pressing `u` updates the plugin under the cursor
1. **Add the `u` action entry** (File: `lua/beast/libs/packer/config.lua`)
   - Action: In `defaults.ui.actions`, insert a new entry right after the `x`/Delete entry:
     ```lua
     {
       keys = { "u" },
       label = "Update",
       key_hl = "DiagnosticWarn",
       label_hl = "Comment",
       on_press = "update_plugin",
       views = { "main" },
     },
     ```
   - Why: `mount_keymaps()` in `ui.lua` and the action-bar renderer both iterate `config.ui.actions` generically, so adding the entry is sufficient to bind the key and show it in the bar.
   - Depends on: None
   - Risk: Low

2. **Add `_actions_handler.update_plugin`** (File: `lua/beast/libs/packer/ui.lua`)
   - Action: Directly after `_actions_handler.delete_plugin`, add:
     ```lua
     function _actions_handler.update_plugin()
       local name, kind = get_plugin_at_cursor()
       if not name then
         vim.notify("No plugin under cursor", vim.log.levels.WARN, { title = "BeastVim" })
         return
       end
       if kind == "lib" then
         Toast(name .. " is a library and can't be updated", vim.log.levels.WARN, { title = "BeastVim" })
         return
       end

       local before = operation.status[name]
       local before_start = before and before.start_time
       local ok, err = pcall(vim.pack.update, { name }, { force = true })
       local after = operation.status[name]

       if not ok then
         vim.notify("Failed to update " .. name .. (err and (": " .. tostring(err)) or ""), vim.log.levels.ERROR, { title = "BeastVim" })
       elseif not after or after.start_time == before_start then
         Toast(name .. " is already up to date", vim.log.levels.INFO, { title = "BeastVim" })
       end
     end
     ```
   - Why: `pcall` mirrors `delete_plugin`'s error handling. The `start_time` snapshot-and-compare is required because `vim.pack.update` fires no event and no notification when the plugin has nothing new to pull — comparing presence alone would misfire on a second `u` press against a plugin with a leftover `success`/`error` entry from an earlier update this session.
   - Depends on: Step 1 (action must exist to be reachable, though implementation order doesn't strictly matter)
   - Risk: Low

3. **Make the Operations header reflect update-vs-install** (File: `lua/beast/libs/packer/ui.lua`, `Main._render_main`, where `ops_list` is built, ~lines 366-372)
   - Action: After building `ops_list`, compute a label:
     ```lua
     local all_updates = #ops_list > 0
     for _, item in ipairs(ops_list) do
       if item.op.kind ~= "update" then
         all_updates = false
         break
       end
     end
     local ops_label = all_updates and "Updating" or "Installing"
     ```
     Then use `ops_label` in place of the literal `"Installing"` in the existing `string.format("  Installing (%d/%d)   Sort: %s", done_count, #ops_list, sort_text)` line.
   - Why: The PM spec requires the header to say "Updating" during an update-only batch. Defaults to "Installing" for a pure-install batch or a mixed batch (rare: manually updating one plugin while another installs at startup) — matches existing behavior for every case except a pure update batch.
   - Depends on: None
   - Risk: Low

4. **Document the key in the help screen** (File: `lua/beast/libs/packer/ui.lua`, `Main._render_help`)
   - Action: Add `table.insert(lines_segments, { { text = "  u - Update plugin under cursor", hl = "BeastPackerComment" } })` next to the existing `x - Delete plugin under cursor` line.
   - Why: Matches the PM spec's requirement that the help screen list the new action, and matches the pattern used for the `x` help line.
   - Depends on: None
   - Risk: Low

---

# Testing Strategy
- Headless tests: None exist for `packer/ui.lua` (same gap as the delete feature); not writing new ones per the existing project pattern for this file.
- Bench: N/A — no bench covers `packer/ui.lua`, and this change is not on a hot path.
- Manual: Use a disposable local git repo registered as a real `vim.pack` plugin (same safe approach used to verify the delete feature — never touch the user's real installed plugins), walking through the PM spec's 5 scenarios:
  1. Check out an old commit in the disposable plugin, `vim.pack.add` it, open the UI, cursor on its row, press `u` → "Updating (0/1)" header, spinner, then success mark with elapsed ms; row returns to normal.
  2. Press `u` again on the same now-current plugin → info toast "... is already up to date", no Operations section, `operation.status` unaffected.
  3. Cursor on a library row (`󰂖`), press `u` → warning toast, nothing changes.
  4. Cursor on a blank line or in "Deleted", press `u` → "No plugin under cursor" warning.
  5. Point the disposable plugin's origin at an unreachable path, press `u` → error mark + message in Operations, plugin left untouched.
  6. Press `?` → help lists `u`; confirm action bar shows `u Update` on the main view only.
  7. `stylua --check lua/` after the edits.

# Success Criteria
- [ ] Pressing `u` on a plugin row (loaded or not loaded) starts an update immediately, no confirmation.
- [ ] Progress renders via the existing Operations section (spinner → success/error), with the header reading "Updating" for an update-only batch.
- [ ] An already-up-to-date plugin shows an info message and changes nothing.
- [ ] Pressing `u` on a library row or non-plugin line does nothing and shows a clear message.
- [ ] A failed update leaves the plugin untouched and reports the error.
- [ ] The action bar and `?` help screen show the new `u` Update action.
