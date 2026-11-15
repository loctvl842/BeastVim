---
name: finder-pr-commits
description: Chain pull requests to the commits of the highlighted PR (each previewed as a diff), then to a grep in the files that commit changed
generated: 2026-11-15
---

# Summary
From the pull request list, one key opens the commits of the highlighted PR, with the diff of the highlighted commit on the right. From a commit, one key opens a grep that only looks inside the files that commit changed. Backspace steps back at every level.

---

# Problem

A pull request is often a series of commits, and reviewing it commit by commit is easier than reading one big diff. Today the finder can show a PR's combined changed files, but not its commits. To see what one commit did you leave the editor for GitHub, and to search inside the files that commit touched you have to remember their names and grep the whole project.

## Why now
The chain machinery (follow-up pickers, backspace to go back, grep scoped to a list of files) and the pull request picker already exist. Commits are the missing middle step between "a PR" and "the code it touched".

---

# Target Behavior

The chain, with `<C-g>` as the existing "go deeper" key. The PR list now has two ways down, so it needs a second key (see Open decisions):

```
Pull Requests ──<C-g>──> Files Changed ──<C-g>──> grep in those files     (exists today)
      │
      └─────<C-t>──> Commits of the PR ──<C-g>──> grep in the files that commit changed   (this spec)

<BS> (empty prompt) or <C-o> goes back one level at every step, nothing is searched again.
```

```
STATE 1 — Pull request list, the way down is shown under the picker:
┌─ Pull Requests - repo:o/n ─────────────────┐┌─ PR #12 ──────────────────────────────┐
│ > is:pr state:open █                  12/12││ Refactor the finder so every picker…  │
├────────────────────────────────────────────┤│ ...                                   │
│▌ #12  Refactor the finder so every pic…    ││                                       │
│  #11  Fix scrollbar flicker                ││                                       │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                              <C-g> files changed in #12   <C-t> commits in #12

─────────────────────────────────────────
STATE 2 — Commits of the highlighted PR, the diff of the highlighted commit on the right:
┌─ PR Refactor the finder so every pic… › Commits (4) ─┐┌─ 3f9a1c2  Add chain table ───────────┐
│ > █                                               4  ││ Loc <l@x.dev>  2 days ago            │
├──────────────────────────────────────────────────────┤│                                      │
│▌ 3f9a1c2  Add chain table          Loc  2 days ago   ││  lua/beast/libs/finder/chains.lua    │
│  b71e0d4  Wire <C-g> to the table  Loc  2 days ago   ││ @@ -0,0 +1,40 @@                    │
│  9c20aa8  Scoped grep              Loc  yesterday    ││ +local M = {}                        │
│  e04d5f7  Fix highlight leak       Loc  today        ││ +...                                 │
└──────────────────────────────────────────────────────┘└──────────────────────────────────────┘
                              <C-g> grep the 3 files changed in 3f9a1c2   <BS> back to Pull Requests

─────────────────────────────────────────
STATE 3 — Grep inside the files that commit changed (your local copies):
┌─ 3 Files in 3f9a1c2 › Live Grep ───────────┐┌─ chains.lua ──────────────────────────┐
│ > chain█                                   ││ ...                                   │
├────────────────────────────────────────────┤│                                       │
│  chains.lua  lua/beast/libs/finder         ││                                       │
│▌  1:3   --- The map of chains              ││                                       │
│   40:5  local function scope_files(what)   ││                                       │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                                                                  <BS> back to Commits
```

A commit row is: short id, the first line of the message, author, how long ago. Typing in the commits picker filters by any of these.

---

# Scenarios

## 1 — Happy path: PR, a commit, grep in its files

```
Step 1: open Pull Requests (<leader>ghp), move to #12
  The hint under the picker offers "<C-g> files changed in #12" and "<C-t> commits in #12".

Step 2: press <C-t>
  Title: "PR Refactor the finder so every pic… › Commits (4)". The 4 commits are listed,
  newest first. The first commit's diff is on the right.

Step 3: move to the third commit
  The right side shows that commit's message, its changed files and the diff of each.

Step 4: press <C-g>
  Title: "3 Files in 9c20aa8 › Live Grep". The prompt is empty; the list says
  "(type to search your local copies of the 3 files)".

Step 5: type "chain", move to a result, press <Enter>
  The picker closes and the file opens at that line.
```

## 2 — Going back

```
From grep: <BS> on an empty prompt (or <C-o>) -> the commits, same highlighted commit.
From commits: <BS> on an empty prompt (or <C-o>) -> the PR list, same search, same highlighted PR.
Nothing is fetched or searched again. <Esc> closes the whole chain.
```

## 3 — Filter the commits

```
In the commits picker type "scoped": only the commits whose message, id or author contain it remain
(fuzzy, like every other picker). The count reads "1/4". <C-g> then greps the files of the highlighted one.
```

## 4 — Open a commit's diff

```
In the commits picker press <Enter>: the picker closes and the whole commit (message, then the diff of
every file) opens in a read-only buffer.
```

## 5 — Commit changed files you do not have

```
The commit touched files that were later deleted or that are not in your checkout.
<C-g> keeps only the files that exist in your working tree. The count in the title is of those.
If none exist: nothing opens and a message says "None of these files exist in your working tree".
```

## 6 — A big pull request

```
A PR with more than 250 commits: GitHub only lists the first 250. The title ends "(250, partial)".
A commit that changed more than 300 files: the 300 first are scoped and shown, the title says "(partial)".
A file whose diff is too big or binary shows "(diff too large or binary)" in the preview.
```

## 7 — Errors and empty

```
No network, rate limit, or login expired: the list shows what happened ("GitHub could not list the
commits: ...") and nothing else. <C-t> on that message row does nothing but a short note.
A PR with one commit: the list has one row and works the same.
A merge commit with no files of its own: <C-g> says "Nothing to open from here".
```

---

# Behavior Rules

- `<C-t>` opens the commits only from the pull request list, on a real PR row (not a message row). `<C-g>` there still opens Files Changed.
- `<C-g>` in the commits picker greps the local copies of the files the highlighted commit changed. It never greps the commit's old content.
- The grep results are your current files, so a line number can differ from what the commit showed.
- The hint under the picker always shows the keys that work on the highlighted row, and "back to ..." below the first level.
- Titles: `PR <title, shortened with ...> › Commits (N)` and `N Files in <short id> › Live Grep`.
- Back goes to the level you came from, exactly as you left it (prompt, list, highlighted row); no new request to GitHub.
- Only the supported chains exist; an unsupported key press just shows "Nothing to open from here".

---

# Open decisions

1. **Key for commits.** The PR list already uses `<C-g>` for Files Changed. Recommended: `<C-t>` for commits (the hint line shows both). Alternative: `<C-g>` opens a small choice (Files changed / Commits).
2. **What "grep" searches after a commit.** Recommended: your local copies of the files the commit changed (jumpable results, same as after Files Changed). Alternative: only the changed lines of the commit's diff (results would open the diff, not your file).
3. **Order.** Decided: newest first (the latest commit on top). Alternative: oldest first, like GitHub's page.

---

# Success Criteria

- [ ] On a PR, `<C-t>` lists its commits (id, message, author, age) and the right side shows the highlighted commit's diff.
- [ ] Typing filters commits by message, id or author; the count shows matches over total.
- [ ] `<C-g>` on a commit opens a grep limited to the existing local copies of that commit's files; the title counts them.
- [ ] `<BS>` on an empty prompt and `<C-o>` go back one level at each step without any new request.
- [ ] `<Enter>` on a commit opens the full commit diff in a read-only buffer; `<Enter>` on a grep result opens the file at the line.
- [ ] Message rows, empty lists and "no local files" never open anything and say why.
- [ ] More than 250 commits, or more than 300 files in a commit, are cut with "(partial)" in the title.
- [ ] The hint under the picker shows `<C-g>` and `<C-t>` on a PR, `<C-g>` and `<BS> back` on a commit.

---

# Out of Scope

- Reviewing or commenting on a commit, checking a commit out, or cherry-picking it.
- Grepping the text of the diffs themselves (see Open decision 2).
- Comparing two commits, or commits of a branch that is not a pull request.
- Commits for Issues, or commits from Files / Buffers (no link between them).
