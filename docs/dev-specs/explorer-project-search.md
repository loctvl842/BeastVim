---
name: explorer-project-search
description: Self-contained explorer search mode (own state, own result tree, own buffer) fed by a headless finder file-search session
generated: 2026-11-14
---

> PM Spec: [docs/pm-specs/explorer-project-search.md](../pm-specs/explorer-project-search.md)

# Summary

Search mode lives in its own folder, `lua/beast/libs/explorer/search/`, with its own state, its own small result tree and its own buffer. Pressing `/` or `?` in the explorer swaps that buffer into the explorer window; it starts empty and re-renders on every keystroke of a bottom prompt. The existing explorer tree, state and render code are not changed (a handful of one-line guards and exports aside). Matching comes from a new headless entry point in the finder, `finder/search.lua`, so the explorer never touches finder UI. If that entry point is unavailable, the `/` and `?` keys are simply not bound and everything stays as today.

---

# Context

## Problem

The explorer only knows the folders the user has opened, and `/` is Neovim's text search over the drawn lines, so files in closed folders are invisible. The finder already answers "which files under this root match this text" (`finder/source/files.lua` + `finder/matcher.lua`) but only through its own picker UI, so the explorer cannot call it.

### Solution

- `finder/search.lua`: a headless session that streams the `files` source once, keeps the items, and re-runs `matcher.run` per query.
- `explorer/search/`: an independent mini-explorer. It builds its own node tree from the matches (no filesystem scan, no watchers, no `open` flags), draws it with the existing row renderer, and shows it in the explorer window by swapping the window's buffer. Leaving search swaps the real explorer buffer back, so the real tree is, by construction, exactly as it was.
- The real explorer never learns about search. It only gets two generic guards ("the explorer window is currently showing another buffer, so skip tree-position work") and two exports so search can reuse open/split.

### Open questions (PM spec is silent or in tension; defaults below, please confirm)

| # | Question | Default in this plan |
|---|---|---|
| Q1 | PM says `j`/`k` skip folders; your review note said "navigate normally". | Plain `j`/`k`. Folder rows are selectable; `<CR>` on a folder row does nothing (folders are always open). |
| Q2 | Too many matches. | Show the best 1000 by score, in tree order; count reads `1000+ files`. |
| Q3 | Empty query. | **Changed per your note:** search mode starts empty (header `/`, no rows) and fills as you type. Backspacing everything empties it again. |
| Q4 | Which prompt. | `vim.fn.input()` with prompt `/` (looks like the bottom search prompt, no side effects). A real `/` cmdline would, on `<Enter>`, also regex-search the buffer (cursor jump, search register, E486 on fuzzy-only queries). |
| Q5 | `/` pressed again with results showing. | Prompt pre-filled with the current query; `<Esc>` restores the previous results and stays in search mode. `<Esc>` in the very first prompt leaves search mode. |
| Q6 | `?` vs `/`. | Same behavior; prompt and header always show `/`. |
| Q7 | **Actions on result rows** (PM rule says normal explorer actions work; with a separate tree they do not come for free). | Result rows support: open (`<CR>`), split (`s`), system open (`o`), toggle hidden (`H`), `/`, `<Esc><Esc>`, and plain cursor motions. Create, rename, delete, trash, copy, cut, paste, set root, navigate up, git/diagnostic jumps are not available in search mode; press `<Esc><Esc>` (cursor lands on the file you were on, folders revealed) and use them there. |
| Q8 | Files change on disk while results are showing. | Results are a snapshot, refreshed when the query changes or hidden/gitignored is toggled. |

### PM spec lines to update once Q3 and Q7 are confirmed

- Scenario 1 step 1 / STATE 2: "tree is replaced by only the matching files" -> "starts empty, fills while typing".
- Behavior Rules: replace "Normal explorer actions ... work on result rows" and "Creating a file ... ends search mode first" with the Q7 list.
- Scenario 7 (`.` re-roots): not reachable from search mode; becomes "press `<Esc><Esc>`, then `.`".

---

# Research

### Repo Search
- Searched for: `search`, `"/"`, `"?"`, `<Esc>` in `lua/beast/libs/explorer/`; `:flat(`, `current_node`, `ui.flush`, `ui.render`, `sticky.refresh` call sites; `render.build`/`build_prefixes` field needs; `files.get`, `matcher.run`, `preflight.lua`, `Filter`; `View.buf.new`, `Instance:is_valid`; `winfixbuf` uses; `CmdlineChanged`/`vim.fn.input` in `lua/`; `git.resolve`, `diagnostics.resolve`; `Util.debounce`; `beast.libs.async`.
- Found:
  - Explorer has no search code; `/` is Neovim's built-in. Keys come from `config.mappings` (buffer-local, `nowait`), mounted once in `keymaps.mount`.
  - `files.get(filter, cb)` is fully headless: spawns `fd`/`rg`/`find`, streams `Item{idx,text=rel,file=abs,cwd}`, `cb(nil)` = done, honors `visibility.hidden/gitignored` at call time. `finder/preflight.lua` already drives it with no UI.
  - `matcher.run(items, filter, cfg, on_done, prev_state, capacity)` is headless and async; intermediate callbacks pass `match_state == nil`, the final one passes it; sets `item.positions` (1-based byte indices into `item.text`); default capacity 1000; supports the finder fuzzy syntax (`space` = AND, `!x`, `'x`, `^x`, `x$`).
  - `render.build(nodes)` only needs `path, name, dir, open, depth, last, parent, hidden, git_status, diagnostic` per node, plus `state.tree.root.path` for the header and `state.clipboard`/`state.active_path`. It returns `lines, hls, badges, active_line`. Its writer, `render.write`, is hard-wired to the explorer view, so search needs its own small writer.
  - `git.resolve(path, parent)` and `diagnostics.resolve(path)` read the explorer's cached status maps and can stamp any node.
  - `ui.create` sets `winfixbuf = true` on the explorer window; swapping the buffer needs it off temporarily. `View.buf.new(ft)` creates a scratch buffer with `bufhidden = wipe`; the explorer buffer uses `bufhidden = hide`, so it survives being swapped out.
  - Explorer code that would misbehave if the window shows another buffer: `sticky.refresh` (reads cursor row against the real flat list) and the `BufEnter` handler (`ui.focus_path` opens real folders and moves the window cursor).
  - `open.lua` and `split_open.lua` keep their window logic in local `on_select`/`on_split`.
  - Pre-existing, not touched: `files.lua` declares `SUPPORTED` as an accidental global and reports a missing binary via `vim.notify`.
- Reuse opportunity: **Yes** - `files.get`, `matcher.run`, finder `config.matcher`, `Filter`, explorer `render.build` (rows), `git.resolve`/`diagnostics.resolve`, `open`/`split` window logic, `ui.focus_path` (on exit), `Util.debounce`, `Toast`.

### Built-in / Existing Lib Check
- Checked: `vim.fn.input` dict form (`prompt`, `default`, `cancelreturn`), `CmdlineChanged` while `input()` runs (`getcmdtype() == "@"`), `:redraw` inside it, `nvim_win_set_buf` + `winfixbuf`, extmarks with `virt_text_pos = "right_align"`.
- Found: `cancelreturn` separates `<Esc>` from an empty `<Enter>`; `CmdlineChanged` fires per keystroke; the explorer's existing `CmdlineEnter/Leave` autocmds already manage the hidden-cursor hack around any cmdline. Live repaint during the prompt needs `vim.cmd.redraw()`; this is the one mechanism to prove first (Phase 1, step 1).
- Decision: **Reuse** finder files source + matcher through a thin headless facade, and `render.build` for rows; **Use** `vim.fn.input`; **Build** the self-contained `explorer/search/` folder.

---

# Architecture Changes

New files:
- `lua/beast/libs/finder/search.lua` - headless session: `available()`, `files({cwd, limit})` -> `{ query(pattern, cb), refresh(), close() }`.
- `lua/beast/libs/explorer/search/init.lua` - public API and lifecycle: `available()`, `start()`, `exit()`, `stop()`, `is_active()`.
- `lua/beast/libs/explorer/search/state.lua` - its own state: `session, query, tree, buf, win, saved_cursor, positions, count, capped, loading, augroup`.
- `lua/beast/libs/explorer/search/tree.lua` - matches -> own nodes (`path, name, dir, open, depth, last, parent, hidden, git_status, diagnostic, children`) and a sorted flat list (dirs first, case-insensitive alpha, same as the real tree).
- `lua/beast/libs/explorer/search/view.lua` - create the search buffer, swap it into / out of the explorer window (`winfixbuf` toggled), buffer-local options.
- `lua/beast/libs/explorer/search/render.lua` - calls `explorer.render.build(nodes)`, then rewrites line 1 as `/ query`, adds the count badge, the empty-result row and the match-letter highlights; writes lines and extmarks to the search buffer.
- `lua/beast/libs/explorer/search/prompt.lua` - `vim.fn.input` prompt with debounced live `CmdlineChanged` updates.
- `lua/beast/libs/explorer/search/keymaps.lua` - buffer-local keys of the search buffer (Q7 list).
- `lua/beast/libs/explorer/actions/search.lua` - thin action behind `/` and `?` with `available()`.
- `tests/test-finder-search.lua`, `tests/test-explorer-search.lua`.

Small edits to existing files (all one-liners or tiny blocks):
- `lua/beast/libs/finder/source/files.lua` - add `M.supported()` (any of fd/rg/find executable).
- `lua/beast/libs/explorer/config.lua` - default mappings `["/"] = "search"`, `["?"] = "search"`.
- `lua/beast/libs/explorer/keymaps.lua` - skip an action when `action.available` exists and returns false (graceful degradation).
- `lua/beast/libs/explorer/sticky.lua` - `refresh()` returns early when the explorer window is not showing the explorer buffer.
- `lua/beast/libs/explorer/autocmds.lua` - same guard at the top of the `BufEnter` handler (`ui.flush()` only).
- `lua/beast/libs/explorer/actions/open.lua`, `split_open.lua` - export `M.select = on_select` / `M.split = on_split`.
- `lua/beast/libs/explorer/highlights.lua` - `SearchCount`, `SearchMatch` groups.
- `docs/CODEMAP/libraries.md` - regenerated via `/update-codemap`.

Not touched: `tree.lua`, `state.lua`, `ui.lua`, `render.lua`, `init.lua`, `watch.lua`, and all mutating actions.

## Implementation Phases

## Phase 1: Finder headless search session - one callable entry point, no UI

1. **Prove the prompt mechanism (throwaway spike)** (File: scratchpad script, not committed)
   - Action: in a real `NVIM_APPNAME=BeastVim nvim`, call `vim.fn.input({prompt="/", cancelreturn="\27"})` with a `CmdlineChanged` autocmd that rewrites a buffer shown in the explorer window and calls `vim.cmd.redraw()`. Confirm live repaint while typing, `<Esc>` returns the sentinel, `<Enter>` returns the text, the prompt does not flicker, and `nvim_win_set_buf` on a `winfixbuf` window works after toggling the option.
   - Why: the UX depends on it and it cannot be verified headlessly. If it fails, fall back to a one-line floating input at the bottom of the explorer; only `prompt.lua` changes.
   - Depends on: None
   - Risk: Medium

2. **Expose binary availability** (File: `lua/beast/libs/finder/source/files.lua`)
   - Action: add `function M.supported()` returning true when any `SUPPORTED[i].cmd` is executable.
   - Why: one source of truth for the fd/rg/find list.
   - Depends on: None
   - Risk: Low

3. **Add the session facade** (File: `lua/beast/libs/finder/search.lua`)
   - Action: `M.available()` (pcall-require matcher/source, then `files.supported()`); `M.files({cwd, limit?})` returns a session that starts `files.get(Filter({cwd}), cb)` once and appends items; `query(pattern, cb)` aborts the previous matcher task and runs `matcher.run` with `config.matcher`, `limit` as capacity (default 1000) and the previous `MatchState`, calling `cb(matched, {capped, loading})` only for final results; re-runs the last pattern when the stream completes; `refresh()` drops items and restarts the stream; `close()` aborts and ignores late callbacks via a generation counter (same trick as `preflight.lua`, since the `files` source has no cancel).
   - Why: gives the explorer the finder's engine with no UI coupling.
   - Depends on: Step 2
   - Risk: Medium (streaming and abort races; covered by the test)

4. **Test the session** (File: `tests/test-finder-search.lua`)
   - Action: headless over a temp fixture tree: matches nested files in closed dirs; fuzzy, AND and inverse syntax; `limit` caps and sets `capped`; a query issued mid-stream is re-run on completion; `close()` stops callbacks; `refresh()` picks up a new file.
   - Why: locks the contract Phase 2 builds on.
   - Depends on: Step 3
   - Risk: Low

## Phase 2: Search tree and view - self-contained, driven programmatically

1. **Own state and tree** (Files: `explorer/search/state.lua`, `explorer/search/tree.lua`)
   - Action: `tree.build(root_path, items)` makes nodes for every match and its ancestors (no fs calls; leaf = file, parents = dirs), stamps `git_status` via `git.resolve` and `diagnostic` via `diagnostics.resolve`, computes `hidden`, `depth` (top level = 0), `last`, and returns `{ nodes, flat }` sorted dirs first then case-insensitive alpha. Also builds `positions[path] = { byte offsets within the node name }` by mapping each `item.positions` byte onto its path segment.
   - Why: replaces any need to mutate the real tree.
   - Depends on: None
   - Risk: Low

2. **View swap** (File: `explorer/search/view.lua`)
   - Action: `attach()` saves the explorer cursor, closes the sticky float (`sticky.close()`), creates the search buffer (`View.buf.new("beast-explorer")`, so tabline/session/other filetype checks treat it as the explorer), sets `winfixbuf` false, `nvim_win_set_buf`, `winfixbuf` true. `detach()` does the reverse and wipes the search buffer. Own `WinClosed` autocmd on the explorer window calls `stop()` so closing the explorer ends search mode.
   - Why: all geometry, cursor hiding and window options are inherited for free.
   - Depends on: Phase 1 Step 1
   - Risk: Medium

3. **Render** (File: `explorer/search/render.lua`)
   - Action: `render()` calls `explorer.render.build(flat)`, replaces line 1 with `<pad>/ <query>` (`BeastExplorerTitle`), adds the badge `N files` / `N+ files` / `1 file` (`BeastExplorerSearchCount`, with `…` while loading), adds the row `No files match "<query>"` when the query is non-empty and there are no results, adds one `BeastExplorerSearchMatch` extmark per matched byte, and writes lines + extmarks to the search buffer in its own namespace. Cursor goes to the first file row.
   - Why: reuses the existing row look (icons, git colors, badges, indent guides) without copying it.
   - Depends on: Step 1
   - Risk: Medium

4. **Guards in the explorer** (Files: `explorer/sticky.lua`, `explorer/autocmds.lua`, `explorer/highlights.lua`)
   - Action: `sticky.refresh` and the `BufEnter` handler return early (the latter after `ui.flush()`) when `nvim_win_get_buf(state.view.win) ~= state.view.buf`; add the two highlight groups.
   - Why: without them, opening a result would open real folders and move the search window's cursor, and the sticky float would compute pins from the wrong buffer.
   - Depends on: None
   - Risk: Low

5. **Lifecycle and update loop** (File: `explorer/search/init.lua`)
   - Action: `start()` (attach, empty render, create the session lazily, prompt), `set_query(q)` (empty -> clear results; else `session:query`, on result `tree.build`, store count/capped/positions, render), `stop()` (close session, delete augroup, detach if attached), `exit()` (remember the selected path, `stop()`, then `ui.focus_path(path)`, or restore the saved cursor when nothing was selected), `is_active()`, `available()`. Listens (own augroup) to `User BeastVisibilityChanged` -> `session:refresh()` + re-query.
   - Why: scenarios 2, 3, 4, 5.
   - Depends on: Steps 1-3
   - Risk: Medium

6. **Test the search tree and lifecycle** (File: `tests/test-explorer-search.lua`)
   - Action: headless: build results for `in.lua` over a fixture -> expected ancestors, order, `last` flags, positions; `set_query("")` empties; zero results -> message row in the buffer; `exit()` leaves the real `Tree` open flags untouched and swaps the explorer buffer back; stopping twice is safe.
   - Why: scenarios 1 (render), 2, 3, 4 without a UI.
   - Depends on: Steps 1-5
   - Risk: Low

## Phase 3: Prompt, keys, degradation - the user-visible feature

1. **Prompt** (File: `explorer/search/prompt.lua`)
   - Action: `prompt()` opens `vim.fn.input({prompt = "/", default = state.query, cancelreturn = "\27"})` with a short-lived `CmdlineChanged` autocmd (`getcmdtype() == "@"`) debounced with `Util.debounce(config.debounce.normal_ms)` that calls `set_query(getcmdline())` then `vim.cmd.redraw()`. On return: sentinel with no earlier confirmed query -> `exit()` without moving the cursor; sentinel with a confirmed query -> restore it and its results; any text -> keep results, cursor on the first file row.
   - Why: Q4/Q5; scenarios 1 (steps 1-3) and 3.
   - Depends on: Phase 2
   - Risk: High (cmdline + redraw; mitigated by the spike)

2. **Search buffer keys** (File: `explorer/search/keymaps.lua`)
   - Action: buffer-local, `nowait`: `<CR>` (file -> `open.select`, folder -> nothing), `s` (`split_open.split`), `o` (`vim.ui.open`), `H` (`visibility.toggle_hidden`), `/` and `?` (prompt), `<Esc><Esc>` (`exit`). `<C-o>`/`<C-i>` stay `<Nop>`. Everything else, including `j`/`k`, is native.
   - Why: Q7; keeps the keys inside the search folder.
   - Depends on: Step 1
   - Risk: Low

3. **Entry key and degradation** (Files: `explorer/actions/search.lua`, `explorer/config.lua`, `explorer/keymaps.lua`)
   - Action: `actions/search.lua` -> `run = require("beast.libs.explorer.search").start`, `available = search.available` (pcall-require of `finder.search`, then its `available()`); defaults `["/"] = "search"`, `["?"] = "search"`; `keymaps.mount` skips an action whose `available()` is false so native `/` and `?` stay untouched.
   - Why: scenario 6 and the "graceful degrading" requirement.
   - Depends on: Phase 2
   - Risk: Low

4. **Reuse open/split** (Files: `explorer/actions/open.lua`, `split_open.lua`)
   - Action: add `M.select = on_select` and `M.split = on_split`.
   - Why: identical window behavior for results as for the tree.
   - Depends on: None
   - Risk: Low

5. **Wire-up test** (File: `tests/test-explorer-search.lua`)
   - Action: with `finder.search.available` stubbed false, `keymaps.mount` leaves `/` unmapped; stubbed true, `/` and `?` are mapped; search buffer keys exist after `start()` and are gone after `exit()`.
   - Why: proves graceful degradation.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 4: Performance and docs

1. **Performance pass** (File: `scripts/bench-explorer.lua`)
   - Action: add a case timing `tree.build` + `render` for 1000 matches on a large fixture, and confirm the existing explorer cases are unchanged.
   - Why: DEVELOPMENT.md makes the bench mandatory for touched benched libs; render cost is paid per keystroke.
   - Depends on: Phase 3
   - Risk: Medium

2. **Docs** (Files: `docs/CODEMAP/libraries.md`, `docs/CODEMAP/architecture.md`)
   - Action: run `/update-codemap`; make sure the explorer section lists `search/`, the new action, and the explorer -> finder soft dependency.
   - Why: repo habit after feature work.
   - Depends on: Phase 3
   - Risk: Low

# Testing Strategy

- Headless tests: `nvim --clean --headless -l tests/test-finder-search.lua` and `... tests/test-explorer-search.lua` (new); re-run `tests/test-explorer-clipboard.lua`, `test-finder-preloaded-items.lua`, `test-visibility.lua`.
- Bench: `nvim --clean --headless -l scripts/bench-explorer.lua` before and after; UX bench after Phase 3: `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all`.
- Manual, in `NVIM_APPNAME=BeastVim nvim` on this repo, following the PM scenarios:
  - 1: closed folders, `/`, type `in.lua`, `<Enter>`, `j`/`k`, `<CR>` on a file (search stays on), `s` split.
  - 2/3: `<Esc><Esc>` after results (folders revealed, real open/closed state otherwise unchanged); `<Esc>` in the first prompt.
  - 4: `zzzz` empty message, then backspace.
  - 5: `H` while searching `env`.
  - 6: `fd`, `rg`, `find` unavailable (PATH override) or finder lib removed: `/` is native search.
  - Also: sticky float absent while searching and back after; resize the window; close the explorer while searching and reopen (normal tree); open a result and check the real tree did not open folders after exit.
- Pixel check (global rule): header row, count badge alignment at width 40 and 120, match-letter contrast on light and dark themes, no leftover sticky float.

# Success Criteria

- [ ] Searching `in.lua` with every folder closed shows `lua/beast/init.lua` and the other matches.
- [ ] Search mode starts empty and the tree fills while typing.
- [ ] Results appear as a tree with the right folders opened and non-matches hidden.
- [ ] Matching letters are highlighted in each result name.
- [ ] Typing happens in a bottom prompt, with results updating live.
- [ ] `<Enter>` leaves the prompt, keeps results, and puts the cursor on the first match.
- [ ] `j`/`k` move between result rows (see Q1).
- [ ] Opening a result file works and search mode stays on.
- [ ] `<Esc><Esc>` returns the explorer to its exact pre-search state (open/closed folders), with the selected file revealed.
- [ ] A zero-result search shows the empty message and a 0 count.
- [ ] With the finder or `fd`/`rg`/`find` missing, `/` and `?` behave exactly as before.
- [ ] The existing explorer tree, state and render files are unchanged (diff shows only the listed one-line edits).
- [ ] Explorer bench shows no regression; typing in a large project stays responsive.
