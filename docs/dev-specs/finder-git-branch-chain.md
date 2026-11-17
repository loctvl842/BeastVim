---
name: finder-git-branch-chain
description: A local branch picker (git_branches) with chain edges to the branch's files changed, its commits and a grep, built on the existing local-commit sources
generated: 2026-11-17
---

> PM Spec: [docs/pm-specs/finder-git-branch-chain.md](../pm-specs/finder-git-branch-chain.md)

# Summary
Add one new picker source, `git_branches`, and one new level source, `git_branch_files`, and wire three chain edges: `git_branches|git_branch_files` (`<C-g>`), `git_branches|git_commits` (`<C-t>`) and `git_branch_files|live_grep` (`<C-g>`). Everything past the branch level (commits, a commit's files, the grep) reuses the local-commit sources. The new git reads (branch list, merge-base, branch diff, commit range) go into `source/git/log.lua`, in the same shapes the commit sources already consume.

---

# Context

## Problem
The finder can chain local commits to their files and then to a grep (`git_commits` > `git_commit_files` > `live_grep`), but nothing starts from a branch: there is no branch list, no way to ask "what did this branch change against main", and `git_commits` can only show the whole history, not the commits of one branch.

### Solution
`git_branches` lists local branches as commit-like items (the tip commit fields plus `name`/`current`). Its `<C-t>` edge opens `git_commits` with `ctx.branch`, which then lists the range `merge-base..branch` (or the latest 500 when the branch has nothing of its own). Its `<C-g>` edge is a waiting edge: it resolves the merge-base, then opens `git_branch_files`, which lists `git diff merge-base tip` through the same row builder as `git_commit_files`. A commit-shaped item with `base` set lets `commit_preview.detail` serve both a commit and a branch diff, so previews, caching and Enter keep working unchanged.

---

# Research

## Research

### Repo Search
- Searched for: `git_commits`, `git_commit_files`, `commit_preview`, `chains.lua` edges, `scope_local_copies`, `for-each-ref`, `merge-base`, `branch` in `lua/beast/libs/finder`, `lua/beast/libs/git`, `lua/beast/init.lua`, `tests/`, `docs/`.
- Found:
  - `source/git_commits.lua`, `source/git_commit_files.lua`, `source/git/log.lua` (`commits`, `show`, `parse_show`): the whole local-commit pipeline, async `git` runner (`git(cwd, args, cb)`), error shape `Beast.Finder.Gh.Error`, `LIMIT = 500`, `MAX_FILES = 300`.
  - `source/gh/commit_preview.lua`: `detail(item, cb)` dispatches `git show` for a local item (no `item.pr`), caches by `repo@sha`; `show(view, item)` is the preview hook.
  - `chains.lua`: waiting edges (`open` returns a `function(resume)`), `commit_files(source)`, `scope_local_copies`, `grep_local_copies`.
  - `format.lua`: `gh_commit` row, `commit_label`, `commit_trail`.
  - Existing key `<leader>gc` opens `git_commits` (`lua/beast/init.lua:395`); `<leader>gb` (blame line) and `<leader>gB` (blame file) are taken.
  - No branch listing, `for-each-ref`, `merge-base` or branch-diff code anywhere.
  - Tests to mirror: `tests/test-finder-git-commits.lua` (real temp repo, real picker), `tests/test-finder-chain.lua` (closed edge map), `tests/test-finder-chain-config.lua` (default edge list).
- Reuse opportunity: Yes. The commit row, preview, Enter action, files row builder, local-copies grep and the git runner are all reused; only the branch reads and the edges are new.

### Built-in / Existing Lib Check
- Checked: `git for-each-ref`, `git merge-base`, `git log A..B`, `git diff A B` (all in `git`, already required by the local-commit sources); `vim.system` (already used); `Beast.Finder` chain/source registry.
- Found: `git diff --raw --numstat --patch` prints the same three parts that `parse_show` already parses (it only skips the `--format=` header, which `diff` does not print), so no new parser is needed.
- Decision: **Reuse** the commit pipeline, **Build** only the branch reads, one source, one preview, three edges.

---

# Architecture Changes

- `lua/beast/libs/finder/source/git/log.lua` (modified): add `branches(cwd, cb)`, `default_name(branches)`, `base(cwd, branch, default, cb)`, `diff(cwd, base, tip, cb)`; give `commits(cwd, cb, rev?)` an optional revision argument; share the file truncation tail between `show` and `diff`.
- `lua/beast/libs/finder/source/git_branches.lua` (new): the branch list, match source, title, Enter opens the tip commit.
- `lua/beast/libs/finder/source/git/branch_preview.lua` (new): the preview pane of a branch (the commits it has over the default branch).
- `lua/beast/libs/finder/source/git_branch_files.lua` (new): files a branch changed; shares the list with `git_commit_files`.
- `lua/beast/libs/finder/source/git_commit_files.lua` (modified): split `get` into `M.list(filter, owner, cb)` so the branch source reuses it; behaviour unchanged.
- `lua/beast/libs/finder/source/git_commits.lua` (modified): honour `filter.ctx.branch` (range or history, title `<name> › Commits (N)`).
- `lua/beast/libs/finder/source/gh/commit_preview.lua` (modified): `item.base` makes `detail` run `log.diff(base, sha)` and is part of the cache key.
- `lua/beast/libs/finder/format.lua` (modified): add `git_branch(item)` row.
- `lua/beast/libs/finder/chains.lua` (modified): three edges, hints, `scope_local_copies` titled for a branch.
- `lua/beast/libs/finder/source/init.lua`, `lua/beast/libs/finder/query.lua` (modified): `Beast.Finder.Source` alias gains the two sources; `ctx` annotation gains `branch` and `default`; item annotation gains `name`/`current`.
- `lua/beast/init.lua` (modified): key `<leader>gr` opens `git_branches`.
- `tests/test-finder-git-branches.lua` (new), `tests/test-finder-chain.lua`, `tests/test-finder-chain-config.lua` (modified).
- `lua/beast/libs/finder/docs/chains.md`, `docs/CODEMAP/libraries.md` (modified): the new edges and files.

## Implementation Phases

## Phase 1: Git reads — branches, base, branch diff, commit range
Mergeable alone; nothing in the UI changes.

1. **Branch list** (File: `lua/beast/libs/finder/source/git/log.lua`)
   - Action: `M.branches(cwd, cb)` runs `git for-each-ref --sort=-committerdate --format=<fields> refs/heads` with the `%(HEAD)` marker, `refname:short`, `objectname`, `authorname`, `authordate:iso-strict`, `contents`, joined by the existing `FIELD`/`RECORD` bytes. Parse into commit-shaped tables (`sha`, `short`, `subject`, `message`, `author`, `date`) plus `name`, `current`. The current branch moves to the front, the rest stay newest first. Errors come back as `{ error = failure(res) }`.
   - Why: PM "Target Behavior" STATE 1, scenario 1.
   - Depends on: None
   - Risk: Low
2. **Default branch and base** (File: same)
   - Action: `M.default_name(branches)` returns `"main"`, else `"master"`, else nil (pure, over the list). `M.base(cwd, branch, default, cb)` calls back with the merge-base sha, or nil when there is no default, the branch is the default, or the merge-base equals the branch tip (no changes of its own). Uses `git merge-base refs/heads/<default> refs/heads/<name>`; a failing merge-base (unrelated histories) also calls back nil.
   - Why: PM Behavior Rules ("against main"), scenario 4.
   - Depends on: Step 1
   - Risk: Medium (unrelated histories, detached HEAD, `main` missing)
3. **Commit range** (File: same)
   - Action: `M.commits(cwd, cb, rev?)`: `rev` is appended to `git log` (`"base..refs/heads/x"` or `"refs/heads/x"`); nil keeps today's `HEAD` behaviour. Always pass fully qualified refs so a tag with the same name cannot win.
   - Why: PM scenarios 2 and 4.
   - Depends on: None
   - Risk: Low
4. **Branch diff** (File: same)
   - Action: `M.diff(cwd, base, tip, cb)` runs `git diff -M --raw --numstat --patch --relative <base> <tip>`, parses with `parse_show`, truncates at `MAX_FILES` and calls back `{ detail = { message = "", files, truncated } }`. Extract the shared parse-and-truncate tail of `show` into a local used by both.
   - Why: PM scenario 1, 5, 7 (300-file cap).
   - Depends on: None
   - Risk: Low
5. **Test the reads** (File: `tests/test-finder-git-branches.lua`, new)
   - Action: temp repo with `main` (2 commits) and `feat/x` (2 commits, one adds, one modifies, one deletes a file) plus an `old` branch at main's tip. Assert: branch order (current first, then newest), `default_name`, `base` (sha for feat/x, nil for main and for `old`), `commits` with a range (2 commits) and without (history), `diff` (statuses A/M/D, patch starts at `@@`).
   - Why: the data layer is the part everything else trusts.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 2: The branch picker
Mergeable alone: `<leader>gr` lists branches, previews them, Enter opens the tip commit; no chain keys yet (the hint line is empty).

1. **Row format** (File: `lua/beast/libs/finder/format.lua`)
   - Action: `M.git_branch(item)`: `●` (or two spaces) for the current branch, the name, the tip subject, author and age right-aligned. Item text is `"<name> <subject> <author>"` and each part carries its `src` range so match highlights land on the right columns (same approach as `gh_commit`). Message rows as in `gh_commit`.
   - Why: PM STATE 1.
   - Depends on: None
   - Risk: Low
2. **Preview** (File: `lua/beast/libs/finder/source/git/branch_preview.lua`, new)
   - Action: `show(view, item)` draws `"<N> commits ahead of <default>"` (or `"latest commits"` when there is no base) and one `<short>  <subject>` line per commit through `ui/diff`'s `plain` rows and `diff.draw`, setting `view.loaded_file` to a `git-branch:` marker. Same request-cancel and stale-answer guard as `commit_preview.show` (`states` weak table, `req` identity). Answers cached per `cwd@name@sha` (bounded like `commit_preview`).
   - Why: PM STATE 1 right pane.
   - Depends on: Phase 1
   - Risk: Medium (stale answers when moving fast; mirror the existing guard exactly)
3. **The source** (File: `lua/beast/libs/finder/source/git_branches.lua`, new)
   - Action: `live=false, async=true, auto_select=false, keep_order=true, count=format.ratio, format=format.git_branch, preview=branch_preview.show`. `get` calls `log.branches`, sets `filter.ctx.default = log.default_name(branches)`, emits items (`idx`, `score=0`, `text`, `cwd`, `name`, `current`, plus `sha/short/subject/body/author/date`). Error row `"git could not list the branches:"` + message; a stderr containing `not a git repository` shows the single row `"Not a git repository"`; empty list `"No branches"`. `title` is `"Git Branches (N)"`. `open` is `action.open_commit` (the tip commit, read-only; never checks out).
   - Why: PM scenarios 6 and 7.
   - Depends on: Steps 1-2, Phase 1
   - Risk: Low
4. **Wire the source and key** (Files: `lua/beast/libs/finder/source/init.lua`, `lua/beast/libs/finder/query.lua`, `lua/beast/init.lua`)
   - Action: add `"git_branches"` and `"git_branch_files"` to the `Beast.Finder.Source` alias; annotate `name`, `current` on items and `branch`, `default` on `ctx`; add `{ "<leader>gr", ..., desc = "Git branches" }` after `<leader>gc` (`<leader>gb`/`<leader>gB` are the blame keys).
   - Why: `<leader>gb` from the PM spec is taken; see Decisions.
   - Depends on: Step 3
   - Risk: Low
5. **Test the picker** (File: `tests/test-finder-git-branches.lua`)
   - Action: open `git_branches` over the temp repo: title `Git Branches (3)`, current branch first and marked, filter by subject, preview shows the commits, Enter opens the tip commit buffer and `HEAD` is unchanged, a non-repo directory shows `Not a git repository`.
   - Why: PM scenarios 6, 7.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 3: The chain
Mergeable alone once Phase 2 is in: this is the feature.

1. **Branch diff in the commit preview** (File: `lua/beast/libs/finder/source/gh/commit_preview.lua`)
   - Action: when `item.base` is set, `detail` calls `log.diff(item.cwd, item.base, item.sha, answer)`; `key(item)` becomes `repo@[base..]sha` so a branch diff never collides with the tip commit's own cache entry.
   - Why: lets `git_branch_files` reuse the commit list/preview/open unchanged.
   - Depends on: Phase 1
   - Risk: Medium (cache key change touches every commit preview; existing tests cover it)
2. **Shared files list** (File: `lua/beast/libs/finder/source/git_commit_files.lua`)
   - Action: move the body of `get` into `M.list(filter, owner, cb)` (owner = the commit item or the branch item); `get` becomes `M.list(filter, filter.ctx.commit, cb)`. Items keep `commit = owner` so `pr_files.preview` and `open_diff` work as today.
   - Why: no duplicated row builder.
   - Depends on: Step 1
   - Risk: Low
3. **Files of a branch** (File: `lua/beast/libs/finder/source/git_branch_files.lua`, new)
   - Action: same flags as `git_commit_files`; `get = list(filter, filter.ctx.branch, cb)` (the branch item carries `base`); `preview`/`open` reused; `title` `"<name> › Files Changed (N[, partial])"`; row `"Nothing changed"` is not needed (the edge refuses to open an empty branch).
   - Why: PM STATE 2.
   - Depends on: Steps 1-2
   - Risk: Low
4. **Commits of a branch** (File: `lua/beast/libs/finder/source/git_commits.lua`)
   - Action: with `filter.ctx.branch`, resolve `log.base(cwd, branch, filter.ctx.branch_default, ...)` then call `log.commits(cwd, cb, rev)` with `rev = base .. ".." .. ref` or just `ref` (`ref = "refs/heads/" .. name`). Without a branch behaviour is unchanged. `title` becomes `"<name> › Commits (N)"` for a branch, keeping the `latest only` suffix.
   - Why: PM STATE 3, scenarios 2 and 4.
   - Depends on: Phase 1
   - Risk: Medium (the default name must reach the source: the edge copies `ctx.filter.ctx.default` into the new level's ctx as `branch_default`)
5. **Edges** (File: `lua/beast/libs/finder/chains.lua`)
   - Action:
     - `git_branches|git_branch_files` (`<C-g>`, crumb `Git Branches`): hint `"files changed in <name>"`; `open` returns `function(resume)` that calls `log.base`; nil base resumes the string `"Nothing changed on this branch against <default>"` (or `"No main or master branch to compare against"` when there is no default); otherwise resumes `{ ctx = { branch = vim.tbl_extend("force", item, { base = base }) }, title = git_branch_files.title(...) }`. Returns the request handle so a pop/close kills it (as `scope_commit_files` does).
     - `git_branches|git_commits` (`<C-t>`, crumb `Git Branches`): hint `"commits in <name>"`; `open` returns `{ ctx = { branch = item, branch_default = default }, title = git_commits.title(...) }`.
     - `git_branch_files|live_grep` (`<C-g>`, crumb `Files Changed`): `hint = grep_local_copies`, `open = scope_local_copies`.
     - `scope_local_copies`: read `ctx.filter.ctx.branch` besides `commit`; for a branch the title is `"<name> › <N> Files › Live Grep"` (the existing pattern, see Decisions) and `ctx.commit` stays nil.
   - Why: PM chain and scenarios 1-5.
   - Depends on: Steps 1-4
   - Risk: Medium (`scope_local_copies` ctx contract; check how `ctx.local_copies`/`ctx.commit` are consumed in `live_grep` before changing)
6. **Tests** (Files: `tests/test-finder-git-branches.lua`, `tests/test-finder-chain.lua`, `tests/test-finder-chain-config.lua`)
   - Action: chain test over the temp repo: `<C-g>` files (title, 3 rows, status letters), `<C-g>` grep (deleted file left out), `<BS>` back, `<C-t>` commits (2 rows, newest first), commit `<C-g>` files, `<C-g>` grep, back x3; on `main`: `<C-g>` shows the "Nothing changed" message and stays, `<C-t>` lists history; hints. Extend `valid` in `test-finder-chain.lua` with the three new pairs and the expected list in `test-finder-chain-config.lua`; the "all use `<C-g>`" predicate gains the `git_branches|git_commits` `<C-t>` exception.
   - Why: the closed edge map must name exactly what exists.
   - Depends on: Step 5
   - Risk: Low

## Phase 4: Docs
1. **Chains doc and codemap** (Files: `lua/beast/libs/finder/docs/chains.md`, `docs/CODEMAP/libraries.md`)
   - Action: add the three edges to the edge table in `chains.md` (`git_branches|git_branch_files` `<C-g>`, `git_branches|git_commits` `<C-t>`, `git_branch_files|live_grep` `<C-g>`, entry `<leader>gr`); add the new files and edges to the finder tree in the codemap and the `Sources:` line. Leave `CHANGELOG.md` alone.
   - Why: the repo keeps the codemap and the chain table current with each lib change.
   - Depends on: Phase 3
   - Risk: Low

---

# Decisions to confirm

1. **Key for the branch list: `<leader>gr`** (Recommended). The PM spec proposed `<leader>gb`, but it is the existing "Blame current line" key and `<leader>gB` is "Blame file". The PM spec is updated to match.
2. **Titles after a branch.** The PM spec writes `3 Files in <name> › Live Grep`; the existing local-commit grep reads `<commit> › 3 Files › Live Grep`. Recommended: follow the existing pattern (`<name> › 3 Files › Live Grep`) so every chain reads the same. Alternative: change both.
3. **No main or master.** With neither `main` nor `master`, `<C-t>` lists the branch's whole history and `<C-g>` says `"No main or master branch to compare against"`.

---

# Testing Strategy

- Headless tests: new `tests/test-finder-git-branches.lua` (git reads, picker, full chain over a real temp repo); updated `tests/test-finder-chain.lua`, `tests/test-finder-chain-config.lua`; the existing `tests/test-finder-git-commits.lua`, `tests/test-finder-gh-commits.lua`, `tests/test-finder-chain-commit-grep.lua`, `tests/test-finder-source-contract.lua` must keep passing (cache key and `git_commit_files` refactor). Run each with `nvim --clean --headless -l tests/<file>.lua`.
- Bench: no hot-path lib is touched (matcher, extmarks, scroll); run the loop `for f in scripts/bench-*.lua; do nvim --clean --headless -l "$f" || echo "FAIL: $f"; done` once as a sanity check. Type check with `lua-language-server --check . --checklevel=Warning` (see DEVELOPMENT.md).
- Manual (PM spec scenarios, `NVIM_APPNAME=BeastVim nvim` inside a repo with a feature branch): scenario 1 (branch > files > grep), 2 (branch > commit > files > grep), 3 (back at each level restores prompt and highlighted row), 4 (on `main`: `<C-g>` message, `<C-t>` history), 5 (a file the branch deleted is listed `D` but left out of the grep), 6 (`<Enter>` on a branch never changes `HEAD`), 7 (outside a repo: `Not a git repository`). Check pixel details: current-branch marker alignment, right-aligned author/age, title shortening, hint line text.

# Success Criteria

- [x] `<leader>gr` lists local branches (current first, marked), each with its latest commit line, author and age; typing filters them.
- [x] On a branch, `<C-g>` lists the files it changed against the default branch with status letters, the highlighted file's diff on the right.
- [x] On a branch, `<C-t>` lists its commits newest first (only those not on main), the highlighted commit's diff on the right.
- [x] On a commit (from a branch or from `<leader>gc`), `<C-g>` lists the files that commit changed.
- [x] On a list of changed files, `<C-g>` greps the existing local copies; the title counts them.
- [x] `<BS>` on an empty prompt and `<C-o>` go back one level without searching again, restoring prompt and highlighted row.
- [x] A branch with no changes of its own says so on `<C-g>`, still lists history on `<C-t>`.
- [x] Message rows, empty lists and "no local files" never open anything and say why.
- [x] The hint shows `<C-g>` and `<C-t>` on a branch, `<C-g>` and `<BS> back` elsewhere.
- [x] `<Enter>` on a branch never changes the checked-out branch.
- [x] All finder headless tests, the bench loop and the type check pass.

---

# Completed

2026-11-17. Phase 1 git reads (`log.lua`), Phase 2 branch picker, Phase 3 chain (3 edges, shared files list, branch diff in the commit preview), Phase 4 docs.

- `50acac0` feat(finder): git reads for branches, merge-base, branch diff and commit ranges
- `fbfe590` feat(finder): git branches picker with commit preview, opened with <leader>gr (the key collided with Reset hunk; fixed in the next commit)
- `2f568f2` feat(finder): chain git branches to files changed, commits and grep; branches on <leader>gb, blame on <leader>gl/gL (also: `move_cursor` refreshes the hint line so it names the highlighted row; `log.base` typed for items; `refname:lstrip=2`)
- `836e62d` fix(bench): statuscolumn bench defines the Util global hl_reload needs (pre-existing failure)

Deviations from this spec: branch items carry `default` (main, else master) instead of `ctx.default`/`branch_default`; keys are `<leader>gb` (branches) and `<leader>gl`/`<leader>gL` (blame, moved by the user's choice) instead of `<leader>gr`; the grep title follows the existing `<name> › N Files › Live Grep` pattern.

Verified: `test-finder-git-branches` 52/0, every `tests/test-finder-*.lua` passes, stylua clean, lua-language-server clean, bench loop ok (`bench-grep-ab` is a manual A/B bench needing `BENCH_ROOT`, not run).
