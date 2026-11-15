---
name: finder-continuous
description: Chained finder pickers - an in-place level stack (push/pop on the same windows), scoped live grep, a below-the-frame key hint, and PR changed-files / issue-text levels
generated: 2026-11-15
---

> PM Spec: [docs/pm-specs/finder-continuous.md](../pm-specs/finder-continuous.md)

# Summary
The finder keeps its three windows and swaps what they show: a **level stack** inside the one `State`. `<C-g>` asks the current source for its next level (`source.drill`), pushes the current query/pipeline/prompt onto a stack and installs the new one; `<BS>` on an empty prompt or `<C-o>` pops it back with no re-search. Scoped grep is the existing `live_grep` source given a file list. The key hint is a small borderless float under the picker. Files and Buffers rows are first moved to the grep file look, because the chain relies on it.

---

# Context

## Problem
Every picker starts from nothing: `State:new` builds one `Query` + pipeline and there is no way to feed one picker's results into the next. The match pipeline also keeps only the top 1000 matches (`matched` is a TopK), so even "the files that currently match" cannot be read from the state when the prompt is short. Files rows show the whole path folder-first and Buffers rows show `[n] path`, unlike grep results (icon, name, dim folder). The fuzzy-match highlight assumes the rendered row contains the relative path contiguously, which breaks as soon as the row is reordered.

### Solution
`State` gains a `stack` of level snapshots plus `push(spec)` / `pop()` that swap `query`, `pipeline`, prompt text, title and list position in place (windows are never closed, so there is no flicker and the dimmed backdrop stays). Sources opt in through `drill = { hint, open }`. The match pipeline exposes `count(state)` / `matches(state)` (from the matcher's score table, so the full match set is available, not just 1000). `live_grep` accepts `filter.files`. New sources `gh_pr_files` and `gh_issue_grep` complete the GitHub chains. A new `ui/hint.lua` draws the tooltip line.

---

# Research

### Repo Search
- Searched for: `State:new`, `instance`, `reset`, `pipeline.load/run/abort`, `Query:new`, `Filter`, `source.preview`, `count`, `title`, `initial_query`, `preloaded_items`, `header_fn`, `set_count`, `set_title`, `batch_targets`, `survivors`, `topk_capacity`, `match_state`, `format.filename`, `compute_list_ranges`, `<BS>`/`<C-g>`/`<C-o>` mappings.
- Found:
  - `lua/beast/libs/finder/state.lua`: singleton `instance`; `new()` builds `Query`, picks `pipeline` (stream if `source.live`), creates input/list/preview/backdrop. The input `on_change` closure captures the local `query` and `pipeline`, so it must read `instance.query` / `instance.pipeline` to survive a swap. `initial_query` already provides an "echo skip" for programmatic prompt writes. `reset()` aborts only `self.query`.
  - `pipeline/match.lua`: `state.query.matched` is TopK(1000). The matcher's final `on_done` passes `match_state.scores[item.idx]` for every item (0 = no match; empty pattern = everything matches), so the full match set can be derived. `Task:running()` (`libs/async.lua`) tells whether loader/matcher are still working. Loader finishing with an empty pattern does not call `M.run`, so `match_state` may be nil (then all items match).
  - `pipeline/stream.lua`: `run_id` guard, spinner, `update_count` (local), `s.fresh` retain flow. Empty prompt clears results (unless `run_when_empty`).
  - `source/live_grep/init.lua`: `M.get(filter, cb)`; `prefilter()` returns bigram survivors (or nil = whole tree); `batch_targets(cwd, survivors)` already fans a file list into argv-sized `rg` batches. A scoped file list can be passed as the survivors.
  - `ui/list.lua`: grouped headers are decided by `items[idx].file ~= items[idx-1].file` (two places, `item_cost` and the render loop); `header_fn` comes from `format.<source>_header`.
  - `format.lua`: `filename` (icon, dim `dir/`, base), `buffers` (`[n] path [+]`), `live_grep_header` (icon, base, dim `  dir`, with `trim_path`).
  - `match_hl.lua:compute_list_ranges`: finds the relative path inside the rendered text and shifts positions by a constant offset (only valid when the path is contiguous).
  - `source/gh/api.lua` / `gh.lua` / `gh/preview.lua`: `gh api` wrapper with `classify` errors, handle `kill()`, generation guard, preview hook, `message()` rows, `count`. `normalize` drops the issue `body`.
  - `keymaps.lua`: input mappings use `map({"i","n"}, ...)`; `<CR>` ignores `item.message`; `<C-y>` copies `url or file`.
  - `autocmds.lua`: WinEnter closes the picker when focus leaves the three windows (a hint float must not be focusable).
  - Tests: `tests/test-finder-gh-keys.lua`, `test-finder-stream-retain.lua`, `test-finder-input-initial.lua`, `test-finder-preloaded-items.lua` show the integration-test pattern (real finder, fake sources). Bench: `scripts/bench-finder-matcher.lua`, `scripts/bench-ux.sh`.
- Reuse opportunity: Yes - the `initial_query` echo skip, `source.preview`/`title`/`count`/`check` hooks, `message` rows, `live_grep` batching, `live_grep_header`, `gh/api` patterns, `Toast`.

### Built-in / Existing Lib Check
- Checked: floating windows (`nvim_open_win` with `focusable=false`), `vim.system`, `vim.ui.open`, scratch buffers with `filetype=diff`, `vim.keymap.set` with `expr`, `libs/view` helpers.
- Found: GitHub REST `GET repos/{o}/{r}/pulls/{n}/files` returns, in one call, `filename`, `status`, `additions`, `deletions`, `previous_filename` and `patch` (verified with `gh api`); `patch` is absent for binary or very large diffs. No existing hint/tooltip window in the finder.
- Decision: **Reuse** the finder/state/pipeline/source machinery and extend it with opt-in fields; **Build** the level stack, `ui/hint.lua`, `gh_pr_files`, `gh_issue_grep`, and the highlight position mapping. No new dependency.

### Corrections to the PM spec found during research
1. "GitHub's own limit for this listing" is 300 files: GitHub allows up to 3000. We cap at 3 pages x 100 = 300 ourselves; wording to fix in the PM spec (scenario 9, mock title stays).
2. The mocks show a match count in the prompt row of Files, Buffers and Help (`38/912`). The finder shows none today for match sources. This plan adds it (tiny, the matcher can count for free) since the approved mocks include it.
3. The mocks show `<C-g> grep 38 files`; the number needs the *full* match count, which only the score table gives (see `pipeline.count`).

---

# Architecture Changes
- `lua/beast/libs/finder/format.lua` - modified: shared file-row builder (icon, base, dim dir, `src` ranges), `filename` and `buffers` use it, `ratio` count helper, formats for the new sources.
- `lua/beast/libs/finder/match_hl.lua` - modified: `compute_list_ranges` maps positions through `src` ranges when a row provides them.
- `lua/beast/libs/finder/matcher.lua` - modified: `MatchState.total`.
- `lua/beast/libs/finder/pipeline/match.lua` - modified: `count(state)`, `matches(state)`, settled count label, title refresh on load.
- `lua/beast/libs/finder/pipeline/stream.lua` - modified: `count`, `matches`, empty-prompt placeholder row, export `update_count` use.
- `lua/beast/libs/finder/state.lua` - modified: `stack`, `push`, `pop`, closure refactor, `reset` cleans stacked queries, hint wiring.
- `lua/beast/libs/finder/chain.lua` - **new**: `drill(state)`, `back(state)`, `hint_text(state)`, level spec types.
- `lua/beast/libs/finder/ui/hint.lua` - **new**: the below-the-frame tooltip window.
- `lua/beast/libs/finder/ui/input.lua` - modified: `set_text`.
- `lua/beast/libs/finder/ui/list.lua` - modified: group key `item.group or item.file`.
- `lua/beast/libs/finder/layout.lua`, `highlights.lua`, `ui/init.lua` - modified: hint geometry, `BeastFinderHint`, registry.
- `lua/beast/libs/finder/keymaps.lua` - modified: `<C-g>`, `<BS>` (expr), `<C-o>`.
- `lua/beast/libs/finder/query.lua`, `filter.lua`, `source/init.lua` - modified: `files`, `ctx` options and the `drill` / `crumb` / `placeholder` source fields.
- `lua/beast/libs/finder/source/{files,buffers,help_tags}.lua` - modified: `drill`, `count`.
- `lua/beast/libs/finder/source/live_grep/init.lua` - modified: scoped `filter.files`, `placeholder`.
- `lua/beast/libs/finder/source/gh/api.lua` - modified: `files()` (paged REST), `normalize_files`, issue `body`.
- `lua/beast/libs/finder/source/gh_pr_files.lua`, `source/gh_issue_grep.lua` - **new** sources; `source/gh.lua` - modified: `drill` for PRs and issues; `source/gh/preview.lua` - modified or sibling for diff preview.
- `lua/beast/libs/finder/action.lua` - modified: open a changed file's diff in a read-only buffer.
- `tests/test-finder-*.lua` - new tests (see Testing Strategy); `docs/CODEMAP/libraries.md`, `INDEX.md` - updated at the end.

## Level model (shared by all phases)

```
Level snapshot (what push() saves, pop() restores)
  source_name, query (kept alive: items, matched, filter), pipeline,
  text (prompt), title, cursor, list offset, crumb ("Files"), count label

source.drill = {
  hint = function(total, selected) -> string?     -- text after "<C-g> ", nil hides the hint
  open = function(ctx) -> spec | string | nil     -- spec = new level; string = toast; nil = "Nothing to open from here"
}
ctx = { items = full match set (nil while still working), selected = item, filter = filter }
spec = { source = "live_grep", files = {...}?, ctx = {...}?, title = string|fun, crumb = "Files" }
```

Drill is refused (toast, nothing changes) while the pipeline is not settled (`Task:running()` / spinner active), with an empty list, or when `source.drill` is missing.

## Implementation Phases

## Phase 1: Row look - Files and Buffers use the grep file look (prerequisite, ships alone)
1. **Shared file row** (File: `lua/beast/libs/finder/format.lua`)
   - Action: extract the body of `live_grep_header` into a local `file_row(path, cwd, max_width, opts)` returning highlights: icon, base (`BeastFinderListFile`), dim `"  " .. dir` (`BeastFinderListDir`, trimmed with `trim_path` to the remaining width). Each highlight part carries `src = { from, to }` (byte range in the relative path it was taken from; dir range excludes the trailing `/`). `live_grep_header` calls it (behavior unchanged).
   - Why: one definition of the look; Files/Buffers/grep headers cannot drift.
   - Depends on: None. Risk: Low
2. **Files and Buffers rows** (File: `format.lua`)
   - Action: `M.filename` returns `file_row`. `M.buffers` returns `file_row` for named buffers (`[No Name]` plain for nameless) plus a trailing `[+]` in `BeastFinderListMatch` when modified; the `[n]` prefix is dropped.
   - Depends on: Step 1. Risk: Medium - `filename` is the default formatter for any source without its own.
3. **Highlight mapping** (File: `lua/beast/libs/finder/match_hl.lua`)
   - Action: in `compute_list_ranges`, when the formatted parts carry `src`, convert each match position (1-based index into the relative path) to a rendered column by finding the part whose `src` range contains it; positions in the dropped `/` or in a trimmed (ellipsis) region are skipped. Parts without `src` keep the existing offset logic.
   - Why: the current offset trick assumes a contiguous path.
   - Depends on: Step 1. Risk: Medium
4. **Tests** (Files: `tests/test-finder-format.lua` new, `tests/test-finder-match-hl.lua` new)
   - Action: rows for root file, nested file, long dir (trimmed), nameless / modified buffer; position mapping for base-only, dir-only, across the boundary, trimmed dir. Update any existing test that asserts the old row text.
   - Risk: Low

## Phase 2: Chain core + Files -> grep (the first complete chain)
1. **Full match set and count** (Files: `matcher.lua`, `pipeline/match.lua`)
   - Action: `MatchState.total` counted in the final pass (empty pattern: `#items`). `match.count(state)` returns the total when loader and matcher tasks are not running (else nil); `match.matches(state)` returns `query.items` for an empty pattern, otherwise the items whose `scores[idx] > 0`. After each settled run, `ui.input.set_count(source.count(items, total))` when the source defines `count`; on loader completion with a source `title` function, refresh the title with `source.title(filter, items)`.
   - Why: scope must be everything that matches, not the 1000 shown.
   - Risk: Medium (hot path: the counter must cost O(1) per item - bench).
2. **Stream equivalents** (File: `pipeline/stream.lua`)
   - Action: `stream.count(state)` / `stream.matches(state)` (settled when no spinner/run active); empty prompt with `source.placeholder(filter)` renders one message row (`message = true`).
   - Depends on: Step 1. Risk: Low
3. **Level stack in State** (File: `state.lua`)
   - Action: `stack = {}`; input `on_change` uses `instance.query` / `instance.pipeline`; `push(spec)` snapshots, `render.cleanup(old query)`, builds a `Query` (new `files`, `ctx` options flow into `Filter`), swaps pipeline by `source.live`, clears list cursor/offset and preview, writes an empty prompt via `ui.input.set_text` (echo-skip), sets title/count, then `pipeline.load` / `pipeline.run`. `pop()` aborts the child query, restores the saved query/pipeline/prompt (echo-skip), title, count, cursor, offset and calls `render.render` - no search. `reset()` also aborts and cleans every stacked query.
   - Depends on: Steps 1-2. Risk: High (singleton lifecycle, WinEnter guard, stale callbacks of the aborted child).
4. **Input text** (File: `ui/input.lua`)
   - Action: `set_text(view, text)` rewriting line 1 after the prompt prefix, cursor at end.
   - Risk: Low
5. **Hint window** (Files: `ui/hint.lua` new, `ui/init.lua`, `layout.lua`, `highlights.lua`, `state.lua`)
   - Action: borderless `focusable = false` float, `zindex` above the three panels, one line, right edge aligned to the picker's right edge, row just under the bottom border; hidden when `row + 1 > vim.o.lines - vim.o.cmdheight` or the layout is `cards`; `BeastFinderHint` (dim fg, bg and blend taken from the backdrop so it looks like part of the dim). `relayout` repositions it; `reset` closes it. Text comes from `chain.hint_text(state)`: `<C-g> <drill.hint>` and, below level 1, `<BS> back to <crumb>`; refreshed from `render.render` (O(1)).
   - Risk: Medium (visual match with the backdrop: verify in wezterm light and dark).
6. **Orchestration and keys** (Files: `chain.lua` new, `keymaps.lua`)
   - Action: `<C-g>` -> `chain.drill(state)` (refusals as toasts: "Nothing to open from here", "Still searching - try again in a moment"); `<C-o>` -> `chain.back(state)` (no-op at level 1, toast not needed); `<BS>` as an `expr` insert/normal mapping that pops when the prompt text is empty and depth > 1, else returns a real `<BS>`.
   - Depends on: Steps 3-5. Risk: Medium (insert-mode `<C-o>` is normally "one normal command").
7. **Scoped live grep** (File: `source/live_grep/init.lua`, `filter.lua`, `query.lua`)
   - Action: `Filter` carries `files` (absolute paths); `M.get` uses them as survivors (skipping the bigram index, optionally intersected with it); `M.placeholder(filter)` returns "(type to search inside the N files)" only when `filter.files`. Title spec: `"<N> Files › Live Grep"`.
   - Risk: Medium
8. **Files drill** (Files: `source/files.lua`, `source/init.lua` types, `format.lua`)
   - Action: `count = format.ratio`; `drill.hint = function(total) return ("grep %d files"):format(total)`, `drill.open` builds `{ source = "live_grep", files = <abs paths of ctx.items>, title = N .. " Files › Live Grep", crumb = "Files" }`.
   - Risk: Low
9. **Tests** (Files: `tests/test-finder-chain.lua` new, `tests/test-finder-chain-grep.lua` new)
   - Action: fake sources: push/pop restores prompt, cursor, results with no re-run; `<BS>` on empty vs non-empty prompt; `<C-o>`; `<Esc>` closes the whole chain; refusals (no drill, empty list, still loading); more than 1000 matches still scope all of them; hint text and visibility; real `live_grep` over a temp directory returns only scoped files.
   - Risk: Low

## Phase 3: Buffers and Help -> grep
1. **Buffers drill** (File: `source/buffers.lua`): scope = matched items with a `file` (nameless skipped); `count`; hint `grep N files`; crumb "Buffers"; title `N Buffers › Live Grep`. Risk: Low
2. **Help drill** (File: `source/help_tags.lua`): scope = distinct `item.file` of matched tags; `count`; title `N Help Files › Live Grep`; crumb "Help". Risk: Low
3. **Tests** (File: `tests/test-finder-chain-sources.lua` new): scope derivation for both. Risk: Low

## Phase 4: Pull requests -> Files Changed
1. **API** (File: `source/gh/api.lua`)
   - Action: `M.files(item, cb)` runs `gh api repos/{slug}/pulls/{n}/files?per_page=100` for pages 1..3 (stop on short page), `--hostname`, returns normalized `{ path, previous, status, additions, deletions, patch? }` and `truncated` when a 4th page would exist; errors through the existing `classify`. Handle with `kill()`.
   - Risk: Medium
2. **Source** (File: `source/gh_pr_files.lua` new; `format.lua`)
   - Action: match-pipeline async source: `get(filter, cb)` reads `filter.ctx.pr`, emits one item per file (`file` = relative path for fuzzy matching and the row, status icon, `patch`), message rows for errors; `title(filter, items)` = `PR <title trimmed with ...> › Files Changed (N)`; `count`; `preview` shows the patch with diff highlighting (`filetype=diff`), header with status and +/- counts, "(diff too large or binary)" when `patch` is nil; `Enter` handled by `action`.
   - Depends on: Step 1. Risk: Medium
3. **Open diff** (File: `action.lua`)
   - Action: for `gh_pr_files` items open a read-only scratch buffer (`buftype=nofile`, `filetype=diff`, name `owner/name#N: path`) in the main window, cursor on the first hunk.
   - Risk: Low
4. **PR drill** (File: `source/gh.lua`): `kind == "pr"`: hint `files changed in #N` (needs `selected`), `open` returns `{ source = "gh_pr_files", ctx = { pr = selected }, crumb = "Pull Requests" }`; refuse on message rows. Risk: Low
5. **Tests** (Files: `tests/test-finder-gh-files-api.lua`, `test-finder-gh-pr-files.lua` new): paging and truncation, error mapping, row/preview content, title trimming, chain push/pop from the PR list with no new search. Risk: Low

## Phase 5: PR files -> grep (local copies)
1. **Drill** (File: `source/gh_pr_files.lua`): scope = items not `removed` whose path exists under the project root (`vim.uv.fs_stat`); none -> toast "None of these files exist in your working tree"; title `N PR Files › Live Grep`; scoped grep's placeholder says "your local copies". Risk: Low
2. **Tests** (File: `tests/test-finder-chain-pr-grep.lua` new): removed and missing files dropped, count, none-exist toast, three-level back chain. Risk: Low

## Phase 6: Issues -> grep (title and description)
1. **Keep the body** (File: `source/gh/api.lua`): `normalize` keeps `body` on items. Risk: Low
2. **Source** (Files: `source/gh_issue_grep.lua` new, `format.lua`, `ui/list.lua`)
   - Action: live source over `filter.ctx.issues`: for the prompt text (smartcase literal match) emit one item per matching line of `title` + `body` with `group` = issue url, `pos`, `url`; `format.gh_issue_grep_header` (icon, `#N`, title); `ui/list.lua` groups by `item.group or item.file`; preview shows the issue; `Enter` opens `url`; placeholder "(type to search the text of the N issues)"; `drill` on `gh_issue`: hint `grep N issues`.
   - Risk: Medium (list grouping change touches a shared renderer: covered by the existing separator/grouping tests)
3. **Tests** (File: `tests/test-finder-gh-issue-grep.lua` new). Risk: Low

## Phase 7: Docs and wrap-up
1. Update `docs/CODEMAP/libraries.md` and `INDEX.md` (finder section: chain, hint, new sources, opt-in fields). 2. Fix the PM spec wording noted above. 3. Final verification (below). Risk: Low

# Testing Strategy
- Headless tests: new files listed per phase; run `for f in tests/test-finder-*.lua; do nvim --clean --headless -l "$f"; done` plus `tests/test-preflight*`; stylua (`stylua --check lua/ tests/`); lua-language-server check as in DEVELOPMENT.md.
- Bench: `scripts/bench-finder-matcher.lua` before and after Phase 2 (the counter must not move p50/p99); `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all`, compared with a baseline worktree of the starting commit.
- Manual (real wezterm pane, `NVIM_APPNAME=BeastVim`), per PM spec scenarios: Phase 1 STATE 0 (Files, Buffers look, fuzzy highlight on base and dir); Phase 2 scenarios 1, 2, 5, 6, 7; Phase 3 scenarios 10, 11; Phase 4 scenarios 3, 4, 8, 9 (use a public repo with a large PR); Phase 5 scenario 12; Phase 6 scenario 13. Check the hint under the frame in dark and light themes and at a short terminal height (hidden when no room).
- Not testable offline (state clearly in the final report): live GitHub paging beyond what is stubbed, clipboard, browser open.

# Success Criteria
- [ ] Files and Buffers rows show icon, file name and dim folder; `[+]` on modified buffers; the fuzzy match highlight is correct on name and folder (STATE 0).
- [ ] In Files, Buffers and Help, `<C-g>` opens a grep that only returns matches inside the matching files / help pages, including when more than 1000 items match.
- [ ] In Pull Requests, `<C-g>` lists the changed files of the highlighted PR with the diff, status and +/- counts in the preview; typing filters by path; capped at 300 files with a `(partial)` title.
- [ ] From a PR's changed files `<C-g>` greps the local copies (removed / missing files dropped, count reflects it); in Issues `<C-g>` greps title and description.
- [ ] `<BS>` on an empty prompt and `<C-o>` return to the earlier level with the same prompt, results and highlighted row; no new search (GitHub or files).
- [ ] `<Esc>` / `<C-c>` close the whole chain; `<Enter>` on a result closes it.
- [ ] Titles read `38 Files › Live Grep` / `PR <title...> › Files Changed (N)`; the hint sits under the picker, right-aligned, hidden when there is no room.
- [ ] `<C-g>` with no next step, an empty list, or a still-working list toasts and changes nothing.
- [ ] Windows are never closed and reopened during a push or pop (no flicker, backdrop stays).
- [ ] Technical gates: all finder tests pass, luals and stylua clean, matcher bench and `bench-ux.sh all` within noise of baseline, no `vim.notify` or lib-config keymaps in new code (Toast and `packer.lazy` conventions).
