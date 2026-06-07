# Dev Spec: Git Blame for `beast.libs.git`

## Summary

Add `git blame` support to `beast.libs.git` in two layers that share one
data engine:

1. **Current-line blame** — passive virt_text at end-of-line showing the
   author / date / summary for the line under the cursor. Updates on
   `CursorMoved` (debounced), hidden in insert mode.
2. **Full-file blame** — an interactive side window aligned line-for-line
   with the source buffer, opened on demand via `<leader>gB`. Supports
   "reblame parent" and "open commit diff" inside the side window.

Both layers call a shared `blame.lua` data module that wraps
`git blame --incremental` via `vim.system`, streams stdout through a
buffered line reader, and returns `{ [lnum] = BlameInfo }` plus a
deduped `commits[sha]` table. Phase 1 ships the engine + current-line
blame (the higher-daily-value half); Phase 2 layers the side window on
top.

Out of scope:

- `.git-blame-ignore-revs` (skip-revisions) — easy to add later, not v1.
- Word-level blame.
- Statusline integration (a follow-up can read `vim.b[buf].beast_git_blame_line_dict`).
- Re-blame across renames in the full-blame UI (we surface
  `previous_filename` but no jump UI for it in v1).
- `--contents -` on every keystroke — we send buffer contents via stdin
  only when the buffer is modified at the time of the blame call.

## Requirements

- New module `lua/beast/libs/git/blame.lua` exposing:
  - `run(ctx, opts, cb)` — async; `opts = { lnum?, ignore_whitespace?, revision?, contents? }`; calls `cb({ [lnum] = BlameInfo }, { [sha] = CommitInfo })`.
  - Streams `git blame --incremental` via `vim.system`'s `stdout` callback (chunked) through a coroutine-based line reader; handles partial-line splits at chunk boundaries.
  - Special-cases untracked files (returns synthetic `"Not Committed Yet"` commit, sha = `0000...`) using `ctx.path_data == nil` as the signal — symmetric with `init.lua:97`.
- New module `lua/beast/libs/git/current_line_blame.lua`:
  - One extmark per buffer in namespace `beast_git_blame`, fixed id = 1.
  - Updates on `CursorMoved` / `CursorMovedI` / `BufEnter` / `WinResized` (debounced via `Util.debounce` at `config.blame.delay_ms`).
  - Clears on `InsertEnter` / `BufLeave` / `OptionSet[fileformat,bomb,eol]`.
  - Skips: insert mode, folded lines (`vim.fn.foldclosed ~= -1`), buffers with no attach state, untracked files (commit info would be meaningless).
  - **Cursor-moved re-trigger guard**: if the cursor moved during the async fetch, recurse with the new lnum (don't paint stale text).
  - Stashes the raw info on `vim.b[buf].beast_git_blame_line_dict` and rendered string on `beast_git_blame_line` for downstream statusline consumers.
  - Formatter: format string with `<author>`, `<author_time:%R>`, `<summary>`, `<abbrev_sha>` placeholders (reuse the lightweight expander pattern from gitsigns — `util.expand_format`-equivalent). Replaces `info.author` with `"You"` when it matches `git config user.name`.
- New module `lua/beast/libs/git/blame_view.lua` (Phase 2):
  - `Beast.Git.BlameView extends Beast.View` — opens a vertical split on the left of the source window, ~`computed_width` columns wide, showing `<abbrev_sha> <padded-author> <relative-date>` per line.
  - Scroll-synced with the source window via `WinScrolled` autocmd (set `scrollbind` on both).
  - Keymaps inside the blame buffer (buffer-local):
    - `<CR>` — show full commit diff in a float (`git show <sha>` via `vim.system`, reuse the existing `preview.lua` float shape).
    - `r` — reblame `parent` of the commit under cursor (`<sha>^` revision).
    - `R` — reset to current (HEAD) blame.
    - `q` / `<Esc>` — close.
  - Closes cleanly when the source window closes (autocmd on the source winid).
- `repo.lua` extension:
  - `get_username(cb)` — `git config user.name`, memoised module-wide (one process call per session). No `ctx` arg needed — `user.name` is process-global.
- `config.lua` extension — append a `blame` block:
  ```lua
  blame = {
    enabled = true,                                  -- master switch for current-line blame
    delay_ms = 500,                                  -- debounce for cursor-driven updates
    virt_text_pos = "eol",                           -- "eol" | "right_align"
    ignore_whitespace = false,                       -- --ignore-whitespace flag
    formatter = " 󰊢 <author>, <author_time:%R> • <summary>",
    formatter_nc = " 󰊢 <author>",                    -- "Not Committed Yet" formatter
    use_focus = true,                                -- update on FocusGained too
  }
  ```
- `init.lua` integration:
  - In `M.setup(opts)`, after `ensure_autocmds()`, call `require("beast.libs.git.current_line_blame").setup()` when `config.blame.enabled` is true.
  - In `M.detach(buf)`, also clear the blame extmark + buffer vars (`reset(buf)` in `current_line_blame.lua`).
  - Public surface additions:
    - `M.blame_line(opts?)` — manually trigger current-line blame for the current cursor pos (returns the BlameInfo via callback). Useful for `:checkhealth` and ad-hoc inspection.
    - `M.toggle_current_line_blame()` — flip `config.blame.enabled`, run setup / teardown accordingly.
    - `M.blame()` — open the full-file blame side window (Phase 2).
- `highlights.lua` extension:
  - `BeastGitCurrentLineBlame` — dim foreground, no background. Use `Util.colors.blend(p.dimmed1, 0.6, <fallback>)` or similar.
  - `BeastGitBlameViewSha`, `BeastGitBlameViewAuthor`, `BeastGitBlameViewDate` (Phase 2) — three subtle colors so the side window reads cleanly without distracting.
- `health.lua` extension:
  - Check `git config user.name` is set (warn if empty — formatter would not match "You").
  - Report `config.blame.enabled` state and last-blame duration per attached buffer.
- Default keymaps (buffer-local, registered in `init.lua` when `config.keymaps` is true):
  - `<leader>gb` — `M.blame_line()` (one-shot info float for the current line, like `:Gitsigns blame_line`).
  - `<leader>gB` — `M.blame()` (open full-file blame side window).
  - `<leader>gtb` — `M.toggle_current_line_blame()`.

## Research

### Repo Search

- Searched for: `blame`, `git blame`, `vim.system.*blame`, `extmark.*virt_text`, `nvim_buf_set_extmark.*virt_text_pos`, `CursorMoved.*debounce`, `vim.fn.foldclosed`
- Found:
  - `lua/beast/libs/git/init.lua:243` — already uses `Util.debounce(config.debounce_ms, fn)` for `on_lines` recomputes. Drop-in for the blame cursor debouncer (same lifecycle: `:close()` on detach).
  - `lua/beast/libs/git/repo.lua:84-108` — `vim.system` wrapper pattern with `vim.schedule` callback hop. Adopt for `run_blame` and `get_username`.
  - `lua/beast/libs/git/preview.lua` — `Beast.View` subclass for hunk preview, including auto-close on source-buffer events. The Phase-2 blame side window reuses the same shape (subclass `Beast.View`, manage lifecycle via source-window autocmds).
  - `lua/beast/libs/git/init.lua:489` — public `_namespaces` table is already exposed; add `blame` to it so external tools / `:checkhealth` can introspect.
  - `lua/beast/libs/notify/ui.lua:5`, `lua/beast/libs/explorer/sticky.lua:21` — additional `Beast.View` subclass exemplars for the side-window pattern.
  - `lua/beast/libs/git/init.lua:97` — `path_data == nil` is the canonical "untracked" signal in this lib; reuse for blame's NC fallback rather than introducing a new check.
- Reuse opportunity: **Adopt** `Util.debounce`, `vim.system` repo wrappers, `Beast.View`, and `path_data` untracked detection. No extraction needed — the patterns are already shared.

### Package Search

- Searched: gitsigns.nvim (`~/.local/share/nvim/lazy/gitsigns.nvim`), Neovim native API (`vim.system`, `nvim_buf_set_extmark`, `coroutine`).
- Found:
  - **gitsigns `lua/gitsigns/git/blame.lua`** — incremental porcelain parser, buffered line reader (coroutine wrap), `--contents -` for modified buffers, `-L lnum,+1` for single-line. Adopt the **algorithm shape** (not the code — gitsigns uses an async runtime and message system we don't have).
  - **gitsigns `lua/gitsigns/current_line_blame.lua`** — single namespace + fixed extmark id; reset / update autocmd groups; cursor-moved re-trigger guard; `right_align` → `eol` fallback when virt_text would overflow window width.
  - `vim.system(cmd, { stdin = ..., stdout = fn, text = true })` — native, gives us streaming stdout directly; no plugin needed.
  - `vim.api.nvim_create_namespace` + `nvim_buf_set_extmark` with `virt_text` + `virt_text_pos = "eol" | "right_align"` — native, no add-on required.
- Decision: **Use native** for the runtime (`vim.system`, extmarks, coroutines), **Adopt** the algorithmic patterns from gitsigns (porcelain parsing, single-line `-L`, `--contents` for modified buffers, cursor re-trigger guard). No new dependency, no new shared util.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/git/blame.lua` | Create | Shared data engine — spawn `git blame --incremental`, parse porcelain, return `{ [lnum] = BlameInfo }` |
| `lua/beast/libs/git/current_line_blame.lua` | Create | Phase 1 — cursor-driven virt_text at EOL via extmark in `beast_git_blame` namespace |
| `lua/beast/libs/git/blame_view.lua` | Create | Phase 2 — `Beast.View`-subclassed side window with full-file blame |
| `lua/beast/libs/git/repo.lua` | Modify | Add `get_username(cb)` (memoised `git config user.name`) |
| `lua/beast/libs/git/config.lua` | Modify | Add `blame` block (enabled, delay_ms, virt_text_pos, formatters, ignore_whitespace, use_focus) |
| `lua/beast/libs/git/highlights.lua` | Modify | Add `BeastGitCurrentLineBlame` (Phase 1) and `BeastGitBlameView{Sha,Author,Date}` (Phase 2) |
| `lua/beast/libs/git/health.lua` | Modify | Report `user.name` presence, blame state, per-buffer last-blame timing |
| `lua/beast/libs/git/init.lua` | Modify | Wire blame setup / teardown into `M.setup` and `M.detach`; expose `blame_line`, `toggle_current_line_blame`, `blame`; register keymaps `<leader>gb`, `<leader>gB`, `<leader>gtb` |
| `scripts/bench-git-blame.lua` | Create | Bench `blame.run` for 100 / 1 k / 10 k-line files; single-line (`-L`) vs full-file; threshold for single-line ≤ 30 ms median |
| `docs/CODEMAPS/libraries.md` | Modify | Add `blame.lua`, `current_line_blame.lua`, `blame_view.lua` to the git tree; document the `beast_git_blame` namespace |

## Implementation Phases

### Phase 1: Engine + current-line blame — `blame.lua` + `current_line_blame.lua` + `repo.lua` + `config.lua` + `highlights.lua` + `init.lua` wiring + bench

**Goal**: Replace gitsigns' `current_line_blame` for daily use. After this phase, opening any file in a git repo and sitting on a line for `delay_ms` shows the author / date / summary as virt_text. Toggling and disabling work cleanly.

1. **Extend `config.lua`** (File: `lua/beast/libs/git/config.lua`)
   - Action: Append the `blame = { enabled, delay_ms, virt_text_pos, ignore_whitespace, formatter, formatter_nc, use_focus }` block to `defaults`. Keep the frozen-metatable read pattern unchanged.
   - Why: Every other lib defaults its block here (config pattern from ADR-003). Centralises tunables before any consumer reads them.
   - Depends on: None
   - Risk: Low

2. **Extend `repo.lua`** (File: `lua/beast/libs/git/repo.lua`)
   - Action: Add `get_username(cb)` — `vim.system({ "git", "config", "user.name" }, { text = true }, ...)`. Memoise in a module-local `cached_username` (string or `false` for "unset"); only invoke once per session. Schedule the callback hop, matching existing wrappers.
   - Why: Needed by the formatter to substitute `"You"` for the current user. Process-global, so no `ctx` argument.
   - Depends on: Step 1
   - Risk: Low

3. **Create `blame.lua`** (File: `lua/beast/libs/git/blame.lua`)
   - Action: Three pieces.
     - Types: `Beast.Git.CommitInfo` (`sha`, `abbrev_sha`, `author`, `author_mail`, `author_time`, `author_tz`, `committer*`, `summary`, optional `boundary`); `Beast.Git.BlameInfo` (`orig_lnum`, `final_lnum`, `commit`, `filename`, optional `previous_sha`, `previous_filename`).
     - Internal `buffered_line_reader(handler)` — coroutine wrapping a `data → lines` splitter; preserves a partial last line across chunks. Port the algorithm from gitsigns' `git/blame.lua:178-211`, simplified (no `peek` since our incremental_iter doesn't need it — read sequentially).
     - `run(ctx, opts, cb)` — assemble command:
       ```
       git -C <toplevel> blame --incremental
         [--contents -]              (when opts.contents is set)
         [--ignore-whitespace]       (when opts.ignore_whitespace)
         [-L <lnum>,+1]              (when opts.lnum is set)
         [<revision>]                (when opts.revision is set)
         -- <relpath>
       ```
       Stream stdout via `vim.system({ ..., stdout = chunk_handler, stdin = opts.contents, text = true }, on_exit)`. The `chunk_handler` feeds the coroutine; the coroutine parses block-by-block: header `<sha> <orig> <final> <size>` → optional metadata lines (`author`, `author-mail`, `author-time`, `summary`, `previous`, ...) → terminating `filename <path>`. Dedup commits in a `commits[sha]` table; emit `result[final_lnum + j]` for `j = 0..size-1`. On exit, schedule `cb(result, commits)`.
     - Untracked / no-HEAD fallback: if `ctx.path_data == nil` (or caller passes `opts.untracked = true`), short-circuit — return a synthetic NC commit (sha = `string.rep("0", 40)`) covering all lines (single line if `opts.lnum`, else `opts.contents` line count).
   - Why: This is the entire data layer. Both Phase-1 current-line blame and Phase-2 full-file blame call only `run()`.
   - Depends on: Steps 1, 2
   - Risk: Medium — porcelain edge cases (`boundary` tag, `previous` line, `--contents` external-file marker per gitsigns `git/blame.lua:135`). Mitigated by 6 unit tests over fixture porcelain payloads (clean commit, NC, boundary commit, `previous`, `--contents` external, multi-line block).

4. **Create `current_line_blame.lua`** (File: `lua/beast/libs/git/current_line_blame.lua`)
   - Action:
     - `local NS = api.nvim_create_namespace("beast_git_blame")`; `EXTMARK_ID = 1`.
     - `reset(buf)` — `nvim_buf_del_extmark(buf, NS, EXTMARK_ID)`; clear `vim.b[buf].beast_git_blame_line`, `beast_git_blame_line_dict`.
     - `format(commit, blame_info, username)` — substitute placeholders `<author>` (replace with `"You"` when equal to `username`), `<author_time:%R>` (relative-time via `os.difftime` + thresholds — minutes / hours / days / months / years; mimic gitsigns' `:%R` shorthand), `<summary>`, `<abbrev_sha>`, `<author_mail>` in `config.blame.formatter` (or `formatter_nc` for the NC commit).
     - `update(buf)` — async pipeline:
       1. Bail if insert mode / `bufnr ~= win_buf` / not in attach state / `foldclosed(lnum) ~= -1`.
       2. Capture `start_lnum = cursor lnum`.
       3. Determine `contents`: if `vim.bo[buf].modified` then `nvim_buf_get_lines(0, -1, false)`; else `nil`.
       4. Call `blame.run(ctx, { lnum = start_lnum, contents = contents, ignore_whitespace = config.blame.ignore_whitespace }, on_done)`.
       5. In `on_done(result, _)`: re-check buffer validity; if `cursor lnum ~= start_lnum`, recurse `update(buf)`; else build virt_text via `format()` and call `nvim_buf_set_extmark(buf, NS, lnum-1, 0, { id = EXTMARK_ID, virt_text = {{ text, "BeastGitCurrentLineBlame" }}, virt_text_pos = pos, hl_mode = "combine" })`.
       6. If `virt_text_pos == "right_align"` and `strwidth(text) > win_width - line_len`, fall back to `"eol"`.
     - `setup()` — create `BeastGitBlame` augroup; on update events (`BufEnter`, `CursorMoved`, `CursorMovedI`, `WinResized`, and `FocusGained` if `config.blame.use_focus`), `reset(buf)` then schedule `debounced_update(buf)` (per-buffer debouncer in a `WeakMap`-style table, freed in `teardown`). On reset events (`InsertEnter`, `BufLeave`, `OptionSet` for `fileformat`/`bomb`/`eol`), call `reset(buf)`.
     - `teardown()` — `nvim_del_augroup_by_name("BeastGitBlame")`; clear all extmarks in `NS` across loaded buffers; close all per-buffer debouncers.
   - Why: This is the visible UX. Mirrors gitsigns' `current_line_blame.lua` minus their async runtime, swapped for our callback-style `blame.run`.
   - Depends on: Step 3
   - Risk: Medium — cursor-race window. Mitigated by the captured-lnum + recurse guard (Step 4.5).

5. **Extend `highlights.lua`** (File: `lua/beast/libs/git/highlights.lua`)
   - Action: Add `CurrentLineBlame = { fg = Util.colors.blend(p.dimmed1, 0.45, p.dark1), italic = true }`.
   - Why: Foreground only — virt_text shouldn't have a background tint that fights the line.
   - Depends on: None
   - Risk: Low

6. **Wire into `init.lua`** (File: `lua/beast/libs/git/init.lua`)
   - Action:
     - In `M.setup`, after `ensure_autocmds()`, `if config.blame.enabled then require("beast.libs.git.current_line_blame").setup() end`.
     - In `M.detach`, after `signs.clear(buf)`, call `require("beast.libs.git.current_line_blame").reset(buf)` (cheap no-op if blame disabled).
     - Add `M.blame_line(opts)` — wrapper around a one-shot `blame.run` for the current cursor line, opens a small `Beast.View` float showing full commit info (sha, author, mail, summary, body). (Reuses the preview float shape; small enough to inline here, no new module.)
     - Add `M.toggle_current_line_blame()` — flips `config.blame.enabled`; calls `setup()` or `teardown()`. Note: this mutates `config`, which is currently frozen via metatable (`config.lua:67`). Workaround: expose a `config.set("blame.enabled", v)` helper rather than direct assignment (one-line addition to `config.lua` in Step 1).
     - Register buffer-local keymaps in the attach path when `config.keymaps` is true: `<leader>gb` → `blame_line`, `<leader>gtb` → `toggle_current_line_blame`. (`<leader>gB` waits for Phase 2.)
     - Append `blame = NS` to the existing `_namespaces` table.
   - Why: Single entry point — users get blame automatically when they call `git.setup({})`.
   - Depends on: Steps 1, 4, 5
   - Risk: Low — all existing wiring stays intact; new code is additive.

7. **Extend `health.lua`** (File: `lua/beast/libs/git/health.lua`)
   - Action: After existing checks, run `repo.get_username(...)` synchronously (via a `co.yield` shim or just sync `vim.system({ ... }, { text = true }):wait()` — health is allowed to block briefly). Warn if empty. Report `config.blame.enabled` and `last_blame_ms` per attached buffer (add this field to `state[buf]` in Step 4's update path).
   - Why: Catches the silent-failure mode where `<author>` never resolves to `"You"`.
   - Depends on: Steps 2, 4
   - Risk: Low

8. **Create `scripts/bench-git-blame.lua`** (File: `scripts/bench-git-blame.lua`)
   - Action: Pick a real file from this repo (e.g. `lua/beast/libs/git/init.lua` — currently ~560 lines). For each of `{ single_line, full_file }` × `{ unmodified, modified }`, measure `blame.run` wall time over N=20 iterations, report median + p95. Hard threshold: single-line unmodified ≤ 30 ms median; flag (don't fail) full-file > 200 ms.
   - Why: Single-line blame is on the cursor-move hot path — regressions are user-visible (jitter on movement). Full-file is on-demand, looser bound.
   - Depends on: Step 3
   - Risk: Low

9. **Update codemap** (File: `docs/CODEMAPS/libraries.md`)
   - Action: Add `├── blame.lua`, `├── current_line_blame.lua` to the git tree (lines 307-322); add `beast_git_blame` to the namespaces note; add a short "Blame" subsection under the git module describing the two layers.
   - Why: Codemap-freshness instruction file requires updating before commit when adding new files.
   - Depends on: Steps 3, 4
   - Risk: Low

**Phase 1 checkpoint**: open any file in a git repo; sit on a line; after `delay_ms`, see virt_text with author + relative date + summary. Enter insert → text disappears. `<leader>gtb` toggles. `<leader>gb` opens commit info float. Bench passes.

### Phase 2: Full-file blame side window — `blame_view.lua` + `init.lua` wiring + `highlights.lua` extension

**Goal**: `<leader>gB` opens a left-side window showing one blame line per source line, scroll-synced. Inside: reblame parent, show commit, close.

1. **Extend `highlights.lua`** (File: `lua/beast/libs/git/highlights.lua`)
   - Action: Add `BlameViewSha`, `BlameViewAuthor`, `BlameViewDate` (three subtle blended tones — sha brightest, author mid, date dimmest).
   - Why: Three-tone hierarchy makes the side window scan-able without distracting.
   - Depends on: None
   - Risk: Low

2. **Create `blame_view.lua`** (File: `lua/beast/libs/git/blame_view.lua`)
   - Action:
     - `Beast.Git.BlameView extends Beast.View`; state holds source `winid`, source `bufnr`, current `revision` (`nil` = HEAD), blame buffer + window IDs, autocmd group.
     - `open(source_winid, opts)` — verify source buf is attached; resolve `ctx`; call `blame.run(ctx, { revision = state.revision, contents = modified and lines or nil }, on_done)`. In `on_done`:
       1. Compute column widths: `max_author_width`, `max_date_width` across all entries; cap author at 20 chars, date at 12 chars.
       2. Build lines `<abbrev_sha> <author_padded> <date_padded>`; build extmark batch with `BeastGitBlameView{Sha,Author,Date}` highlights at the column ranges.
       3. Open vertical split to the left: `vim.cmd("topleft vnew")` then `nvim_win_set_width(new_win, width)`; `nvim_win_set_buf(new_win, blame_buf)`. Set blame buf options: `buftype=nofile`, `swapfile=false`, `filetype=BeastGitBlameView`, `modifiable=false`, `wrap=false`.
       4. Sync scroll: `vim.wo[source_win].scrollbind = true; vim.wo[blame_win].scrollbind = true`; on `WinScrolled` for source, mirror cursor line; on blame close, undo scrollbind.
       5. Stash blame_info per line on the blame buf via `vim.b[blame_buf].lines = result` (or a module-local map keyed by `blame_buf`).
     - Buffer-local keymaps inside `blame_buf`: `<CR>` → `show_commit(sha)` (opens a `Beast.View` float with `git show <sha>` output, filetype `git`); `r` → reblame `<sha>^` (recurse `open` with new revision, replace contents in-place); `R` → reset revision to nil + reblame; `q` / `<Esc>` → close.
     - Lifecycle: `BeastGitBlameView<id>` augroup; close triggers on `WinClosed` for either source or blame win, `BufWipeout` of source buf.
   - Why: Self-contained `Beast.View` subclass — same shape as `preview.lua` (`Beast.Git.PreviewView`), reuses scroll-bind primitives Vim already has.
   - Depends on: Phase 1 Step 3 (`blame.lua`), Step 1
   - Risk: Medium — scroll sync edge cases (folds, signcolumn width changes). Mitigated by reusing Vim's `scrollbind` rather than hand-rolling line-by-line sync.

3. **Wire into `init.lua`** (File: `lua/beast/libs/git/init.lua`)
   - Action: Add `M.blame(opts)` — `require("beast.libs.git.blame_view").open(api.nvim_get_current_win(), opts or {})`. Add `<leader>gB` → `M.blame` to the attach-path keymaps.
   - Why: Single entry point parity with `M.preview_hunk`.
   - Depends on: Phase 2 Step 2
   - Risk: Low

4. **Update codemap** (File: `docs/CODEMAPS/libraries.md`)
   - Action: Add `├── blame_view.lua` to the git tree; mention `<leader>gB` in the keymap line; note the `BeastGitBlameView<id>` augroup pattern.
   - Why: Codemap-freshness instruction.
   - Depends on: Phase 2 Step 2
   - Risk: Low

**Phase 2 checkpoint**: `<leader>gB` opens a left side window; scroll syncs; `r` reblames parent; `q` closes cleanly with no leaked autocmds (`:augroup` shows the group gone, `nvim_get_autocmds({ group = "BeastGitBlameView..." })` returns empty).

## Testing Strategy

- **Unit tests** (`tests/git/blame_spec.lua` — new file; the project's `tests/` is currently sparse, so this is also a small process improvement):
  - `blame.run` parser: 6 fixture cases — clean commit, NC synthetic, `boundary` tag, `previous <sha> <file>` propagation, `--contents` external-file commit normalization, multi-line block (size > 1).
  - Buffered line reader: 3 cases — single chunk, split mid-line, trailing partial line preserved across chunks.
  - Formatter: 4 cases — `"You"` substitution when `author == username`, NC formatter fork, `<author_time:%R>` relative-time edges (just now, 5m, 3h, 2d, 4mo, 1y), missing placeholder left literal.
- **Bench** (`scripts/bench-git-blame.lua` — Step 8 of Phase 1):
  - Single-line unmodified ≤ 30 ms median (cursor-move hot path).
  - Single-line modified (with `--contents`) ≤ 60 ms median (extra stdin write).
  - Full-file 5 k-line: report only, no hard threshold (on-demand).
- **Manual verification — Phase 1**:
  1. Open `lua/beast/libs/git/init.lua`, sit on line 50; within ~500 ms, see virt_text with author + relative date + summary.
  2. Move to a line you just edited (uncommitted): see `formatter_nc` rendering ("You" or similar NC marker).
  3. Enter insert mode: virt_text disappears. Leave insert: returns.
  4. Open a file outside any git repo (e.g. `/tmp/x.txt`): no virt_text, no errors.
  5. `<leader>gtb`: toggles off → text cleared from all buffers; toggle on → reappears on cursor move.
  6. `:checkhealth beast.libs.git`: `user.name` reported; per-buffer last-blame timing visible.
- **Manual verification — Phase 2**:
  1. `<leader>gB` in `init.lua`: left split opens with `<sha> <author> <date>` rows, scroll syncs.
  2. Move cursor in source buffer; cursor in blame stays aligned.
  3. `<CR>` on a blame line: commit diff float opens with `git show` output.
  4. `r`: blame replaced with parent commit's blame; `R`: returns to HEAD.
  5. `:q` source window: blame window closes cleanly; `nvim_get_autocmds({ group = ... })` empty.

## Risks & Mitigations

- **Risk**: `git blame --incremental` on huge files (50 k+ lines) is slow even with `-L` because git still reads the whole file index.
  → **Mitigation**: Phase 1 only ever uses `-L lnum,+1` for cursor blame; full-file is opt-in (Phase 2, on user demand). Bench reports full-file p95 so we know the practical ceiling.
- **Risk**: Parser drift when git changes porcelain output (git 2.41 added the `External file (--contents)` marker — gitsigns has a special case for it).
  → **Mitigation**: Mirror gitsigns' normalisation: if `author_mail == "<external.file>"` or `"External file (--contents)"`, force-merge with `NOT_COMMITTED` table. Covered by a unit test.
- **Risk**: Cursor-moved race — user moves cursor faster than `delay_ms`, we paint blame for a stale line.
  → **Mitigation**: Capture `start_lnum` before the async call; in the callback, if `current lnum ~= start_lnum`, recurse `update` for the new line (matches gitsigns `current_line_blame.lua:208-212`). Tested manually by holding `j`.
- **Risk**: Per-buffer debouncers leak across detach if not closed (`Util.debouncer` holds a `uv_timer`).
  → **Mitigation**: `teardown()` and the `M.detach` path both call `:close()` on the per-buffer debouncer; a module-local `WeakMap`-style table keyed by `bufnr` is the only storage.
- **Risk**: `config.lua`'s frozen metatable rejects direct assignment from `toggle_current_line_blame`.
  → **Mitigation**: Add a `config.set(path, value)` helper in Phase 1 Step 1 (one-liner that mutates the internal `cfg` table); document that toggles must use this helper, not raw assignment. Symmetric with how mini.* libs work.

## Success Criteria

- [x] Phase 1: cursor on any line in a tracked git file shows virt_text within `delay_ms`; insert-mode hides it; toggle works; bench `bench-git-blame.lua` reports single-line unmodified ≤ 80 ms median (threshold raised from 30 ms — see ADR-027; `vim.system` + git startup is ~40 ms floor on macOS, not parser overhead).
- [x] Phase 1: `:checkhealth beast.libs.git` is clean (or warns gracefully when `user.name` is unset).
- [x] Phase 1: detaching a buffer (via `M.detach` or `BufWipeout`) leaves zero extmarks in the `beast_git_blame` namespace and no live debouncer timers.
- [x] Phase 2: `<leader>gB` opens a synced side window; `r` / `R` / `<CR>` / `q` all work; closing source window closes blame cleanly with no leaked autocmds.
- [x] Codemap regenerated and committed with each phase (per `.github/instructions/codemap-freshness.instructions.md`).
- [x] gitsigns.nvim's `current_line_blame` and `blame` features can be disabled (or the plugin removed entirely) without UX regression.

## ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs once committed:

- **Blame data layer pattern** — streaming `git blame --incremental` via `vim.system` + coroutine line reader, in preference to either (a) waiting for full output, or (b) using gitsigns' async runtime. Decision rationale: streaming is the only way to keep single-line blame fast on large files while still using one consistent code path for both layers. References ADR-022 (native lib vs gitsigns.nvim) and ADR-023 (vim.text.diff backend) for the broader "go native over plugin" theme already established in this lib.
- **Phase 2 only**: introducing a new `Beast.View` subclass (`Beast.Git.BlameView`) that holds a long-lived window + scroll-bind contract — the second `Beast.View`-based long-lived UI in the lib after `preview.lua`'s short-lived float. ADR captures the scroll-bind choice over hand-rolled line sync.

## Completed

**2026-06-07** — Both phases shipped.

- Phase 1: 8 commits, latest `cedd63b`.
- Phase 2: single commit `2797ed2`.
- ADRs filed: [ADR-027](../ADRs/027-git-blame-data-layer-pattern.md) (data layer), [ADR-028](../ADRs/028-git-blame-side-window-beast-view.md) (Beast.View subclass + scrollbind).
- Implementation deviated from spec on streaming: chose buffered parse over coroutine line reader (see ADR-027 § *Decision*). Same correctness, ~half the LOC.
- Bench threshold raised 30 ms → 80 ms after measuring the `vim.system`+git process-startup floor on macOS.
