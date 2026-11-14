---
name: explorer-project-search
description: Explorer search mode as a separate state of the explorer: swap in a SearchTree (subclass of Tree), reuse everything else; matches come from a headless finder session
generated: 2026-11-14
---

> PM Spec: [docs/pm-specs/explorer-project-search.md](../pm-specs/explorer-project-search.md)

# Summary

Search mode is a **state of the explorer**, not a second explorer. While searching, `state.tree` points at a `SearchTree` (a subclass of the explorer's `Tree` that never scans the disk and carries the match data); the existing window, buffer, `ui`, `render.build`, sticky headers, git/diagnostic badges, keymaps and actions run unchanged on it. Leaving search puts the real tree back. Matches come from a new headless session in the finder (`finder/search.lua`); the explorer never touches finder UI.

Total new code: one finder file, four small explorer files (`search/init.lua`, `search/tree.lua`, `search/prompt.lua`, `search/decorate.lua`) and one-line hooks in existing files.

---

# Context

## Problem

The explorer only knows the folders the user opened, and `/` is Neovim's text search over drawn lines, so files in closed folders are invisible. The finder already answers "which files under this root match this text" (`finder/source/files.lua` + `finder/matcher.lua`) but only behind its picker UI.

### Solution

1. **Finder:** `finder/search.lua`, a headless session: stream the `files` source once, re-run `matcher.run` per query, no windows or picker state.
2. **Explorer modes:** the explorer gets a standard `state.mode` (`"normal"` by default, `"search"` here; Git, Diagnostics etc. could follow) and `state.mode_state` (data owned by the active mode, e.g. search's `real_tree`, query, session). A tiny `explorer/mode.lua` holds the registry (`{ search = "beast.libs.explorer.search" }`) and two calls: `leave()` (stops the active mode, no-op in normal), `decorate(lines, hls, badges, nodes)` (dispatches to the active mode's optional `decorate`). A mode module exposes `start`, `stop` and optionally `decorate`; core code never names search.
3. **Result tree:** `SearchTree` inherits `Tree` and overrides one method, `expand`, to prune missing children instead of scanning the disk; that single override stops walk, refresh, watchers and actions from re-adding non-matching files. It also owns the search data (`positions`, `count`, `capped`) and `SearchTree.from_matches(root, matches)`, so `decorate.lua` reads everything from `state.tree`. `tree.lua` itself is not edited.
4. **Drawing:** one call at the end of `render.build` hands the built rows to `search/decorate.lua`, which adds the query line + caret while typing, the count badge, the empty message and matched-letter highlights.
5. **Typing:** `search/prompt.lua` reads keys with `getcharstr` and repaints the top line per key. No cmdline, no insert mode, no second prompt.
6. **Keys:** `/`, `?` and `<Esc><Esc>` are ordinary explorer mappings, bound only when the finder is available.

### Open questions (PM spec silent; defaults below, please confirm)

| # | Question | Default |
|---|---|---|
| Q1 | `j`/`k`, `<CR>` on a folder. | Plain motions; folders are rows. `<CR>` on a folder toggles it, like the normal tree. |
| Q2 | Too many matches. | Best 1000 by score, shown in tree order; count reads `1000+ files`. |
| Q3 | `/` again while results show. | Typing resumes on the top line with the current query; `<Esc>` restores the previous results and stays in search mode. `<Esc>` in the very first prompt leaves search mode. |
| Q4 | `?` vs `/`. | Same behavior. |
| Q5 | Disk changes while results show. | Explorer actions work (delete/rename prune the row, created files appear via `tree:open`). Files created elsewhere show after the next query change. |
| Q6 | Matching per keystroke. | No debounce: each key aborts the previous matcher run and starts a new one; the tree is rebuilt only when results arrive. |

### Pitfalls found in the first attempt (build them in from the start)

- The explorer window shows trailing spaces as `-` (`listchars = trail:-`): the query line must not end in a space (the caret char is the line's last character while typing).
- While a key loop blocks, nothing repaints on its own: call `vim.cmd.redraw()` after each paint (verified: `vim.schedule` callbacks and the async matcher still run inside `getcharstr`).
- Leaving the explorer must reveal the file now open in the editor (not the row search stopped on) and must be scheduled (the window switch is still in progress inside `WinLeave`).
- `Tree:find`/`open` add nodes to whatever tree is current (inherited by `SearchTree`); that is fine for a result tree (a created or opened file shows up) but `state.tree` must be restored before revealing paths in the real one.
- Extmarks left past the end of a line that is replaced by a shorter one migrate to the next row; avoided here because all marks go through `render.write`, which clears and re-adds them.

---

# Research

### Repo Search
- Searched for: every reader of `state.tree` in `explorer/`; `Tree:walk`, `expand`, `flat`, `ensure_child`, `find`, `open`, `refresh`; `watch.lua` flush; the `tree:refresh` / `tree:open` calls in each action; `render.build` / `write`; `keymaps.mount`; `ui.focus_path`; `sticky`; `files.get`, `matcher.run`, `preflight.lua`, `Filter`; `Util.debounce`, `beast.libs.async`; tests and `scripts/bench-explorer.lua`.
- Found:
  - `Tree:expand` is the only place children come from disk. `walk` calls it only for `open` and not `expanded` children; `refresh` (create/delete/rename/trash/paste) only clears `expanded`, so the next `flat()` re-runs `expand`. Overriding it in a subclass covers every path, including the filesystem watchers (`watch` flush does `refresh` + `expand` for dirs in `state.tree.nodes`).
  - `ensure_child` stamps git status and diagnostics from the explorer's caches; `Tree:find`/`open` use it, so created or opened files join a result tree naturally.
  - `state.current_node`, `ui.flush`, `ui.focus_path`, `sticky`, git/diagnostic apply and all actions go through `state.tree`.
  - `set_root` and `navigate_up` replace `state.tree` (`Tree(new_root)`), so they must end search mode first.
  - `render.build(nodes)` returns `lines, hls, badges, active_line` (header = line 1, rows from line 2); `render.write` clears and re-adds extmarks, including right-aligned badges.
  - `files.get(filter, cb)` is headless and streams `Item{idx, text = rel, file = abs}` (`cb(nil)` = done, honors `visibility` flags); `finder/preflight.lua` already drives it without UI. `matcher.run(items, filter, cfg, on_done, prev_state, capacity)` is headless and async; partials have `state == nil`, the final result has it; `item.positions` are 1-based byte indices into `item.text`.
  - The first attempt (branch `backup/explorer-search-v1`) contains reviewed, tested versions of `finder/search.lua`, `files.supported()`, `search/prompt.lua` and the finder test; they are ported, not rewritten.
- Reuse opportunity: **Yes**: `Tree`, `ensure_child`, `render.build`/`write`, `ui`, sticky, actions, keymap mounting, `ui.focus_path`, `files.get`, `matcher.run`, finder `config.matcher`.

### Built-in / Existing Lib Check
- Checked: filtering the real tree instead of swapping a tree; `vim.fn.input` / native `/` cmdline for the prompt; a `getcharstr` loop; swapping the buffer shown in the explorer window.
- Found: filtering the real tree touches `flat`/`walk` (hot path) and leaves matches in the real tree; a cmdline prompt means a second prompt (rejected) and a native `/` would regex-search the buffer on Enter; swapping the window buffer forced guards in sticky/autocmds and broke cursor hiding.
- Decision: **Reuse** the explorer wholesale via a swapped `state.tree`; **Use** `getcharstr`; **Build** the finder session, a `SearchTree` subclass, a render hook and the lifecycle.

---

# Architecture Changes

New:
- `lua/beast/libs/finder/search.lua` - headless session: `available()`, `files({cwd, limit})` -> `{ query(pattern, cb), refresh(), close() }` (port from backup branch).
- `lua/beast/libs/explorer/search/init.lua` - lifecycle on `state.mode_state`: `start`, `prompt`, `set_query`, `exit`, `stop`, `is_active`; builds the result tree through `SearchTree.from_matches`.
- `lua/beast/libs/explorer/search/tree.lua` - `SearchTree`: subclass of `explorer/tree.lua` (same `__index`/`new` pattern, so `Tree.new` builds a `SearchTree`). Overrides `expand` (prune, never scan); adds `positions`, `count`, `capped`, and `from_matches(root, matches)` which `ensure_child`s each match with dirs `open` and `expanded`.
- `lua/beast/libs/explorer/search/prompt.lua` - `getcharstr` key loop (port).
- `lua/beast/libs/explorer/search/decorate.lua` - render hook.
- `lua/beast/libs/explorer/actions/search.lua`, `actions/search_exit.lua` - the actions behind `/` `?` and `<Esc><Esc>`, each with `available()`.
- `tests/test-finder-search.lua` (port), `tests/test-explorer-search.lua`.

Small edits (a few lines each):
- `lua/beast/libs/finder/source/files.lua` - `M.supported()`.
- `lua/beast/libs/explorer/mode.lua` (new) - mode registry: `leave`, `decorate`.
- `lua/beast/libs/explorer/state.lua` - `mode` (default `"normal"`) and `mode_state`, both reset by `reset()`.
- `lua/beast/libs/explorer/render.lua` - at the end of `build`: `mode.decorate(lines, hls, badges, nodes)` (returns at once in normal mode).
- `lua/beast/libs/explorer/config.lua` - default mappings `/`, `?`, `<Esc><Esc>`.
- `lua/beast/libs/explorer/keymaps.lua` - skip an action whose `available()` is false.
- `lua/beast/libs/explorer/actions/set_root.lua`, `navigate_up.lua` - one line: end search mode first.
- `lua/beast/libs/explorer/highlights.lua` - `SearchCount`, `SearchMatch`.
- `scripts/bench-explorer.lua` - one search case; `docs/CODEMAP/libraries.md` after implementation.

Not touched: `tree.lua`, `ui.lua`, `sticky.lua`, `autocmds.lua`, `watch.lua`, `git.lua`, other actions.

## Implementation Phases

## Phase 1: Finder headless session - one callable entry point, no UI

1. **Binary availability** (File: `lua/beast/libs/finder/source/files.lua`)
   - Action: add `M.supported()` (any of fd/rg/find executable).
   - Why: one list of binaries.
   - Depends on: None
   - Risk: Low

2. **Session facade** (File: `lua/beast/libs/finder/search.lua`)
   - Action: port from `backup/explorer-search-v1`: stream `files` once; `query` aborts the previous matcher run and ignores stale results (pattern check); `limit + 1` capacity so `capped` means "more than limit"; re-run when streaming ends; `refresh()` restarts the stream; `close()` ignores late callbacks via a generation counter.
   - Why: gives the explorer the finder's engine with no UI.
   - Depends on: Step 1
   - Risk: Medium (streaming and abort races; covered by tests)

3. **Test** (File: `tests/test-finder-search.lua`)
   - Action: port the 14 cases (nested matches, fuzzy/AND/inverse syntax, hidden excluded, limit/capped/exactly-limit, rapid queries, mid-stream query, close in flight, refresh).
   - Depends on: Step 2
   - Risk: Low

## Phase 2: Explorer plumbing - SearchTree, state field, render hook (inert until used)

1. **SearchTree** (File: `lua/beast/libs/explorer/search/tree.lua`)
   - Action: subclass `Tree`. `expand(node)`: for a directory, drop children whose path no longer exists (`uv.fs_lstat`), set `expanded = true`, `_touch()` if anything was dropped, never scan. `from_matches(root, matches)`: new tree, `ensure_child` per match path (dirs `open` and `expanded`), fill `positions[path]` (1-based byte indices into the file name), `count`, `capped`.
   - Why: the one override that keeps every inherited code path honest; the data decorate needs lives on the tree instead of a side table.
   - Depends on: None
   - Risk: Low (normal trees untouched)

2. **Modes** (Files: `lua/beast/libs/explorer/state.lua`, `explorer/mode.lua`)
   - Action: `state.mode` and `state.mode_state` (`reset()` clears both); `mode.lua` with the registry and `leave` / `decorate`. Search's `mode_state` is `Beast.Explorer.SearchState` (`real_tree, query, confirmed, prompting, session, loading, focus_pending, saved_cursor, augroup`).
   - Why: a standard seam so another mode later adds a module and a registry line, not new fields and hooks.
   - Depends on: None
   - Risk: Low

3. **Render hook** (Files: `lua/beast/libs/explorer/render.lua`, `search/decorate.lua`, `highlights.lua`)
   - Action: `decorate.apply(lines, hls, badges, nodes)`: while prompting, line 1 = `<pad>/ <query>▏` (header highlight widened) and a count badge (`N files`, `N+ files`, `1 file`, `…` while loading); non-empty query with no nodes and not loading appends `No files match "<query>"`; matched bytes from `state.tree.positions[path]`, count from `state.tree.count`/`capped` get `BeastExplorerSearchMatch`. Add the two highlight groups.
   - Depends on: Step 2
   - Risk: Low

4. **Test the plumbing** (File: `tests/test-explorer-search.lua`)
   - Action: a `SearchTree.from_matches` tree lists only its nodes and ignores extra files on disk; deleting a file then `refresh(parent)` removes its row; `mode.decorate` in search mode yields the query line, badge, empty row and highlights for a fake search `mode_state`.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 3: Search mode - lifecycle, prompt, keys, degradation

1. **Lifecycle** (File: `lua/beast/libs/explorer/search/init.lua`)
   - Action: `start()` sets `state.mode = "search"`, saves `state.tree` as `real_tree` and the cursor, creates the finder session for the root, sets an empty `SearchTree`, registers one augroup (`WinClosed` on the explorer window -> `stop`; `WinLeave` on the explorer buffer -> scheduled `exit({path = file open now})` when it is under the root and readable, else `exit({reveal = false})`, skipping floating targets; `User BeastVisibilityChanged` -> `session:refresh()`). `set_query(q)`: empty -> empty tree; else `session:query`, and on a non-stale result build a fresh `SearchTree.from_matches` (matches + ancestors), assign `state.tree`, `ui.flush()`, `sticky.refresh()`, cursor on the first file row for a new query or back on the same path otherwise, `redraw` while prompting. `stop()`: close session, delete augroup, `state.tree = real_tree`, `state.mode = "normal"`, `state.mode_state = nil`, `ui.render()`. `exit(opts)`: pick the path to reveal (given path, else row under cursor; `reveal = false` restores the saved cursor), `stop()`, then `ui.focus_path`.
   - Why: all search behavior in one module on top of the explorer.
   - Depends on: Phase 2
   - Risk: Medium

2. **Prompt** (Files: `search/prompt.lua`, `search/init.lua`)
   - Action: port the key loop (characters, `<BS>`, `<C-w>`, `<C-u>`, `<Enter>`, `<Esc>`/`<C-c>`); `prompt()` calls `start()` if needed, sets `prompting`, repaints the top line per key (`ui.flush()` + `redraw`) and starts a query, then: text -> keep results and focus the first file; cancel with confirmed results -> restore them; cancel otherwise -> `exit({reveal = false})`.
   - Why: Q3, Q6; one prompt only, on the top line.
   - Depends on: Step 1
   - Risk: Medium (key loop + repaint; validated in the first attempt)

3. **Keys and degradation** (Files: `actions/search.lua`, `actions/search_exit.lua`, `config.lua`, `keymaps.lua`, `actions/set_root.lua`, `actions/navigate_up.lua`)
   - Action: actions with `available()` (finder session available); defaults `/`, `?`, `<Esc><Esc>`; `keymaps.mount` skips unavailable actions (native `/` and `?` stay); `set_root` and `navigate_up` call `mode.leave()` first (no-op in normal mode).
   - Why: PM scenarios 6 and 7.
   - Depends on: Step 1
   - Risk: Low

4. **Lifecycle tests** (File: `tests/test-explorer-search.lua`)
   - Action: start is empty; query shows the nested matches in tree order; `state.tree` is a `SearchTree` while searching and the identical real tree afterwards with `open` flags unchanged; folder toggle hides/shows matches; delete removes a row; create adds one; `exit` reveals the selected file; leaving the window (with another file open there) ends search, puts the explorer cursor on that file and leaves `guicursor` unhidden; `stop` twice is safe; closing the explorer ends search; prompt key loop cases; keys mapped when available and unmapped in a degraded child run; `set_root` while searching ends search first.
   - Why: proves "all normal-mode features work on results".
   - Depends on: Steps 1-3
   - Risk: Medium

## Phase 4: Verify, bench, docs

1. **Bench** (File: `scripts/bench-explorer.lua`)
   - Action: add one case: build a 1000-match `SearchTree` + `render.build` + `decorate.apply`; warn above 16 ms (one frame); existing cases must not regress (the only change on their path is one `mode.decorate` call that returns at once).
   - Depends on: Phase 3
   - Risk: Medium

2. **Manual run** (tmux, full config)
   - Action: every PM scenario, plus: `<CR>` on folders, `a r d y p` on result rows, `.` and `<BS>`, `H`, sticky while scrolling long results, `<C-w>l` (cursor visible, explorer cursor on the open file), `<Esc><Esc>`, close and reopen while searching.
   - Depends on: Phase 3
   - Risk: Low

3. **Docs** (File: `docs/CODEMAP/libraries.md`)
   - Action: `/update-codemap`; document the state-swap design and `SearchTree`.
   - Depends on: Phase 3
   - Risk: Low

# Testing Strategy

- Headless: `tests/test-finder-search.lua`, `tests/test-explorer-search.lua` (new); re-run `test-explorer-clipboard.lua`, `test-visibility.lua`, `test-finder-preloaded-items.lua`.
- Bench: `scripts/bench-explorer.lua` before and after; per-keystroke case under 16 ms.
- Manual: the PM scenarios 1-7 and the list in Phase 4 step 2.

# Success Criteria

- [x] Searching `in.lua` with every folder closed shows `lua/beast/init.lua` and the other matches.
- [x] Search mode starts empty; the tree fills while typing on the top line; no prompt at the bottom.
- [x] Results appear as a tree with the right folders opened, non-matches hidden, matching letters highlighted, count shown while typing.
- [x] `<Enter>` ends typing, keeps results and puts the cursor on the first match; the top line is the folder title again.
- [x] Folders open and close, files open or split, and create, rename, delete, trash, copy, cut, paste, `H` work on result rows.
- [x] `.` and `<BS>` while searching end search mode first, then behave as usual.
- [x] Sticky headers work while scrolling results with no search-specific code in `sticky.lua`.
- [x] `<Esc><Esc>`, closing the explorer, or moving focus out of the explorer ends search mode; focus-out puts the explorer cursor on the file now open and the cursor stays visible.
- [x] The real tree object and its open/closed folders are untouched by searching.
- [x] A zero-result search shows the empty message and a 0 count.
- [x] With the finder or fd/rg/find missing, `/` and `?` behave exactly as before.
- [x] Existing explorer files change only by the listed small edits; explorer bench shows no regression.

---

# Completed

2026-11-14. Phase 1 finder session, Phase 2 SearchTree + mode seam + render hook, Phase 3 lifecycle, prompt, keys, degradation, Phase 4 bench, e2e and docs.

- `eb5ae11` docs(explorer): dev spec v2 for project search (SearchTree + explorer modes)
- `b4e30d3` feat(finder): headless file search session for other libs
- `54328d1` feat(explorer): SearchTree and mode seam for search results
- `bc0ebb3` feat(explorer): project search mode on / and ?

Deviations from the plan: `SearchTree:open` and `SearchTree:unwatch_subtree` are overridden too (a created or renamed file must join the results; the real tree's watchers must not be stopped), `explorer/init.lua` calls `mode.leave()` before re-rooting, and `mode.enter` was dropped (nothing needed it).

Verification: `test-finder-search` 14/14, `test-explorer-search` 46/46, `test-explorer-clipboard` 19/19, `test-visibility` 17/17, `test-finder-preloaded-items` 4/4. Bench: explorer mixed 533 us (unchanged); search, 1000 matches, build 0.9 ms + render 0.7 ms (budget 16 ms). tmux run on the real config: typing with live count, no-match message, `<Esc>` in the first prompt, `<Esc><Esc>`, `G` scrolling with sticky, opening a result ends search and reveals the file.

