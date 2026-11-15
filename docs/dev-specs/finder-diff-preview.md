---
name: finder-diff-preview
description: Share one diff row renderer between the git hunk preview and the finder, dedupe the finder's raw patch handling, then draw Files Changed diffs as numbered, tinted, word-emphasized, wrapped rows
generated: 2026-11-16
---

> PM Spec: [docs/pm-specs/finder-diff-preview.md](../pm-specs/finder-diff-preview.md)

# Summary
The repo already has a rich diff renderer (the git hunk float) and four raw-text diff paths in the finder. Building the new look as a second renderer would duplicate the first. So the work starts with two behavior-preserving refactors: (1) lift the row renderer out of `git/preview.lua` into a shared `view/diff.lua` (rows to body, tints, changed words, number gutter, statuscolumn, window options), (2) give the finder one place that knows a file's patch, its summary line and the "(diff too large or binary)" placeholder, and one scratch-buffer opener. Only then does the finder draw diffs with the shared renderer. Syntax coloring is last.

---

# Context

## Problem
Today diffs are presented in five different ways with overlapping code:

| # | Where | How | Rich? |
|---|---|---|---|
| 1 | Finder preview of a file (`gh_pr_files.preview`, also used by `gh_commit_files`, `git_commit_files`) | raw patch text + a head line, `filetype=diff`, no wrap | no |
| 2 | Finder preview of a commit (`commit_preview.draw` / `build`) | raw summary + raw patch per file | no |
| 3 | Enter on a file (`action.open_diff`) | raw patch in a scratch buffer | no |
| 4 | Enter on a commit (`action.open_commit`) | `commit_preview.build` in a scratch buffer | no |
| 5 | Git hunk float (`git/preview.lua`, 803 lines) | rows with line numbers, tints, changed words, treesitter, statuscolumn gutter | yes |

(The review lib paints an agent's proposal inline in the live buffer; a different problem, not touched.)

Duplication found:
- **The renderer:** `git/preview.lua` owns `render_rows`, `apply_decorations`, `_statuscol`, `maybe_start_treesitter` and the float's gutter window options (`number`, `numberwidth`, `statuscolumn`, ...). The finder needs the same thing; copying it would make two. Its highlight groups (`BeastGitPreview*`) and word spans (`git/diff.word_spans`) are likewise locked inside the git lib.
- **The finder's patch handling, 3 times each:** `vim.split(patch, "\n")` (`gh_pr_files`, `commit_preview.build`, `action.open_diff`); the text "(diff too large or binary)" (same three places); a file's one-line summary as two formats (`head` in `gh_pr_files.preview`, `file_line` in `commit_preview`).
- **Scratch buffers:** `action.open_diff` and `action.open_commit` repeat ~12 lines (nofile, wipe, name collision delete, set name, lines, read-only, filetype, `m'`, set buf).
- **Preview-pane writes:** `gh_pr_files.preview` and `commit_preview.draw` repeat modifiable / set_lines / filetype / `loaded_file` / title / cursor.

### Solution
```
lua/beast/libs/view/diff.lua        shared: rows -> body/tints/words/gutter, paint, attach/detach window, statuscol
lua/beast/libs/view/highlights.lua  shared BeastViewDiff* groups (git and finder both use them)
git/preview.lua                     builds rows from buffer text, calls view/diff           (refactored)
finder/ui/diff.lua                  one place for a file's patch: summary, raw lines, placeholder,
                                    patch -> rows, draw into the preview pane / leave        (new)
finder/action.lua                   one scratch-buffer opener for Enter on a file and on a commit
```
After the refactors nothing looks different. Then the feature is a small adapter (patch to rows, draw, leave) on top of the shared renderer.

---

# Research

### Repo Search
- Searched for: `patch`, `filetype = "diff"`, `vim.text.diff`, `vim.diff`, `word_spans`, `@@`, `statuscolumn`, `BeastGitPreview`, `highlight_modules`, `View.win.wo` in `lua/beast`, plus `tests/`.
- Found:
  - Finder: `source/gh_pr_files.lua:81` `preview` (aliased by `gh_commit_files.lua:15`, `git_commit_files.lua:15`); `source/gh/commit_preview.lua` `build` (feeds both the pane and Enter's buffer), `file_line`, `draw`, `show`; `action.lua:88` `open_diff`, `:121` `open_commit` (near-identical scratch buffer setup); `finder/source/git/log.lua` parses `git show` into the same file/commit shapes as GitHub, so one preview path serves both.
  - Git: `git/preview.lua` `build_rows` (buffer text + hunks to rows, pairs the j-th removed with the j-th added line), `render_rows`, `apply_decorations` (range extmark + `hl_eol`, because `line_hl_group` paints over word backgrounds), `_statuscol` (reads a gutter table stashed in `vim.b[buf]`), `maybe_start_treesitter`, `open_float` window options; `git/diff.lua` `word_spans` (pure, `vim.text.diff` on tokens); `git/highlights.lua` the red/green blends. `BeastGitPreview*` groups are used only in `git/preview.lua` and `git/highlights.lua` (renaming is safe).
  - `hl_reload.lua` `highlight_modules` registry: a shared `view/highlights.lua` needs one line there.
  - `git/patch.lua` builds unified-zero patches (the opposite direction); nothing parses patch text today.
  - Tests that touch this: `tests/test-git-preview.lua` (uses `preview._test.render_rows/build_rows`), `tests/test-git-word-diff.lua` (`git.diff.word_spans`), the four finder preview tests (`test-finder-gh-pr-files`, `-gh-commit-files`, `-gh-commits`, `-git-commits`), `tests/helpers/finder.lua`, `tests/helpers/gh.lua`.
  - Existing inconsistency: each preview writer sets its own window options and nothing resets `wrap` after a markdown preview.
- Reuse opportunity: **Yes**, mostly - the whole renderer already exists. The work is moving it to a neutral place and making it serve two callers, not writing a second one.

### Built-in / Existing Lib Check
- Checked: `statuscolumn` with `v:virtnum` and `nvim_eval_statusline(..., { use_statuscol_lnum })` (Neovim >= 0.11 required by DEVELOPMENT.md), `vim.treesitter.get_string_parser`, `vim.filetype.match`, extmark `hl_group` + `hl_eol`.
- Found: wrapped lines call the statuscolumn once per screen row with `v:virtnum > 0`, so blanking numbers on continuation rows is one branch. A weak Lua table keyed by buffer replaces `vim.b[buf]` for the gutter (a `vim.b` read copies a Vimscript dict, once per screen row: fine for a hunk, bad for 3000 rows).
- Decision: **Reuse** (move the git renderer and word spans to `view/diff.lua`) + **Build** only the finder adapter (patch parser, draw/leave, syntax). No new dependency. `view/` is already the shared UI toolkit (`view/buf`, `view/win`), so it is the neutral home; the shared groups follow the `Beast<Lib>*` convention as `BeastViewDiff*`.

---

# Architecture Changes
- **New** `lua/beast/libs/view/diff.lua` - shared: `word_spans`, `pair`, `render`, `paint`, `clear`, `attach`, `detach`, `statuscol`.
- **New** `lua/beast/libs/view/highlights.lua` - `BeastViewDiff*` groups (Add, Delete, AddWord, DeleteWord, AddSign, DeleteSign, LineNr, Hunk, Gap, Head), moved from `git/highlights.lua`'s `PreviewAdd...` family; **Modified** `lua/beast/hl_reload.lua` - register it.
- **Modified** `lua/beast/libs/git/preview.lua` - uses `view/diff` (drops `render_rows`, `apply_decorations`, `_statuscol`, the gutter window options); keeps `build_rows`, float placement, close wiring. **Modified** `lua/beast/libs/git/diff.lua` - `word_spans` and its helpers move out; `compute_hunks` stays. **Modified** `lua/beast/libs/git/highlights.lua` - the diff-colored groups move out; blame, conflict and staged-badge groups stay.
- **New** `lua/beast/libs/finder/ui/diff.lua` - the finder's one place for a file's patch: `summary`, `raw_lines`, `parse`, `rows`, `draw`, `leave`, syntax (Phase 5).
- **Modified** `lua/beast/libs/finder/action.lua` - one local `open_scratch(win, name, lines)` for `open_diff` and `open_commit`; `open_diff` uses `diff.raw_lines`.
- **Modified** `lua/beast/libs/finder/source/gh_pr_files.lua`, `source/gh/commit_preview.lua`, `ui/preview.lua`, `source/gh/preview.lua` - see phases.
- **Tests** new `tests/test-view-diff.lua` (moved word-span cases + renderer), `tests/test-finder-diff.lua`; modified `test-git-preview.lua`, `test-git-word-diff.lua` (paths), the four finder preview tests (Phases 3-4).
- **Docs** `docs/CODEMAP/libraries.md` - regenerated with `/update-codemap`, not edited by hand.

### Shared row model

```
row = {
  kind  = "text" | "head" | "gap" | "hunk" | "code" | "note",
  text  = string,            -- the buffer line (code text WITHOUT the -/+ mark)
  old   = integer?, new = integer?,   -- line numbers (code rows only)
  sign  = "-" | "+" | " ",   -- code rows
  spans = integer[][]?,      -- changed-word byte ranges {s, e}, 0-based, end exclusive
  marks = { {s, e, group} }? -- extra highlights inside the line
}
render(rows, { columns = 1 | 2 }) -> { body, hls, spans, gutters, width }
```
`columns = 1` is the git float (the source line number and the mark); `columns = 2` is the finder (old and new). Wrapped screen rows (`v:virtnum > 0`) get a blank gutter in the row's tint. Non-code rows (head, gap, hunk, note) get a blank gutter in their own background.

Finder gaps (hidden unchanged lines) come from the hunk headers only. A hunk covers old lines from `first` = `old_start` (`old_start + 1` when it has no old lines: it sits after that line) for `old_count` lines; above the first hunk `first - 1`; between hunks `next.first - (prev.first + prev.old_count)`; nothing after the last one (the file length is not in a patch).

## Implementation Phases

## Phase 1: Shared renderer, git hunk preview migrated (refactor, nothing looks different)
1. **Baseline** (no file)
   - Action: run `tests/test-git-*.lua` and `tests/test-finder-*.lua`, note results; open the git hunk preview (`<leader>gp`-style, staged and unstaged, a changed-word line) and keep a screenshot to compare at the end of the phase.
   - Why: the refactor claims "no visible change"; this is what it is compared with.
   - Depends on: None
   - Risk: Low
2. **Shared highlights** (Files: `lua/beast/libs/view/highlights.lua` new, `lua/beast/hl_reload.lua`, `lua/beast/libs/git/highlights.lua`)
   - Action: move the Add / Delete / Word / Sign formulas to `BeastViewDiff*` (same blends over the same background), register the module, load it when `view/diff` is first required; `git/highlights.lua` keeps the groups that are about blame, conflicts and the staged badge. Add the finder-only ones (`LineNr`, `Hunk`, `Gap`, `Head`) here too so there is one family.
   - Why: one source of red/green for every diff.
   - Depends on: Step 1
   - Risk: Low (names are used only in `git/preview.lua`)
3. **`view/diff.lua`** (File: `lua/beast/libs/view/diff.lua`, new; `lua/beast/libs/git/diff.lua`)
   - Action: move `word_spans` and its tokenizer helpers from `git/diff.lua` (which keeps `compute_hunks`); move the j-th-with-j-th pairing into `pair(removed_rows, added_rows)`; move `render_rows` (generalized with `opts.columns`), `apply_decorations` (as `paint`, plus `clear`), `_statuscol` (as `statuscol`, reading a module-local weak table keyed by buffer instead of `vim.b`), and the gutter window options of `open_float` (as `attach(win, rendered)` / `detach(win)`).
   - Why: the renderer lives once, in a neutral place.
   - Depends on: Step 2
   - Risk: Medium (statuscolumn string registration, width calculation, extmark priorities must stay identical)
4. **Migrate the git float** (File: `lua/beast/libs/git/preview.lua`)
   - Action: call `view/diff` (`pair`, `render`, `paint`, `attach`); delete the moved functions; keep `build_rows`, placement, close wiring; `_test` exposes what the tests still need.
   - Why: proves the shared renderer by serving its original caller first.
   - Depends on: Step 3
   - Risk: Medium
5. **Tests** (Files: `tests/test-view-diff.lua` new, `tests/test-git-word-diff.lua`, `tests/test-git-preview.lua`)
   - Action: word-span cases now require `view/diff`; `render` tests move with it and add `columns = 2`, wrapped-row gutter (`virtnum`), blank gutter on non-code rows; git preview tests unchanged except the import. Re-run the baseline and the screenshot comparison; run `scripts/bench-git.lua` (the hunk preview is on its path).
   - Why: behavior preserved and the new capability (two columns) covered.
   - Depends on: Step 4
   - Risk: Low

## Phase 2: Finder dedupe (refactor, nothing looks different)
1. **One place for a file's patch** (File: `lua/beast/libs/finder/ui/diff.lua`, new)
   - Action: `summary(file)` returns the one-line "status +N -M (was X)" text (one format; `gh_pr_files.preview` and `commit_preview.file_line` both use it); `raw_lines(file)` returns the patch lines or the single placeholder line "(diff too large or binary)" (the only definition of that text); nothing else yet.
   - Why: removes the 3x `vim.split` + placeholder and the two summary formats before anything new is added.
   - Depends on: None
   - Risk: Low
2. **Use it** (Files: `lua/beast/libs/finder/source/gh_pr_files.lua`, `lua/beast/libs/finder/source/gh/commit_preview.lua`, `lua/beast/libs/finder/action.lua`)
   - Action: replace the inlined versions in `gh_pr_files.preview`, `commit_preview.build`/`file_line`, `action.open_diff`. Add `open_scratch(win, name, lines)` in `action.lua` and call it from `open_diff` and `open_commit`.
   - Why: one scratch-buffer opener and one source of the placeholder and summary.
   - Depends on: Step 1
   - Risk: Low (all four existing finder preview tests must pass unchanged: the output is identical)

## Phase 3: Draw Files Changed with the shared renderer (the feature)
1. **Patch to rows** (File: `lua/beast/libs/finder/ui/diff.lua`)
   - Action: `parse(patch)` -> hunks `{ old_start, old_count, new_start, new_count, context, lines = {{ kind = "ctx"|"del"|"add"|"note", text }} }` (a `\ No newline at end of file` line becomes a `note`; CRLF stripped). `rows(file)` -> shared rows: a `head` row (`summary` plus the 5/10-block +/- bar as `marks`), then per hunk an optional `gap` row, a `hunk` row (`▸ @@ -a,b +c,d @@ context`) and `code` rows with old/new numbers, `view/diff.pair` for word spans; no patch gives the head row and the placeholder as a `note` row; at most `MAX_ROWS = 3000` code rows then a `note` "(N more lines not shown)".
   - Why: all four STATES of the PM spec are decided here, with no window involved.
   - Depends on: Phase 2
   - Risk: Medium (header edge cases: `-0,0`, `+1,0`, omitted counts, `@@ -1 +1 @@`)
2. **draw / leave** (File: `lua/beast/libs/finder/ui/diff.lua`)
   - Action: `draw(view, rows, title)` writes the buffer, calls `view/diff.render` (`columns = 2`), `paint`, `attach`, then sets `wrap = true`, `filetype = ""`, the window title, cursor row 1, and marks the view. `leave(view)` is a no-op unless the view was drawn here; otherwise `view/diff.clear` + `detach`, `wrap = false`.
   - Why: the finder-specific part is only what differs from the git float (wrap on, a shared preview window that other writers reuse).
   - Depends on: Step 1
   - Risk: Medium (the same preview window is reused by other levels; width must not flicker between files)
3. **Wire Files Changed** (File: `lua/beast/libs/finder/source/gh_pr_files.lua`)
   - Action: `M.preview` draws via `ui/diff` (still `ui.preview.clear` for no item or a message row); the commit and local-commit Files Changed levels follow because they alias it. Enter unchanged.
   - Why: first visible change.
   - Depends on: Step 2
   - Risk: Low
4. **Release the window for other previews** (Files: `lua/beast/libs/finder/ui/preview.lua`, `lua/beast/libs/finder/source/gh/preview.lua`)
   - Action: `diff.leave(view)` at the top of `ui.preview.show`, `clear`, `draw_image` and `gh/preview.show`.
   - Why: going back to PRs, Files or a grep must not inherit the statuscolumn or wrapping.
   - Depends on: Step 2
   - Risk: Medium (a writer that forgets `leave` leaves a stale gutter)
5. **Tests** (Files: `tests/test-finder-diff.lua` new, `tests/test-finder-gh-pr-files.lua`, `tests/test-finder-gh-commit-files.lua`)
   - Action: pure `parse`/`rows` cases (two hunks with gap 13 and 19 above, pure add, pure delete, rename head, no patch, spans vs unrelated lines, over the cap, no-newline note, CRLF, header without counts); in the pickers: preview text without `+`/`-`, `filetype == ""`, gutter via `nvim_eval_statusline(use_statuscol_lnum)`, a wrapped row blank, `<BS>` back restores `statuscolumn`, `wrap`, `number`. Enter still opens a raw `diff` buffer.
   - Why: PM scenarios 1, 2, 5, 6, 9.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 4: The commit preview uses the same look
1. **Styled sections** (File: `lua/beast/libs/finder/source/gh/commit_preview.lua`)
   - Action: split the top of `build` (header, message, file list) into a local `summary(item, detail, failure)`; `build` stays `summary` + raw patches (Enter's buffer unchanged); `draw` builds `text` rows for the summary then, per file, a head row with the path and `diff.rows(file)`, and calls `ui/diff.draw`. Keep the `loaded_file` marker and stale-request guard; drop its own `wrap=false`.
   - Why: PM decision 3 (recommended): one look through the whole chain; gutter width over all files.
   - Depends on: Phase 3
   - Risk: Medium (early draw with `detail == nil` must still work)
2. **Tests** (Files: `tests/test-finder-gh-commits.lua`, `tests/test-finder-git-commits.lua`)
   - Action: new preview expectations; Enter's buffer still raw `diff`.
   - Why: PM scenario 7.
   - Depends on: Step 1
   - Risk: Low

## Phase 5: Syntax coloring (PM decision 2)
1. **Per-side treesitter** (File: `lua/beast/libs/finder/ui/diff.lua`)
   - Action: when `vim.filetype.match({ filename = file })` has a parser and `highlights` query, parse each hunk's old side (context + removed) and new side (context + added) separately with `get_string_parser`; add foreground-only capture extmarks (priority below the tint and word marks, split per row for multi-line nodes) through the shared `paint`. Skip on too many rows, long lines, no parser or any error (`pcall`).
   - Why: a mixed old/new buffer would not parse; the git float keeps its whole-buffer parse until someone wants to change it.
   - Depends on: Phase 3
   - Risk: Medium (cost on big files; fragments that start mid-construct)
2. **Tests** (File: `tests/test-finder-diff.lua`)
   - Action: a Lua hunk gets captures on code rows only; unknown extension and oversized file draw plain; time a 3000-row draw.
   - Why: keeps highlighting from slowing cursor movement.
   - Depends on: Step 1
   - Risk: Low

# Testing Strategy
- Headless (each: `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/<file>`): `tests/test-view-diff.lua` and `test-finder-diff.lua` (new), `test-git-preview.lua`, `test-git-word-diff.lua` and the rest of `tests/test-git-*.lua`, the four finder preview tests, and all of `tests/test-finder-*.lua`, after every phase.
- Type check and style: `lua-language-server --check . --checklevel=Warning` (as in DEVELOPMENT.md), `stylua`.
- Bench: Phase 1 touches the git hunk preview, so run `scripts/bench-git.lua` before and after; run `./scripts/bench-ux.sh all` (extmark and window-option change) before merging Phases 1, 3 and 5. No preview-pane component bench exists; time `draw` on 3000 rows in `test-finder-diff.lua`.
- Manual: Phase 1: the git hunk preview looks and behaves as in the baseline screenshot (staged badge, changed words, gutter, `q`/`<Esc>`). Phases 3-5: PM scenarios 1 to 9 with a real PR; hold `<Down>` (no width flicker), resize with a long line open, `<BS>` to PRs and to a grep (no leftover gutter or tint), `:colorscheme` light and dark, deleted and binary files. Pixel-level check of gutter alignment and tint continuity across wrapped rows.

# Success Criteria
- [x] After Phases 1-2 nothing looks different: git hunk preview identical to the baseline, finder previews and Enter buffers unchanged, all tests green.
- [x] One implementation of rows-to-buffer, word spans, tints and gutter (`view/diff.lua`), used by the git float and the finder; one source of red/green groups.
- [x] One definition of the "(diff too large or binary)" text, of a file's summary line, of splitting a patch, and of opening a scratch diff buffer in the finder.
- [x] Highlighting a file shows the header (status, +N -M, bar) and the diff with old and new line numbers.
- [x] Removed lines are red and added lines green across the whole row; context is neutral.
- [x] On an edited line, only the changed words get the stronger shade.
- [x] A long line wraps with empty number columns and keeps its color; nothing is cut at the edge.
- [x] Gaps show "N unchanged lines"; numbers stay correct across them.
- [x] Added, deleted, renamed, binary and too-large files render as in STATES 3 and 4.
- [x] A commit's preview draws each file's diff in the same style.
- [x] Changing the colorscheme recolors the diff correctly, dark and light (finder and git).
- [x] Moving through files is as fast as before; the diff always starts at the top.
- [x] `<Enter>`, `<BS>`, `<C-o>` and `<C-g>` behave exactly as before; Enter still opens the raw diff.
- [x] Code is colored for the file's language (PM decision 2), never breaking the red/green or word backgrounds.
- [x] After leaving a diff (back, other level, close), the preview pane shows no gutter and file previews have line numbers again.
- [x] `tests/test-git-*.lua`, `tests/test-finder-*.lua`, the type check, `bench-git.lua` and `bench-ux.sh all` are green/healthy.

# Notes for review
- **PM spec gap (scenario 8):** the PM spec says the finder keeps its own colors while open. In the code only the prompt and list panels are frozen (`highlights.freeze`); the preview pane uses global groups, so the diff recolors with `:colorscheme`. This plan implements "recolors"; the second sentence of scenario 8 should be dropped from the PM spec.
- **Scope:** Phases 1-2 are refactors requested before new features. Out of scope: the review lib's inline overlay, `git/patch.lua`, and moving the git float to the finder's per-side syntax parse.
- **Decision (recommended):** the shared renderer lives in `libs/view/` with `BeastViewDiff*` groups. Alternative: `util/diff.lua`; rejected because it also owns buffer painting and window options, which is what `view/` is for.

## Completed

2026-11-16 - all five phases: shared renderer, finder dedupe, Files Changed diff, commit preview, syntax coloring.

- `e10881e` refactor(view): move the git hunk preview renderer to a shared view/diff
- `8fce4e2` refactor(finder): one place for a file's patch, its summary line and the scratch diff buffer
- `5b6dc7f` feat(view): diff rows can be plain bands, carry extra marks and wrap; attach restores the window (also the `detach` restore the Phase 1 review asked for)
- `ccda1b0` feat(finder): files changed are previewed as a numbered, tinted diff with the changed words marked
- `ee5cf21` feat(finder): the preview of a commit draws each file's diff like files changed
- `b963409` feat(finder): the code of a diff is colored for the language of its file

Deviations from the plan: `attach(win, width)` instead of `attach(win, rendered)`; the shared highlights are applied from the git and finder `setup` (not on first require, `Util` is not global in the bare test env); `attach` saves the window's options and `detach` restores exactly those; the finder-only groups (Head, Hunk, Gap, StatAdd/StatDelete) were added in Phase 3 when first used; `Beast.Finder.Diff.File` is a type alias of the two file shapes.

Verification: `tests/test-git-*`, `test-finder-*`, `test-view-diff` (45 checks), `test-finder-diff` (33 checks): 38 files, 0 failing; `lua-language-server --check` no problems; `stylua --check` clean; `bench-git.lua` PASS (words200 2.3 ms, same as before); `bench-ux.sh all` keypress, scroll, bufswitch, extmarks, keymaps all PASS; coloring 2000 rows about 32 ms (cap is 1500 rows). Checked in a real terminal: gutter alignment, tint continuity across wrapped rows, changed-word backgrounds and syntax foreground together.
