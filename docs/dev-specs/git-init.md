---
name: git-init
description: Git signs, hunk actions, previews, and blame in the editor
generated: 2026-05-31
---

> PM Spec: [docs/pm-specs/git-init.md](../pm-specs/git-init.md)

# Summary

Git is the native in-editor git library for signs, hunk navigation, preview, blame, and change actions. The implementation keeps repository data in buffer-local state, uses native diffing and subprocess APIs, and exposes the same behavior through editor commands and keymaps.

---

# Context

## Problem

The editor needs git context close to the code so users can review changes, move through hunks, stage or reset work, and inspect blame without switching to another tool. The current implementation already provides that surface natively, so the spec should describe the shipped architecture rather than the older plan.

### Solution

Keep git as a native editor library with async repo resolution, per-buffer diff state, hunk expansion, preview windows, and blame helpers. The statuscolumn namespace, highlight groups, and keymaps should all read from the same git state.

---

# Research

### Repo Search
- Searched for: `gitsigns`, `git_signs`, `vim.system.*git`, `vim.text.diff`, `nvim_buf_set_extmark.*sign_text`, `BufWritePost.*debounce`
- Found: `lua/beast/libs/git/*` already contains the current git implementation, `lua/beast/libs/statuscolumn/signs.lua` routes the namespace, `lua/beast/icon.lua` already defines git icons, and the explorer git module shows the existing `vim.system` + debounce style this library also uses.
- Reuse opportunity: Yes — reuse the existing git modules, statuscolumn namespace routing, and Beast icon / highlight conventions.

### Built-in / Existing Lib Check
- Checked: `vim.system`, `vim.text.diff`, `vim.diff`, `nvim_buf_set_extmark`, `vim.api.nvim_win_text_height`, `vim.api.nvim_create_namespace`
- Found: Neovim provides everything needed for native git signs, hunk diffing, and preview rendering.
- Decision: **Reuse** — the library already follows the native path and does not need a plugin dependency.

---

# Architecture Changes

- `lua/beast/libs/git/init.lua` — public API, buffer lifecycle, keymaps, and action routing.
- `lua/beast/libs/git/config.lua` — git defaults and frozen config.
- `lua/beast/libs/git/repo.lua` — repo resolution and base-text fetching.
- `lua/beast/libs/git/diff.lua` — hunk computation.
- `lua/beast/libs/git/hunks.lua` — hunk-to-line-sign expansion and lookup helpers.
- `lua/beast/libs/git/signs.lua` — namespace-backed sign placement.
- `lua/beast/libs/git/nav.lua` — hunk navigation.
- `lua/beast/libs/git/preview.lua` — hunk preview float.
- `lua/beast/libs/git/blame.lua` / `current_line_blame.lua` — blame views and overlays.
- `lua/beast/libs/git/actions.lua` — stage / unstage / reset / repeatable action helpers.
- `lua/beast/libs/git/highlights.lua` — git highlight groups.
- `lua/beast/libs/git/health.lua` — health checks for repo, diff, and namespace status.

## Implementation Phases

## Phase 1: Signs and diff state — keep changes visible
1. **Repo resolution and diffing** (File: `lua/beast/libs/git/repo.lua`, `lua/beast/libs/git/diff.lua`)
   - Action: Resolve the repo for each buffer and compute hunks from the current buffer text.
   - Why: Git signs need source data before anything can render.
   - Depends on: None
   - Risk: Low

2. **Line signs** (File: `lua/beast/libs/git/hunks.lua`, `lua/beast/libs/git/signs.lua`)
   - Action: Expand hunks into per-line signs and place them in the git namespace.
   - Why: Users need visible git state in the gutter.
   - Depends on: Step 1
   - Risk: Medium

3. **Public wiring** (File: `lua/beast/libs/git/init.lua`, `lua/beast/libs/git/highlights.lua`, `lua/beast/libs/git/health.lua`)
   - Action: Expose setup, attach/detach, and health checks with the current highlights.
   - Why: The library needs a stable entry point and a verifiable surface.
   - Depends on: Step 2
   - Risk: Low

## Phase 2: Hunk actions and preview — let users act on changes
1. **Navigation and preview** (File: `lua/beast/libs/git/nav.lua`, `lua/beast/libs/git/preview.lua`)
   - Action: Move between hunks and open a preview for the selected change.
   - Why: Users need a fast way to inspect changes before acting.
   - Depends on: Phase 1
   - Risk: Medium

2. **Edit actions** (File: `lua/beast/libs/git/actions.lua`)
   - Action: Stage, unstage, reset, and repeat the last change action.
   - Why: The library should support common review workflows in-editor.
   - Depends on: Phase 1
   - Risk: Medium

## Phase 3: Blame tools — current-line and file-level history
1. **Blame views** (File: `lua/beast/libs/git/blame.lua`, `lua/beast/libs/git/current_line_blame.lua`)
   - Action: Show blame in a dedicated view and as current-line overlay text.
   - Why: Users need lightweight history context while editing.
   - Depends on: Phase 1
   - Risk: Medium

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: `scripts/bench-git.lua` for diff overhead and `compute_hunks` regression checks.
- Manual: open a modified file, move between hunks, preview changes, stage/unstage/reset a hunk, and toggle blame.

# Success Criteria

- [x] Changed lines show git signs in the editor.
- [x] Users can move between hunks and preview the current one.
- [x] Users can stage, unstage, or reset a hunk from the editor.
- [x] Blame information is available for the current line or file.
- [x] Files outside a git repository still open normally.
- [ ] Git state updates stay responsive on large files and repos.
