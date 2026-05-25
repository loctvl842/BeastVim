# Dev Spec: Explorer Git Status Decorations

## Summary

Add git status decorations to the Beast Explorer, following VS Code's explorer
UI/UX model. Files and directories display colored names and right-aligned
status badges (M, U, A, D, R, C, !) based on `git status --porcelain=v1`.
Parent directories inherit the highest-priority child status via bottom-up
propagation. The implementation introduces a single new file (`git.lua`) that
runs `git status` asynchronously via `vim.system`, parses the output, stamps
`node.git_status` on tree nodes, propagates to directories, and signals the
renderer. The renderer (`render.lua`) and sticky overlay (`sticky.lua`) read
`node.git_status` to apply highlight overrides and virt_text badges.

The `git_status` field already exists on `Beast.Explorer.Node` (tree.lua:15)
and four highlight groups are already defined (highlights.lua:23-26). This
spec wires them up with real data and adds the missing groups.

## Requirements

- **R1**: On explorer open, refresh, `BufWritePost`, and `FocusGained`, run
  `git status --porcelain=v1 --ignored` asynchronously and apply results to
  tree nodes.
- **R2**: File names are highlighted with their git status color, overriding
  `BeastExplorerFile` / `BeastExplorerDir`.
- **R3**: Status badges (single letter: M, U, A, D, R, C, !) appear as
  right-aligned virtual text on file lines.
- **R4**: Directory names inherit the highest-priority child status color
  (propagation). Ignored status does NOT propagate.
- **R5**: Sticky ancestor headers reflect propagated git status colors.
- **R6**: Clipboard indicator and git badge coexist — badge is virt_text
  (right-aligned), clipboard suffix remains inline.
- **R7**: When explorer root is not inside a git repo, git decorations are
  silently disabled (no errors, no badges, default colors).
- **R8**: `git status` failures (permissions, bare repo, etc.) silently
  disable decorations.
- **R9**: Config options: `git.enable` (master toggle, default true),
  `git.badges` (show badge virt_text, default true).
- **R10**: New highlight groups: `GitConflict`, `GitRenamed`, `GitIgnored`.

### Out of scope

- **Staging UI** — no staged vs unstaged distinction in v1 (VS Code parity:
  both show "M"). Future config toggle.
- **Deleted file display** — deleted files are not shown in the tree (same as
  VS Code). Deletion status only propagates to parent dirs.
- **Submodule badges** — submodules are rare in personal configs; punt to v2.
- **Multi-repo support** — explorer root spanning multiple git repos is not
  supported in v1.
- **`.git/index` file watching** — the fs watcher already triggers refreshes
  on file changes; git status is re-run on those events. A dedicated index
  watcher is a future optimization.

## Research

### Repo Search

- Searched for: `git_status`, `git status`, `porcelain`, `icon_git`
- Found:
  - `tree.lua:15` — `git_status? string` field already on `Beast.Explorer.Node`
  - `tree.lua:30` — `git_status? string` in `Beast.Explorer.NodeOpts`
  - `tree.lua:250` — `unwatch_subtree()` already clears `node.git_status`
  - `config.lua:8` — `git = true` config key exists (boolean toggle)
  - `config.lua:20-28` — `icon_git` table maps porcelain codes to icon+hl pairs
  - `highlights.lua:23-26` — Four git highlight groups defined: `GitAdded`,
    `GitModified`, `GitDeleted`, `GitUntracked`
  - `render.lua` — No git rendering logic yet; `node.git_status` is unused
  - `statusline/components/git_branch.lua` — Has `resolve_git_dir()` that walks
    upward looking for `.git`; reusable pattern but statusline-specific caching
  - `util/root.lua:358-363` — `Util.root.git()` finds git root via `vim.fs.find`
- Reuse opportunity:
  - **Adopt** `Util.root.git()` for finding the git root directory
  - **Adopt** existing `node.git_status` field — no schema change needed
  - **Rework** `config.icon_git` → fold into new `git` config section
  - **Reuse** existing highlight groups, add 3 missing ones

### Package Search

- Searched: Neovim native API for async process execution
- Found: `vim.system(cmd, opts, on_exit)` — built-in async subprocess (Neovim 0.10+).
  Used by other libs in this project (e.g. `treesitter/install.lua`, `packer/operation.lua`).
- Decision: **Use native** `vim.system` — no plugins needed.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/explorer/git.lua` | **Create** | New module: async git status fetch, parse, apply to nodes, propagate to dirs |
| `lua/beast/libs/explorer/render.lua` | **Modify** | Read `node.git_status` → override name highlight + add virt_text badge |
| `lua/beast/libs/explorer/sticky.lua` | **Modify** | Read `node.git_status` → override dir name highlight in sticky entries |
| `lua/beast/libs/explorer/highlights.lua` | **Modify** | Add `GitConflict`, `GitRenamed`, `GitIgnored` groups |
| `lua/beast/libs/explorer/config.lua` | **Modify** | Restructure `git` from boolean to table with `enable`, `badges` keys; keep `icon_git` |
| `lua/beast/libs/explorer/init.lua` | **Modify** | Call `git.refresh()` after render; hook into lifecycle |
| `lua/beast/libs/explorer/autocmds.lua` | **Modify** | Add `BufWritePost`/`FocusGained` hooks to trigger `git.refresh()` |
| `lua/beast/libs/explorer/state.lua` | **Modify** | Add `git_root` and `git_job` fields for caching |

## Implementation Phases

### Phase 1: Git Status Engine — `git.lua` + state changes

**Goal**: Async git status fetch, parse, apply to tree nodes, propagate to dirs.

1. **Create `git.lua`** (File: `lua/beast/libs/explorer/git.lua`)
   - Action: New module with these functions:
     - `M.refresh(on_done)` — async entry point. Finds git root via `Util.root.git()`,
       runs `vim.system({"git", "-C", git_root, "status", "--porcelain=v1", "--ignored"}, {text=true}, on_exit)`.
       Parses output in `on_exit`, applies to nodes, propagates, calls `on_done()`.
     - `M.parse(output, git_root)` — parse porcelain output into `{[abs_path] = badge}` table.
       Maps XY codes to single-char badges (M, A, D, R, U, C, !) per the mockup's badge reference.
     - `M.apply(statuses)` — stamp `node.git_status` on matching tree nodes; clear stale statuses
       on nodes not in the new result set.
     - `M.propagate()` — walk the flat node list in reverse; each dir gets highest-priority
       child status (priority: C > M > R > D > A > U; ignored doesn't propagate).
     - `M.clear()` — clear all `git_status` from all nodes (used on close / root change).
   - Why: Core engine that all other phases depend on. Keeps git logic isolated from render.
   - Depends on: None
   - Risk: Low — `vim.system` is well-tested; porcelain format is stable.

2. **Add state fields** (File: `lua/beast/libs/explorer/state.lua`)
   - Action: Add `git_root = nil` (string?), `git_job = nil` (vim.SystemObj?) to state table
     and type annotations.
   - Why: Cache git root to avoid re-detecting per refresh; track running job to cancel on
     rapid re-triggers.
   - Depends on: None
   - Risk: Low

### Phase 2: Renderer Integration — badges + name colors

**Goal**: Tree lines show git-colored names and right-aligned status badges.

1. **Modify `render.build()`** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: After the existing name highlight block (lines 140-145), check `node.git_status`:
     - If set, override the file name highlight group with the corresponding `BeastExplorerGit*` group.
     - For directories, override `BeastExplorerDir` with the propagated status color.
     - Add virt_text extmark with the badge character, using `virt_text_pos = "right_align"`.
   - Why: R2 + R3 — file colors and badges.
   - Depends on: Phase 1 (needs `node.git_status` populated)
   - Risk: Low — additive change to existing render loop.

2. **Modify `render.write()`** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: Accept and apply virt_text specs alongside highlight specs. The `build()` function
     returns a third array of virt_text entries `{line, virt_text, hl_group}` that `write()`
     applies as extmarks with `virt_text` and `virt_text_pos = "right_align"`.
   - Why: Badges must be extmark virt_text, not inline text (so they don't shift columns).
   - Depends on: Step 1
   - Risk: Low

3. **Add missing highlight groups** (File: `lua/beast/libs/explorer/highlights.lua`)
   - Action: Add `GitConflict = { fg = p.accent1, bold = true }`,
     `GitRenamed = { fg = p.accent2 }`, `GitIgnored = { fg = p.dimmed3 }`.
   - Why: R10 — complete the highlight palette.
   - Depends on: None
   - Risk: Low

### Phase 3: Lifecycle Wiring — config, init, autocmds

**Goal**: Git refresh happens automatically at the right times.

1. **Restructure git config** (File: `lua/beast/libs/explorer/config.lua`)
   - Action: Change `git = true` to `git = { enable = true, badges = true }`. Keep `icon_git`
     as-is for badge character/hl customization. Add backward compat: if user passes
     `git = true/false`, normalize to `{ enable = bool, badges = bool }` in `setup()`.
   - Why: R9 — configurable. Backward compat protects existing user configs.
   - Depends on: None
   - Risk: Low

2. **Wire `git.refresh()` into `init.lua`** (File: `lua/beast/libs/explorer/init.lua`)
   - Action: In `M.open()`, after `ui.render()`, call `git.refresh(function() ui.flush() end)`
     so the first render shows the tree immediately (no flash), then git statuses paint on the
     async callback.
   - Why: R1 — git decorations appear on open.
   - Depends on: Phase 1 + Phase 2
   - Risk: Low

3. **Wire `git.refresh()` into autocmds** (File: `lua/beast/libs/explorer/autocmds.lua`)
   - Action: In the existing `BufWritePost` handler (line 253), after `watch._schedule_refresh()`,
     also schedule `git.refresh(function() ui.flush() end)` (debounced — reuse the git.lua
     internal debounce, ~200ms).
     In the existing `FocusGained` handler (line 274), do the same.
   - Why: R1 — git statuses update on save and focus-return.
   - Depends on: Phase 1
   - Risk: Low

### Phase 4: Sticky Header Git Colors

**Goal**: Sticky ancestor headers show propagated git status colors.

1. **Modify `sticky.lua` build()** (File: `lua/beast/libs/explorer/sticky.lua`)
   - Action: In the `build()` function (line 144), when rendering `entry.kind == "dir"`,
     check `entry.node.git_status`. If set, override the dir-name highlight from
     `BeastExplorerDir` to the corresponding `BeastExplorerGit*` group.
   - Why: R5 — sticky headers reflect propagated status.
   - Depends on: Phase 1 (propagation populates dir git_status)
   - Risk: Low — small additive change.

## Testing Strategy

- **Unit tests**: No test infrastructure exists yet for explorer. Manual verification
  for v1; test harness is a separate concern.
- **Bench**: Git status is async and off the render hot path. No bench needed for v1.
  If performance becomes a concern (large repos), add `scripts/bench-explorer-git.lua`.
- **Manual verification**:
  1. Open explorer in a git repo → modified files show yellow name + "M" badge
  2. Create a new file outside Neovim → `FocusGained` triggers refresh → "U" badge appears
  3. Save a file → `BufWritePost` triggers refresh → badge updates
  4. Expand a directory with mixed statuses → parent dir name is colored by highest-priority child
  5. Open explorer outside a git repo → no badges, no errors, default colors
  6. Scroll down so ancestors are sticky → sticky headers show git colors
  7. Set `git = { enable = false }` → no decorations at all
  8. Cut a file to clipboard that has git status → both badge (right) and "(cut)" suffix visible

## Risks & Mitigations

- **Risk**: `git status` is slow on large repos (10k+ files) →
  **Mitigation**: Async execution means UI never blocks. Show stale data while refresh
  is in progress. Internal debounce prevents rapid re-triggers.
- **Risk**: Race between fs watcher refresh and git refresh (tree nodes change mid-apply) →
  **Mitigation**: `git.apply()` uses `state.tree.nodes[path]` lookups; missing nodes
  are silently skipped. `git.refresh()` cancels any in-flight job before starting a new one.
- **Risk**: Config backward compat — users with `git = true` break on table access →
  **Mitigation**: `setup()` normalizes boolean to table before merging.

## Success Criteria

- [ ] Modified/untracked/added files show correct badge and colored name
- [ ] Parent directories show propagated status color
- [ ] Sticky headers show propagated git colors
- [ ] `git.refresh()` completes < 500ms on repos with 1k files (async, non-blocking)
- [ ] Explorer opens without error when not inside a git repo
- [ ] `git = { enable = false }` disables all decorations
- [ ] Clipboard + git badge coexist without layout issues

## Completed

Implementation completed on 2025-07-26.

### Commits
- `2f6f4d6` — Phase 1: git.lua engine + state fields
- `6f5cfa3` — Phase 2: render badges, name coloring, highlight groups
- `6432d15` — Phase 3: config restructure (boolean → table)
- `73fb2ae` — Phase 3: wiring into init.lua + autocmds
- `5909622` — Phase 4: sticky header git colors

### Files Changed
- **Created**: `lua/beast/libs/explorer/git.lua` (async git status engine)
- **Modified**: `lua/beast/libs/explorer/state.lua` (git_root, git_job, git_timer fields)
- **Modified**: `lua/beast/libs/explorer/highlights.lua` (GitConflict, GitRenamed, GitIgnored)
- **Modified**: `lua/beast/libs/explorer/render.lua` (git name colors, virt_text badges)
- **Modified**: `lua/beast/libs/explorer/ui.lua` (flush passes badges to write)
- **Modified**: `lua/beast/libs/explorer/config.lua` (git table config + normalizer)
- **Modified**: `lua/beast/libs/explorer/init.lua` (git.refresh wiring)
- **Modified**: `lua/beast/libs/explorer/autocmds.lua` (git.schedule_refresh on save/focus)
- **Modified**: `lua/beast/libs/explorer/sticky.lua` (git colors in pinned dirs)
