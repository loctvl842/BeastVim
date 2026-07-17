---
name: explorer-fs-watch
description: "Explorer Filesystem Watcher (Auto-Refresh)"
generated: 2026-05-17
---

# Dev Spec: Explorer Filesystem Watcher (Auto-Refresh)

## Summary

Add a `vim.uv.new_fs_event()`-based filesystem watcher to the explorer so it
automatically refreshes when files or directories change outside of the
explorer's own actions (e.g. `git checkout`, terminal `touch`, another plugin
writing a file). Both **snacks.nvim** and **neo-tree.nvim** use the same
`uv.new_fs_event()` approach with 100 ms debounce — we adopt that proven
pattern.

Today, the explorer only refreshes when its own actions (`create.lua`,
`delete.lua`, `rename.lua`, `paste_from_clipboard.lua`) call
`state.tree:refresh(path)` + `ui.render()`. External changes are invisible
until the user manually navigates into a directory, which forces `tree:expand`.

## Requirements

- **R1**: When the explorer is open, filesystem changes (create/delete/rename)
  inside any *expanded* directory are detected and rendered automatically.
- **R2**: Detection uses `vim.uv.new_fs_event()` — one watcher per expanded
  directory. No polling.
- **R3**: Rapid changes are debounced to a single refresh (100 ms, matching
  snacks/neo-tree).
- **R4**: Watchers are started lazily when a directory is expanded, and stopped
  when the directory is collapsed or the explorer is closed.
- **R5**: `BufWritePost` also triggers a targeted refresh of the saved file's
  parent directory, as a lightweight fallback for editors that don't fire
  `fs_event` reliably on the same process (rare, but neo-tree does this too).
- **R6**: `FocusGained` triggers a full tree refresh — covers changes made
  while Neovim was backgrounded (terminal alt-tab workflow).

### Out of scope

- `.git/index` watching (git status refresh is a separate concern; the current
  git overlay already has its own lifecycle).
- Watching directories that are *not* expanded (would create unbounded
  watchers on large repos).
- Recursive watchers (libuv `fs_event` doesn't support recursive on all
  platforms; we watch each expanded dir individually, same as snacks/neo-tree).

## Research

### Repo Search

- Searched for: `fs_event`, `fs_poll`, `watch`, `new_fs`
  (`grep -rn 'fs_event\|fs_poll\|watch\|new_fs' lua/beast/`)
- Found: No filesystem watcher code exists in BeastVim. The only `watch`
  references are unrelated (`statusline/git_branch.lua` uses a file watch for
  the git HEAD ref).
- Searched for: existing refresh/render call sites in explorer
  (`grep -rn 'tree:refresh\|ui\.render' lua/beast/libs/explorer/`)
- Found: All refresh calls are action-initiated (create, delete, rename, paste).
  `autocmds.lua` only re-renders on `BufEnter` when tree version changes from
  `focus_path` expansion — it never rescans the filesystem.
- Reuse opportunity: None — this is new functionality.

### External Research — snacks.nvim

- File: `lua/snacks/explorer/watch.lua`
- Mechanism: `vim.uv.new_fs_event()` per directory, plus `.git/index` watcher.
- Debounce: Single `uv.new_timer()` with 100 ms delay. Callback checks
  `Tree:is_dirty()` and calls `picker:find()`.
- Also listens to `BufWritePost` via picker window autocmd.

### External Research — neo-tree.nvim

- File: `lua/neo-tree/sources/filesystem/lib/fs_watch.lua`
- Mechanism: `vim.uv.new_fs_event()` per loaded folder, registered in
  `fs_scan.on_directory_loaded()`.
- Debounce: Custom event system with `debounce_frequency = 100`,
  `debounce_strategy = CALL_LAST_ONLY`.
- Fallback: `BufWritePost` when `use_libuv_file_watcher = false`.

### Decision

**Build** — a small `watch.lua` module (~80 lines) using `vim.uv.new_fs_event`
with a 100 ms debounce timer.  The pattern is well-proven by both reference
implementations.  No external dependencies.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/explorer/watch.lua` | **Create** | fs_event watchers + debounced refresh |
| `lua/beast/libs/explorer/tree.lua` | **Modify** | Hook watcher start/stop into `expand()` / `close()` / `refresh()` |
| `lua/beast/libs/explorer/autocmds.lua` | **Modify** | Add `BufWritePost` + `FocusGained` handlers |
| `lua/beast/libs/explorer/init.lua` | **Modify** | Call `watch.stop_all()` in `M.close()` |
| `lua/beast/libs/explorer/state.lua` | **Modify** | Add `watchers` field (table of active handles) |

## Implementation Phases

### Phase 1: Core Watcher Module — filesystem change detection + debounced refresh

1. **Create `watch.lua`** (File: `lua/beast/libs/explorer/watch.lua`)
   - Action: New module with these functions:
     - `M.watch(dir_path)` — creates a `vim.uv.new_fs_event()` handle,
       starts it on `dir_path`, stores in `state.watchers[dir_path]`.
       Callback calls `M._schedule_refresh(dir_path)`.
     - `M.unwatch(dir_path)` — stops and closes the handle, removes from
       `state.watchers`.
     - `M.stop_all()` — iterates `state.watchers`, stops all handles, clears
       the table.
     - `M._schedule_refresh(dir_path)` — uses a single module-level
       `vim.uv.new_timer()` (created once, reused). On fire: calls
       `state.tree:refresh(dir_path)`, then `ui.render()` inside
       `vim.schedule()`. Timer delay: 100 ms, repeat: 0 (one-shot per batch).
       Multiple dirs that change within the same 100 ms window are collected
       into a `dirty_dirs` set; the timer callback refreshes all of them.
   - Why: R1, R2, R3 — core detection and debounce.
   - Depends on: None
   - Risk: Low — `vim.uv.new_fs_event` is stable across all Neovim ≥ 0.9
     platforms.

2. **Add `watchers` to state** (File: `lua/beast/libs/explorer/state.lua`)
   - Action: Add `watchers = {}` field to the state table and to the
     `Beast.Explorer.State` type annotation.
   - Why: Watcher handles need a home in the module's single state object.
   - Depends on: None
   - Risk: Low

3. **Hook watchers into tree lifecycle**
   (File: `lua/beast/libs/explorer/tree.lua`)
   - Action:
     - In `M:expand(node)`: after `node.expanded = true`, call
       `watch.watch(node.path)`.
     - In `M:close(path)`: after setting `node.expanded = false`, call
       `watch.unwatch(node.path)`.
     - In `M:refresh(path)`: after clearing expansion, call
       `watch.unwatch(path)` for each previously-expanded child that was
       cleared.
   - Why: R4 — watchers match expanded directory set exactly.
   - Depends on: Step 1, 2
   - Risk: Medium — must be careful not to double-watch. Guard with
     `if state.watchers[path] then return end` in `watch.watch()`.

4. **Stop watchers on explorer close**
   (File: `lua/beast/libs/explorer/init.lua`)
   - Action: In `M.close()`, call `watch.stop_all()` before `ui.close()`.
   - Why: R4 — clean up handles when explorer is not visible.
   - Depends on: Step 1
   - Risk: Low

5. **Add `BufWritePost` + `FocusGained` autocmds**
   (File: `lua/beast/libs/explorer/autocmds.lua`)
   - Action: Inside `M.mount()`, register:
     - `BufWritePost` (global): get `vim.fn.expand("<afile>:p:h")`, if the
       dir is inside the tree root and expanded, call
       `watch._schedule_refresh(dir)`.
     - `FocusGained` (global): call `state.tree:refresh(state.tree.root.path)`
       then `ui.render()` (debounced via the same timer).
   - Why: R5, R6 — cover edge cases that `fs_event` misses.
   - Depends on: Step 1
   - Risk: Low

## Testing Strategy

- **Unit tests**: Not applicable — no `tests/` infrastructure exists and the
  module is I/O-bound (libuv handles). Would require a full Neovim headless
  harness.
- **Bench**: Not applicable — this is event-driven, not a hot path.
- **Manual verification**:
  1. Open explorer with `:lua require("beast.libs.explorer").open()`.
  2. In a terminal split, run `touch /path/to/open-dir/newfile.txt`.
  3. Verify the explorer shows `newfile.txt` within ~200 ms (100 ms debounce +
     render time).
  4. Run `rm /path/to/open-dir/newfile.txt` — verify it disappears.
  5. Run `mkdir /path/to/open-dir/subdir` — verify it appears.
  6. Collapse a directory, create a file inside it via terminal — verify no
     refresh happens (watcher was removed).
  7. Close the explorer, run `:lua print(vim.inspect(
     require("beast.libs.explorer.state").watchers))` — verify empty table.
  8. Save a buffer (`:w`) in a directory visible in the explorer — verify
     the tree refreshes.
  9. Background Neovim (Ctrl-Z), `touch` a file, `fg` — verify refresh on
     `FocusGained`.

## Risks & Mitigations

- **Risk**: Platform differences in `fs_event` reliability (macOS FSEvents vs
  Linux inotify vs WSL) → **Mitigation**: `BufWritePost` + `FocusGained`
  fallbacks cover the gaps. Both snacks and neo-tree ship the same combination.
- **Risk**: Watcher handle leaks if `close()` path is skipped →
  **Mitigation**: `WinClosed` autocmd already clears `state.augroup`;
  extend it to also call `watch.stop_all()`.
- **Risk**: Rapid external changes (e.g. `git checkout` touching hundreds of
  files) cause render storm → **Mitigation**: 100 ms debounce + dirty-dir
  set batches everything into a single render pass.

## Success Criteria

- [ ] External file creation/deletion/rename is reflected in the explorer
      within ~200 ms without manual intervention.
- [ ] No watcher handles remain after explorer is closed
      (`state.watchers` is empty).
- [ ] `:w` on a buffer triggers a targeted refresh of its parent directory.
- [ ] `FocusGained` after backgrounding Neovim refreshes the full tree.
- [ ] No performance regression — explorer opens and renders in the same time
      as before (watchers are started asynchronously by libuv).
- [ ] Codemap regenerated and committed alongside.
