---
name: finder-init
description: Fuzzy finder picker with prompt, results list, and preview
generated: 2026-05-14
---

> PM Spec: [docs/pm-specs/finder-init.md](../pm-specs/finder-init.md)

# Summary

Finder is the native in-editor picker for files, buffers, and text searches. It uses three floating windows, structured Lua items, and a coroutine-driven matcher pipeline so the user can search and preview without leaving Neovim.

---

# Context

## Problem

The editor needs a fast picker that can handle large result sets, show enough context to choose confidently, and stay inside the normal BeastVim window model. The implementation must avoid external picker binaries and fit the existing view and async patterns.

### Solution

Keep finder as a pure-Lua picker built around three `Beast.View` windows, a shared matcher pipeline, and native Neovim rendering primitives. Sources remain modular so files, buffers, and later search sources can all reuse the same UI shell.

---

# Research

### Repo Search
- Searched for: `picker`, `finder`, `fzf`, `fuzzy`, `snacks`
- Found: no existing picker implementation in BeastVim before this lib; `beast/libs/view.lua` provides the shared window wrapper pattern, `beast/util/init.lua` exposes scratch-buffer and window helpers, and the finder library now owns the picker shell, matcher, sources, and UI modules.
- Reuse opportunity: Yes — reuse `Beast.View`, `Util.create_scratch_buf`, `Util.wo`, and the existing highlight refresh pipeline.

### Built-in / Existing Lib Check
- Checked: `vim.api.nvim_open_win`, `vim.api.nvim_buf_set_lines`, `vim.api.nvim_buf_set_extmark`, `vim.fn.prompt_setprompt`, `vim.uv.new_check()`, `vim.uv.spawn`, and `vim.ui.select`
- Found: Neovim already supplies all the primitives needed for the picker shell, prompt buffer, preview rendering, and async source loading.
- Decision: **Build** — use native APIs instead of an external fuzzy-finder binary.

---

# Architecture Changes

- `lua/beast/libs/finder/init.lua` — public API and picker lifecycle.
- `lua/beast/libs/finder/config.lua` — sizing, debounce, and matcher defaults.
- `lua/beast/libs/finder/filter.lua` — query state shared by matcher and sources.
- `lua/beast/libs/finder/matcher.lua` — fuzzy scoring and result ordering.
- `lua/beast/libs/finder/format.lua` — display formatting for list rows.
- `lua/beast/libs/finder/picker.lua` — picker orchestration.
- `lua/beast/libs/finder/actions.lua` — default result actions.
- `lua/beast/libs/finder/ui/*` — input, list, preview, and backdrop windows.
- `lua/beast/libs/finder/source/*` — file, buffer, and later search sources.
- `lua/beast/libs/finder/highlights.lua` — picker highlight groups.

## Implementation Phases

## Phase 1: Core engine — filter and matcher
1. **Filter state** (File: `lua/beast/libs/finder/filter.lua`)
   - Action: Keep the user query and search context in a small shared state object.
   - Why: Every source and matcher pass needs the same query state.
   - Depends on: None
   - Risk: Low

2. **Fuzzy scoring** (File: `lua/beast/libs/finder/matcher.lua`)
   - Action: Rank items by fuzzy match quality and sort the matches.
   - Why: The picker is only useful if the best result rises to the top quickly.
   - Depends on: Step 1
   - Risk: Medium

3. **Config** (File: `lua/beast/libs/finder/config.lua`)
   - Action: Define the picker size and timing defaults.
   - Why: The UI needs stable dimensions and debounce behavior.
   - Depends on: None
   - Risk: Low

## Phase 2: Picker UI — prompt, list, and preview
1. **Prompt window** (File: `lua/beast/libs/finder/ui/input.lua`)
   - Action: Show the query prompt and update results as the user types.
   - Why: This is the main entry point for the picker.
   - Depends on: Phase 1
   - Risk: Low

2. **Results list** (File: `lua/beast/libs/finder/ui/list.lua`)
   - Action: Render the matching items and keep the cursor selection visible.
   - Why: The user needs a fast way to compare candidates.
   - Depends on: Phase 1
   - Risk: Low

3. **Preview window** (File: `lua/beast/libs/finder/ui/preview.lua`)
   - Action: Show the selected file or buffer before the user confirms.
   - Why: Preview reduces wrong-file opens.
   - Depends on: Phase 2 step 2
   - Risk: Medium

## Phase 3: Sources and integration
1. **Built-in sources** (File: `lua/beast/libs/finder/source/files.lua`, `lua/beast/libs/finder/source/buffers.lua`)
   - Action: Populate results from files and open buffers.
   - Why: These are the initial user-facing entry points.
   - Depends on: Phase 2
   - Risk: Medium

2. **Public entrypoint** (File: `lua/beast/libs/finder/init.lua`)
   - Action: Open the picker, mount keymaps, and connect the configured action.
   - Why: Users need one obvious API for the picker shell.
   - Depends on: Phase 3 step 1
   - Risk: Medium

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: none yet; source latency and render performance are currently verified by manual usage and the async pipeline design.
- Manual: open file and buffer pickers, type a query, move the cursor, toggle preview, and confirm a selection.

# Success Criteria

- [x] Users can open a picker for files, buffers, and search results.
- [x] Typing narrows results quickly.
- [x] The selected item can be previewed before opening.
- [x] Enter opens the chosen result in the expected place.
- [x] The picker works without needing a separate fuzzy-search binary.
- [ ] The prompt, list, and preview stay responsive on large result sets.
