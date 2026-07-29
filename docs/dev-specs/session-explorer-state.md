---
name: session-explorer-state
description: Session save/restore captures the explorer's root + expanded folders + focus in a sidecar file and reconstructs the panel via explorer.open() on load
generated: 2026-07-28
---

> PM Spec: [docs/pm-specs/session-explorer-state.md](../pm-specs/session-explorer-state.md)

# Summary
Session save closes the explorer window right before `:mksession!` and writes a small JSON sidecar next to the `.vim` session file recording the explorer's root, expanded folders, and whether focus was on the panel or the last file. Session load sources the `.vim` file as it does today, then reconstructs the explorer from the sidecar by calling `explorer.open()` (given a new opt-in flag that skips its interactive re-rooting heuristic) and re-expanding the remembered folders.

---

# Context

## Problem
The explorer panel (`lua/beast/libs/explorer/`) is a scratch buffer (`buftype=nofile`, name `beast-explorer`) whose entire tree lives in Lua state (`state.tree`, `state.view`) that is rebuilt only by calling `explorer.open()`. `:mksession`/`:source` has no way to reconstruct that Lua state — sourcing a session file never calls `explorer.open()`, so today the explorer is simply gone after a session reload, and letting `:mksession` try to capture the synthetic buffer's window is undefined/fragile territory (no real file on disk backs it).

### Solution
`session.save()` gains an explorer-aware step: capture `{root, open_dirs, focus}` from `beast.libs.explorer.state`, close the explorer window (so `:mksession` never sees the synthetic buffer), then write the capture to `<same identity>.explorer.json` next to the `.vim` file. `session.load()` gains a matching step: after sourcing the `.vim` file, read the sidecar (if present and its root still exists) and call `explorer.open(root, { restore = true })` — a new opt-in flag added to `explorer.open()` that skips the "re-root to whatever file happens to be current" heuristic used by the interactive `<leader>e` toggle — then re-expand each remembered folder and restore focus to whichever side (explorer vs. last file) had it at quit time.

---

# Research

### Repo Search
- Searched for: `vim.json`, `stdpath("state")`, existing sidecar/state-file patterns, `mksession`/`sessionoptions` usage, existing tests/benches for `session` and `explorer`.
- Found: `vim.json.decode` is already used in `lua/beast/libs/finder/source/live_grep/init.lua:159` — precedent for JSON in this codebase. `lua/beast/libs/session/config.lua` already defines the per-project state directory (`vim.fn.stdpath("state") .. "/sessions/"`) that `session/init.lua` writes `.vim` files into — the natural home for a sidecar file. `tests/test-session.lua` is the only existing session test and establishes the exact pattern to extend (temp git repo via `vim.system`, `encode()` helper duplicated for path assertions, `trigger_save()` via `vim.api.nvim_exec_autocmds("VimLeavePre", {})`). `scripts/bench-explorer.lua` is the mandatory perf bench for the explorer lib and shows the global stubs (`_G.Theme`, `_G.Util`, `_G.View`, `_G.Toast`, a devicons stub) required to load explorer modules headlessly.
- Reuse opportunity: Yes — reuse `vim.json.encode`/`decode` (builtin), the existing per-project+branch path-encoding scheme (`encode()` / `branch_path()` / `plain_path()` in `session/init.lua`) for the sidecar filename so no new session-identity scheme is introduced, and the `bench-explorer.lua` global-stub pattern for the new test scenarios.

### Built-in / Existing Lib Check
- Checked: `vim.json.encode`/`vim.json.decode` (builtin), `vim.fn.writefile`/`vim.fn.readfile`/`vim.fn.delete` (builtin), `View.win.find_normal()` (`lua/beast/libs/view/win.lua`, already used by `explorer.open()` to locate the "main" window), `Beast.Explorer.Tree:open(path)` (`lua/beast/libs/explorer/tree.lua`, already walks a path's ancestors and marks each `open = true` — exactly what's needed to re-expand a remembered folder).
- Found: Everything needed already exists as a Neovim builtin or an existing lib API — no third-party dependency required, no new persistence mechanism to design.
- Decision: **Reuse** — builtins for the sidecar file I/O, and the existing `explorer.open()` / `state.tree` / `View.win` APIs to reconstruct the panel. The only new code is the capture/restore glue in `session/init.lua` and one small opt-in flag on `explorer.open()`.

---

# Architecture Changes
- Modified: `lua/beast/libs/explorer/init.lua` — `M.open(dir, opts)` gains an optional `opts.restore` flag that skips the block re-rooting the tree to whatever file is currently active, so the caller's `dir` always wins exactly.
- Modified: `lua/beast/libs/session/init.lua` — `save()` captures explorer tree state and closes the explorer window before `mksession!`, then writes/clears a `<identity>.explorer.json` sidecar; `load()` reads that sidecar after sourcing the `.vim` file and reconstructs the panel.
- Modified: `tests/test-session.lua` — extended with the four PM-spec scenarios for explorer state, reusing the global-stub preamble from `scripts/bench-explorer.lua`.

## Implementation Phases

## Phase 1: Explorer opt-in exact-root restore — teach `explorer.open()` to skip its interactive re-rooting heuristic
1. **Add `opts` param to `M.open(dir, opts)`** (File: `lua/beast/libs/explorer/init.lua`)
   - Action: Accept an optional second `opts` table. When `opts.restore` is true, skip the existing block that inspects the currently active buffer (`vim.api.nvim_buf_get_name(0)`) and re-roots the tree to that file's directory when it lives outside `dir`. The tree's root stays exactly `dir` in that case; the "focus the active file if it's inside root" behavior is skipped too, since restore explicitly drives root + expanded dirs itself.
   - Why: The re-root-to-current-file heuristic exists for the interactive `<leader>e` toggle, where "whatever file is open" is a reasonable proxy for user intent. During session restore, the file that happens to be current (from `:mksession` sourcing) does not represent explorer intent — the saved root must win unconditionally, even if it doesn't contain the last-edited file.
   - Depends on: None
   - Risk: Low — additive optional param; default (`opts` nil/`opts.restore` falsy) preserves today's exact behavior for the `<leader>e` keymap and the directory-arg startup path in `lua/beast/init.lua`.

## Phase 2: Session save/restore captures and reconstructs explorer tree state
1. **Capture explorer snapshot and close the panel before `mksession!`** (File: `lua/beast/libs/session/init.lua`)
   - Action: In `save()`, before calling `mksession!`, check `require("beast.libs.explorer.state")` for a valid `view`/`tree`. If open, build `{ root = tree.root.path, open_dirs = <paths where node.dir and node.open, excluding root itself>, focus = (current win == view.win) and "explorer" or "main" }` by walking `tree.nodes`, then call `require("beast.libs.explorer").close()` (window-only close — same call the `<leader>e` toggle already makes) so the synthetic `beast-explorer` buffer never becomes part of `:mksession`'s window layout.
   - Why: Sidesteps `:mksession`'s undefined handling of a `buftype=nofile` window entirely, matching the simpler, more robust approach confirmed with the user: let `explorer.open()` fully rebuild the panel on load instead of trying to make `:mksession` understand it.
   - Depends on: None (useful once Phase 2 Step 3 exists to consume it)
   - Risk: Low — no-ops when the explorer was never opened; closing it immediately before an already-in-progress `VimLeavePre` quit has no user-visible effect.

2. **Write/clear the sidecar file** (File: `lua/beast/libs/session/init.lua`)
   - Action: After `mksession!` writes `<identity>.vim`, derive `<identity>.explorer.json` (swap the `.vim` suffix) and write the JSON-encoded snapshot via `vim.fn.writefile` when the explorer was open; when it was closed, `vim.fn.delete` any existing sidecar so a stale one from an earlier save can't leak explorer state into a later closed-explorer save.
   - Why: Reuses the exact per-project+branch identity already computed by `branch_path()`/`plain_path()` (Behavior Rule: no new session-identity scheme). Clearing the stale file is what makes Scenario 3 (closed at quit → stays closed) correct on a second save.
   - Depends on: Step 1
   - Risk: Low

3. **Restore explorer state in `load()`** (File: `lua/beast/libs/session/init.lua`)
   - Action: After sourcing the `.vim` file, compute the sidecar path from the same identity file that was actually sourced, `pcall`-read + `vim.json.decode` it (missing/malformed file is a normal "nothing to restore" outcome, not an error to surface). If `vim.fn.isdirectory(root) == 1`, call `require("beast.libs.explorer").open(root, { restore = true })`, then call `state.tree:open(dir)` for each `open_dirs` entry that still exists, then one `require("beast.libs.explorer.ui").render()`. If `focus == "main"`, switch back to `state.source_win` (already set by `open()` via `View.win.find_normal()`); if `focus == "explorer"`, no action is needed since `open()` leaves the newly created split focused.
   - Why: Implements PM spec Scenarios 1-4 directly: root + expanded dirs restored, focus mirrors quit-time focus in both directions, a missing root is a silent no-op that doesn't disturb the rest of the restored session.
   - Depends on: Phase 1, Steps 1-2
   - Risk: Medium — this step manipulates window focus immediately after a `:source`, which is the part most worth exercising manually in real Neovim, not just headlessly.

## Phase 3: Test coverage
1. **Extend `tests/test-session.lua`** (File: `tests/test-session.lua`)
   - Action: Add the global stubs from `scripts/bench-explorer.lua` (`_G.Theme`, `_G.Util`, `_G.View`, `_G.Toast`, devicons stub) needed to load `beast.libs.explorer` headlessly, then add four scenarios mirroring the PM spec: (a) explorer open, root + expanded folders + focus=explorer survive save → wipe buffers/state → load; (b) same with focus=main; (c) explorer closed at save time stays closed after load; (d) saved root deleted before load → explorer stays closed, no error, and the rest of the session (file buffers) still restores.
   - Why: These are exactly the PM spec's four scenarios, following this project's established headless-test convention for `session`.
   - Depends on: Phase 1, Phase 2
   - Risk: Low

2. **Run the explorer bench** (Verification step, no file changes)
   - Action: `nvim --clean --headless -l scripts/bench-explorer.lua`.
   - Why: `DEVELOPMENT.md` requires the relevant component bench to pass whenever a benched lib is touched — Phase 1 modifies `lua/beast/libs/explorer/init.lua`.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy
- Headless tests: `nvim --clean --headless -l tests/test-session.lua` (extended with the four explorer-state cases from Phase 3).
- Bench: `nvim --clean --headless -l scripts/bench-explorer.lua` — mandatory because Phase 1 touches a benched lib.
- Manual: Using `NVIM_APPNAME=BeastVim nvim`, open a real project, open the explorer (`<leader>e`), expand a couple of folders, `:qa`, relaunch, press `<leader>s` to load the last session — verify PM spec Scenario 1 (root + expanded folders restored, focus on the last file). Repeat quitting with the cursor inside the explorer panel to verify Scenario 2 (focus restored to the panel). Verify Scenario 3 by quitting with the explorer closed and confirming it stays closed on reload. Verify Scenario 4 by deleting/renaming the saved root directory before reloading and confirming a silent no-op with the rest of the session intact.

# Success Criteria
- [x] Quitting with the explorer open and reloading brings the explorer back open, rooted at the same folder.
- [x] Folders that were expanded before quitting are expanded again after reload.
- [x] Keyboard focus after reload matches exactly where it was at quit time (explorer panel vs. last edited file).
- [x] Quitting with the explorer closed leaves it closed after reload — no regression to current behavior.
- [x] A missing/deleted saved root folder fails silently — no error dialog, rest of the session restores normally.
- [x] `tests/test-session.lua` passes with the four new explorer-state scenarios.
- [x] `scripts/bench-explorer.lua` still passes its threshold after the Phase 1 change.

## Completed
2026-07-28. All 3 phases implemented, reviewed, and committed:
- `0e777b7` explorer: add opts.restore to open()
- `ef668f2` session: capture explorer tree state before mksession
- `d662897` session: restore explorer state on load() (+ explorer module trigger fix in beast/init.lua, discovered during implementation)
- `e9d7f38` test: cover explorer state save/restore in test-session.lua

tests/test-session.lua: 32/32 passing. scripts/bench-explorer.lua: passes threshold (520us < 2000us).
