---
name: markdown-lists
description: New standalone BeastVim/markdown language plugin that continues, numbers, nests and exits markdown lists via filetype-local Enter, Tab, Shift-Tab, o and O mappings
generated: 2026-11-05
---

> PM Spec: [docs/pm-specs/cross-markdown-lists.md](../pm-specs/cross-markdown-lists.md)

# Summary

Build a new standalone plugin repo at `/Users/loctvl842/Documents/Beast/Developments/neovim_plugins/markdown` (same shape as `json`, `python`, `cpp`), loaded by a new entry in `lua/beast/plugins/lang.lua` on `filetype = "markdown"`. `setup()` ensures the markdown parsers and installs buffer-local insert/normal mappings through the `Key` global. A pure line parser (`list.lua`) and a set of actions (`actions.lua`) do the work; the Enter and Tab mappings are plain Lua callbacks (not `expr`, see Implementation notes) that decide at press time and feed the resulting keystrokes to the front of the typeahead, so mid-item splitting, `autoindent` and undo behave like normal typing, and they fall back to the mapping that existed before (autopairs, blink) when the cursor is not in a list.

---

# Context

## Problem

BeastVim has language plugins for code languages only. Markdown buffers get highlighting via `render-markdown` and fence expansion via autopairs, but nothing understands list structure: Enter at the end of `- item` yields a bare line, numbers are never maintained, and Tab only inserts whitespace.

### Solution

After this change a `markdown` plugin repo exists next to the others. In a markdown buffer, Enter / Tab / Shift-Tab / `o` / `O` are buffer-local mappings backed by `markdown.actions`. They parse the current line, decide (list item, empty item, in fence, or not a list), and either return the keystrokes that produce the new item or hand off to the previous mapping. Renumbering of following ordered items runs inside the same undo block.

---

# Research

## Research

### Repo Search
- Searched for: `markdown`, `<CR>`, `<Tab>`, `<S-Tab>` across `lua/`; `lang.lua`, `new-lang` skill; sibling plugins under `neovim_plugins/` (`json`, `python`, `cpp`, `lua_ls`, `typescript`); `Key.safe_set`; blink and autopairs keymaps.
- Found:
  - Language plugins are standalone repos (`lua/<name>/init.lua`, `README.md`, `stylua.toml`, `.luarc.json`), registered in `lua/beast/plugins/lang.lua` with `lazy = { filetype = ... }` and `config = function() require("<name>").setup() end`. `cpp` additionally has a second module (`filetype.lua`), so multi-module plugins are an accepted shape.
  - `render-markdown` already loads on `filetype = "markdown"` (`lua/beast/plugins/init.lua`). `lua/beast/libs/treesitter/parsers.lua` already knows `markdown` and `markdown_inline`.
  - autopairs installs a **global** insert-mode expr `<CR>` (`lua/beast/libs/autopairs/keymap.lua`) that expands ``` fences when `markdown = true` (set in `lua/beast/init.lua`).
  - blink.cmp uses `preset = "enter"` (`lua/beast/libs/packer/builtin.lua`): Enter accepts when the menu is open, otherwise falls back; Tab only acts for snippet jumps and otherwise falls back to the previously existing mapping.
  - `Key.safe_set(mode, lhs, rhs, opts)` (`lua/beast/libs/key/core.lua`) accepts `buffer`, `expr`, `replace_keycodes`, `desc`, `group`. Globals `Key`, `Treesitter`, `Toast` exist (`lua/beast/init.lua`).
  - No existing list/markdown editing code. Tests live in `tests/test-*.lua` (headless `nvim --clean --headless -l`).
- Reuse opportunity: Yes - plugin scaffold pattern, `Treesitter.ensure_parser`, `Key.safe_set`, `Toast`.

### Built-in / Existing Lib Check
- Checked: `'autoindent'`, `'formatlistpat'`/`'comments'`/`'formatoptions' n,r,o` (Neovim's built-in list continuation), `<C-g>u`, `<Cmd>` mappings, `vim.fn.maparg(..., dict)`, `vim.fn.pumvisible()`, `vim.api.nvim_buf_set_lines`.
- Found: built-in `formatoptions` `r`/`o` continue only comment leaders and do not increment numbers, un-nest, renumber, or reset checkboxes. Nothing built-in covers the behavior. Buffer line editing and `maparg` fallback are available.
- Decision: **Build** (small, pure-Lua) on top of **Use**d Neovim APIs and **Reuse**d `Key`, `Treesitter` and scaffold pattern.

---

# Architecture Changes

New repo `neovim_plugins/markdown/`:
- `lua/markdown/init.lua` - `M.setup()`: global guard, `Treesitter.ensure_parser` for `markdown` and `markdown_inline`, FileType autocmd (+ already-open markdown buffers) that installs the buffer-local mappings.
- `lua/markdown/list.lua` - pure functions: `parse(line)` -> `{ quote, indent, marker, number, delim, checkbox, offset, empty }` or nil; `next_marker(item)`; `child_indent(item)`.
- `lua/markdown/actions.lua` - `enter()`, `tab()`, `shift_tab()`, `open_below()`, `open_above()`, `renumber(row)`, `in_fence(buf, row)`; each returns keystrokes for the mapping to feed, or does buffer edits via `<Cmd>` calls embedded in the returned keys.
- `tests/test-lists.lua` - headless tests (pure parsing, action output, buffer-level E2E through the real mappings).
- `README.md`, `stylua.toml`, `.luarc.json` - per the `new-lang` skill (`.luarc.json` globals: `vim`, `Key`, `Treesitter`, `Toast`).

BeastVim:
- `lua/beast/plugins/lang.lua` - modified: add the `markdown` entry (`lazy = { filetype = "markdown" }`).

## Implementation Phases

## Phase 1: Plugin + Enter continuation - bullets, ordered, tasks, empty exit, mid-item split
1. **Scaffold the repo** (File: `neovim_plugins/markdown/{README.md,stylua.toml,.luarc.json}`)
   - Action: copy `stylua.toml` from a sibling, write `.luarc.json` and README (not usable standalone, install snippet), `git init`, do not commit.
   - Why: matches every other language plugin.
   - Depends on: None
   - Risk: Low
2. **Line parser** (File: `lua/markdown/list.lua`)
   - Action: parse optional blockquote prefix, indent, marker (`-`, `*`, `+`, `N.`, `N)`), optional `[ ]`/`[x]`/`[X]`, content offset, and "empty item" flag. `next_marker` returns the marker for the next item (number + 1, checkbox reset to `[ ]`).
   - Why: single source of truth for every action; pure, so unit-testable without a buffer.
   - Depends on: None
   - Risk: Low
3. **Enter action + fence guard** (File: `lua/markdown/actions.lua`)
   - Action: `in_fence` scans lines above for an odd number of ``` / ~~~ fence openers. `enter()` returns: not a list / in fence / cursor at or before the marker end / pum visible -> fallback; empty item -> `<Cmd>` that clears the marker (nested handling arrives in Phase 2); otherwise `<C-g>u<CR>` followed by the next marker typed as literal text. The `<CR>` splits the line, so text after the cursor lands after the typed marker.
   - Why: returning keys keeps one undo step per Enter, honors `autoindent` for indent and works mid-item.
   - Depends on: Step 2
   - Risk: Medium - `autoindent` plus typed indent must not double the indent; verified by tests.
4. **Fallback to the previous mapping** (File: `lua/markdown/actions.lua`, `lua/markdown/init.lua`)
   - Action: at install time capture `vim.fn.maparg("<CR>", "i", false, true)` (autopairs' global mapping). Fallback calls its `callback` (returns pre-decoded keys) or returns `<CR>`.
   - Why: keeps autopairs fence expansion and bracket splitting; blink's `enter` preset already runs first and falls back to the buffer-local mapping when the menu is closed.
   - Depends on: Step 3
   - Risk: Medium - mapping order with blink (blink maps buffer-locally on InsertEnter and records the mapping existing at that time; ours is installed on FileType, earlier).
5. **Setup + mappings + wiring** (File: `lua/markdown/init.lua`, BeastVim `lua/beast/plugins/lang.lua`)
   - Action: global guard (sibling pattern), `ensure_parser` x2, FileType autocmd calling `Key.safe_set("i", "<CR>", function() nvim_feedkeys(actions.enter(), "ni", false) end, { buffer, noremap = true, desc, group = "Markdown" })`; apply to buffers already open with `ft=markdown`; add the lang.lua entry. During development `src` points at the local repo path, switched to `gh("BeastVim/markdown")` once pushed.
   - Why: lazy load on first markdown buffer, zero startup cost elsewhere.
   - Depends on: Steps 3, 4
   - Risk: Low
6. **Tests** (File: `tests/test-lists.lua`)
   - Action: pure parse cases (all markers, tasks, quotes, empty items, non-lists); buffer-level cases for scenarios 1, 3, 4, 5 (step 1), 6, 7.
   - Depends on: Steps 2-5
   - Risk: Low

## Phase 2: Numbering and nesting - renumber, Tab, Shift-Tab, empty-item un-nest
1. **Renumber** (File: `lua/markdown/actions.lua`)
   - Action: `renumber(row)` walks down from `row`, rewriting numbers of items with the same indent and same ordered kind (keeping the first number of the run), skipping deeper-indented lines and blank lines, stopping at a shallower item or non-list text at lower indent. Invoked via `<Cmd>lua require("markdown.actions").renumber(...)<CR>` appended to the Enter keys so it joins the undo block.
   - Why: scenario 2 (insert in the middle).
   - Depends on: Phase 1
   - Risk: Medium - must not touch unrelated lists or code fences.
2. **Tab / Shift-Tab** (File: `lua/markdown/actions.lua`, `lua/markdown/init.lua`)
   - Action: on a list item (not in fence, pum closed, no active snippet) Tab nests by the parent item's content offset (`child_indent`), restarts ordered numbering at 1, and renumbers the old level; Shift-Tab dedents to the parent's indent and continues numbering from the previous sibling. Otherwise fall back (captured previous mapping, else the plain key).
   - Why: scenario 8, with completion and snippet jumps keeping priority.
   - Depends on: Step 1
   - Risk: Medium
3. **Enter on a nested empty item** (File: `lua/markdown/actions.lua`)
   - Action: empty item with indent > 0 behaves as Shift-Tab; indent 0 clears the marker.
   - Why: scenario 5 step 2.
   - Depends on: Step 2
   - Risk: Low
4. **Tests** (File: `tests/test-lists.lua`)
   - Action: scenarios 2, 5 (step 2), 8; undo test (one `u` reverts Enter + renumber).
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 3: o / O and integration checks
1. **`o` / `O`** (File: `lua/markdown/actions.lua`, `lua/markdown/init.lua`)
   - Action: normal-mode buffer-local mappings. On a list item `o` returns `A` plus the insert-mode Enter flow; `O` inserts a new item above using the current item's marker (ordered: takes the current number, current and following are renumbered) and starts insert. Off a list item both return the plain key.
   - Why: scenario 9.
   - Depends on: Phase 2
   - Risk: Medium - `O` renumbering and cursor placement.
2. **Block quote prefix** (File: `lua/markdown/list.lua`)
   - Action: confirm `> - item` and `> 1. item` continue with the prefix (parser support lands in Phase 1; this step adds the E2E tests).
   - Depends on: Phase 1
   - Risk: Low
3. **Integration verification** (File: none)
   - Action: real-UI checks under `NVIM_APPNAME=BeastVim`: blink menu open + Enter accepts, closed + Enter continues; ``` fence expansion still works; Tab with an active snippet jumps; `render-markdown` unaffected; startup of a non-markdown file does not load the plugin.
   - Depends on: Phases 1-2
   - Risk: Medium

# Implementation notes

- **Decisions happen when a `<Cmd>` runs, not in the `expr` callback (deviation from the first draft).** Neovim evaluates `expr` mappings while *peeking* at queued keys during insert, before the characters typed ahead of the key are in the buffer. Reproduced: `feedkeys("A<CR>two<CR>three")` evaluated the second Enter on the stale line `"2. "`, took the empty-item path and wiped `"2. two"`. A plain non-expr callback fixes that but breaks behind blink.cmp: blink maps `<CR>`/`<Tab>`/`<S-Tab>` itself (buffer-local `expr`, overriding ours on InsertEnter) and runs a non-expr fallback with `vim.schedule`, i.e. after the keys that follow (reproduced in the real config: Tab did nothing, queued Enters collapsed into one line). The mappings are therefore `expr` mappings that return a **constant** `<Cmd>lua require('markdown.actions').press('<name>')<CR>`; `press` decides at consumption time and feeds the keys with `nvim_feedkeys(keys, "ni")`. The fallback to autopairs' `<CR>` is resolved at press time from `nvim_get_keymap("i")` (autopairs loads on InsertEnter, so it cannot be captured at setup). `tests/test-lists.lua` keeps both the queued-keys case and a blink-style wrapper as regression tests.
- **Tab on the first item of a list is a no-op** (nothing to nest under); Shift-Tab at top level is a no-op. Elsewhere the fallback is the plain key (stock Tab / Shift-Tab), not `<C-d>`.
- **Delimiters are separate lists.** `1)` after `1.` starts a new list and is neither renumbered nor counted as a sibling (CommonMark).
- **Deeper children are not moved** along with a nested or dedented item.
- **Local plugin source.** `lang.lua` currently points `src` at the local clone (`vim.pack` clones local git paths; the plugin repo needs one commit). Switch to `gh("BeastVim/markdown")` once pushed.

# Decisions to confirm

1. **Nested indent width.** PM spec examples show 4 spaces for a nested ordered item. CommonMark needs a child to be indented to the parent's content offset (2 for `- `, 3 for `1. `), and 'shiftwidth' here is 2. Recommendation: indent by the parent's content offset (so it always renders as nested). The PM spec examples (scenario 8, state 5) would then show 3 spaces for ordered children.
2. **Keymap registration.** Recommendation: `Key.safe_set` with `buffer = buf` from a FileType autocmd inside the plugin (it is an external repo and the keys are filetype-local). Alternative: `packer.lazy` `keys` with a filetype condition, if the packer supports it.
3. **Tests location.** Recommendation: inside the plugin repo (`tests/test-lists.lua`), so the plugin is self-contained. Alternative: `BeastVim/tests/` with the plugin path appended to the runtimepath.
4. **Fence detection.** Recommendation: plain line scan for ``` / ~~~ openers (no parser dependency, works while typing). Alternative: tree-sitter `fenced_code_block` node.

# Testing Strategy

- Headless tests: new `tests/test-lists.lua` in the plugin repo, run with `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-lists.lua`, with the plugin on the runtimepath and mocked `Key` / `Treesitter` globals for the pure parts; buffer-level cases drive the real mappings with `nvim_feedkeys`.
- Bench: none. Not a hot path (one line parse per keypress in markdown buffers only); still run the component benches loop from DEVELOPMENT.md once to confirm nothing regressed (`for f in scripts/bench-*.lua ...`) and `./scripts/bench-startup.sh` to confirm startup is unchanged.
- Manual: PM spec scenarios 1-9, in a real markdown file with `NVIM_APPNAME=BeastVim nvim`, plus the integration checks in Phase 3 step 3.

# Success Criteria

- [x] Enter at the end of `-`, `*`, `+` items starts a new item with the same marker and indent
- [x] Enter on `1.` / `1)` items gives the next number, and following items are renumbered
- [x] Enter on a task item gives an unchecked box
- [x] Enter on an empty item exits the list (or un-nests one level)
- [x] Enter mid-item splits the text and moves the rest to the new item
- [x] Tab / Shift-Tab nest and un-nest with correct numbering
- [x] `o` / `O` continue the list
- [x] No change in code blocks, plain paragraphs, or non-markdown files
- [x] Completion menu and autopairs keep working with Enter
- [x] Opening a markdown file loads the plugin lazily with no startup cost elsewhere
- [x] One `u` reverts a whole Enter (new line, marker and renumbering)
- [x] `stylua --check` passes and `tests/test-lists.lua` passes headless

## Completed

2026-11-05 - Phases 1-3 done: Enter continuation, renumbering with Tab / Shift-Tab, `o` / `O`, block quote prefix, integration with blink.cmp and autopairs.

All commits are in the new plugin repo `neovim_plugins/markdown` (BeastVim itself has no commits yet: the `lang.lua` entry and the `nvim-pack-lock.json` change are left uncommitted because `src` points at the local clone until the plugin is pushed):

- `e50f44d` feat: continue markdown lists on Enter
- `2921b63` fix: guard checkbox cursor, keep hard-break spaces, harden <CR> fallback (Phase 1 review warnings)
- `0b57dd3` feat: renumber ordered lists and nest/un-nest items with Tab and Shift-Tab
- `546b060` fix: run mappings as expr-constant <Cmd> so they work behind blink.cmp; keep delimiters as separate lists (blink ran non-expr fallbacks via `vim.schedule`)
- `ecba6af` feat: continue lists with o and O
- `2493394` docs: describe all list mappings in the README
- `688499d` fix: open list items with the real o/O so . and undo stay correct (dot-repeat corrupted text, `O` took two undo steps)

Verification: `tests/test-lists.lua` 110 passed, 0 failed (includes a blink.cmp-style wrapper and queued-keys regressions); `stylua --check lua tests` clean. Real BeastVim config (headless, blink.cmp mappings applied): lazy load on markdown only, Enter with the blink menu open accepts the item, Tab / Shift-Tab jump snippet stops without nesting, `o` / `O` and autopairs fence expansion work. `bench-startup.sh`: 46.6 ms wall-clock (hyperfine), nvim-internal ~31 ms; no pre-change baseline recorded. Codemap not regenerated (language plugins are not covered by it).
