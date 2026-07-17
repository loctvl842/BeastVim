---
name: explorer-git-status
description: Explorer shows git status colors and badges
generated: 2026-05-25
---

> PM Spec: [docs/pm-specs/explorer-git-status.md](../pm-specs/explorer-git-status.md)

# Summary

Explorer git status decorations color files and folders by git state and show small badges for file-level changes. The implementation stamps git data onto tree nodes, propagates directory status, and lets the renderer and sticky headers read that state directly.

---

# Context

## Problem

The explorer needs visible git cues so users can tell what changed without opening every file. The current implementation already has the data model and renderer hooks, but the spec should reflect the shipped behavior rather than the original planning notes.

### Solution

Keep git status as a native explorer subsystem: fetch porcelain data asynchronously, stamp tree nodes, propagate directory status, and render the resulting colors and badges in the tree and sticky headers.

---

# Research

### Repo Search
- Searched for: `git_status`, `git status`, `porcelain`, `icon_git`
- Found: `lua/beast/libs/explorer/git.lua` already parses git status and stamps `node.git_status`, `render.lua` reads the field for badges and colors, `sticky.lua` mirrors the same state, and `highlights.lua` already includes the git groups.
- Reuse opportunity: Yes — reuse the existing git module, render hooks, and highlight groups.

### Built-in / Existing Lib Check
- Checked: `vim.system`, `vim.fn.fnamemodify`, `vim.fs.find`, and the current explorer lifecycle helpers
- Found: Neovim provides the async subprocess API needed for git status.
- Decision: **Reuse** — the explorer already has the native git-status implementation in place.

---

# Architecture Changes

- `lua/beast/libs/explorer/git.lua` — async git status fetch, parse, and propagation.
- `lua/beast/libs/explorer/render.lua` — file and folder highlighting plus status badges.
- `lua/beast/libs/explorer/sticky.lua` — sticky header git colors.
- `lua/beast/libs/explorer/highlights.lua` — git highlight groups.
- `lua/beast/libs/explorer/config.lua` — git toggle and badge settings.
- `lua/beast/libs/explorer/init.lua` — trigger refresh on open and close.
- `lua/beast/libs/explorer/autocmds.lua` — refresh on save and focus changes.
- `lua/beast/libs/explorer/state.lua` — cache git root and job state.

## Implementation Phases

## Phase 1: Git data — fetch and stamp tree nodes
1. **Git status engine** (File: `lua/beast/libs/explorer/git.lua`)
   - Action: Fetch porcelain output, parse it, and stamp node status fields.
   - Why: The tree needs source data before it can render any git cues.
   - Depends on: None
   - Risk: Low

2. **Tree state** (File: `lua/beast/libs/explorer/state.lua`)
   - Action: Keep the minimal cache needed for git refreshes and job tracking.
   - Why: Refreshing should stay cheap and predictable.
   - Depends on: None
   - Risk: Low

## Phase 2: Visible cues — colors and badges
1. **Tree rendering** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: Show git-colored names and per-file status badges.
   - Why: Users need the status cues directly in the explorer.
   - Depends on: Phase 1
   - Risk: Medium

2. **Sticky headers and highlights** (File: `lua/beast/libs/explorer/sticky.lua`, `lua/beast/libs/explorer/highlights.lua`)
   - Action: Match sticky folder headers to the tree's git colors and keep the git palette defined.
   - Why: Sticky folder names should not lose the same context as the tree entries.
   - Depends on: Phase 1
   - Risk: Low

## Phase 3: Refresh behavior — keep the tree current
1. **Lifecycle hooks** (File: `lua/beast/libs/explorer/init.lua`, `lua/beast/libs/explorer/autocmds.lua`)
   - Action: Refresh git data on explorer open, save, and focus return.
   - Why: The tree should keep up with changes made outside the explorer.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: none; this is asynchronous and off the render hot path.
- Manual: open the explorer in a git repo, change files, save buffers, and confirm the badges and folder colors stay in sync.

# Success Criteria

- [x] Modified, added, deleted, renamed, copied, conflicted, untracked, and ignored files are visually distinguishable.
- [x] Parent folders show the strongest status from their children.
- [x] Sticky folder headers use the same git cues as the tree.
- [x] The explorer still works normally when no git repository is present.
- [ ] Git refresh stays async and does not block explorer rendering.
