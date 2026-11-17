---
name: finder-git-branch-chain
description: A local git branch picker that chains to the branch's commits and to the files it changed, then to a grep in those files
generated: 2026-11-17
---

# Summary
A list of your local branches. From a branch, one key opens the files it changed and another opens its commits; from a commit, one key opens the files that commit changed; from any list of changed files, one key opens a grep limited to those files. Backspace steps back at every level.

---

# Problem

To review what a branch does you leave the editor: run git commands to see which files it touched, which commits it holds, and what each commit changed. Searching inside just those files means remembering their names and grepping the whole project. The finder already does this for pull requests and for the commit history, but there is no way in from a branch.

## Why now
Local commits already chain to their files and then to a grep, and pull requests chain the same way. A branch is the missing starting point for work that has no pull request yet (or that you do not want to push to look at).

---

# Target Behavior

The chain. `<C-g>` is the "go deeper" key, `<C-t>` is the "commits" key (as on pull requests). The two boxes marked "new" are what this spec adds; the rest exists today:

```
Git Branches ──<C-g>──> Files Changed ──<C-g>──> grep in those files        (new, new, exists)
     │
     └───────<C-t>──> Commits ──<C-g>──> Files Changed ──<C-g>──> grep      (new, exists, exists)

<BS> (empty prompt) or <C-o> goes back one level at every step, nothing is searched again.
```

```
STATE 1 — Branch list, the ways down are shown under the picker:
┌─ Git Branches (4) ─────────────────────────┐┌─ feat/chain-keys ─────────────────────┐
│ > █                                    4   ││ 3 commits ahead of main               │
├────────────────────────────────────────────┤│                                       │
│▌ feat/chain-keys   Wire keys   Loc  today  ││ 9c20aa8  Scoped grep                  │
│  fix/scrollbar     Flicker     Loc  3 days ││ b71e0d4  Wire <C-g> to the table      │
│  main            ● Merge #11   Loc  5 days ││ 3f9a1c2  Add chain table              │
│  old/spike         Try thing   Loc  3 weeks││                                       │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                    <C-g> files changed in feat/chain-keys   <C-t> commits in feat/chain-keys

─────────────────────────────────────────
STATE 2 — <C-g>: the files the branch changed (against where it left main), diff on the right:
┌─ feat/chain-keys › Files Changed (3) ──────┐┌─ chains.lua ──────────────────────────┐
│ > █                                    3   ││ @@ -0,0 +1,40 @@                     │
├────────────────────────────────────────────┤│ +local M = {}                         │
│▌ M chains.lua    lua/beast/libs/finder     ││ +...                                  │
│  M keymaps.lua   lua/beast/libs/finder     ││                                       │
│  A branches.lua  lua/beast/libs/finder     ││                                       │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                  <C-g> grep these 3 files   <BS> back to Git Branches

─────────────────────────────────────────
STATE 3 — <C-t> from STATE 1: the commits of the branch, newest first:
┌─ feat/chain-keys › Commits (3) ────────────┐┌─ 9c20aa8  Scoped grep ────────────────┐
│ > █                                    3   ││ Loc <l@x.dev>  today                  │
├────────────────────────────────────────────┤│                                       │
│▌ 9c20aa8  Scoped grep          Loc  today  ││  lua/beast/libs/finder/chains.lua     │
│  b71e0d4  Wire <C-g> to the…   Loc  today  ││ @@ -10,3 +10,4 @@                     │
│  3f9a1c2  Add chain table      Loc  today  ││ +...                                  │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                  <C-g> files changed in 9c20aa8   <BS> back to Git Branches

─────────────────────────────────────────
STATE 4 — <C-g> from a commit: only that commit's files; <C-g> again greps them (STATE 5):
┌─ 9c20aa8 Scoped grep › Files Changed (2) ──┐
│▌ M chains.lua    lua/beast/libs/finder     │
│  M keymaps.lua   lua/beast/libs/finder     │
└────────────────────────────────────────────┘
                  <C-g> grep these 2 files   <BS> back to Commits

─────────────────────────────────────────
STATE 5 — Grep inside those files (your local copies):
┌─ 3 Files in feat/chain-keys › Live Grep ───┐┌─ chains.lua ──────────────────────────┐
│ > chain█                                   ││ ...                                   │
├────────────────────────────────────────────┤│                                       │
│  chains.lua  lua/beast/libs/finder         ││                                       │
│▌  1:3   --- The map of chains              ││                                       │
│   40:5  local function scope_files(what)   ││                                       │
└────────────────────────────────────────────┘└───────────────────────────────────────┘
                                                         <BS> back to Files Changed
```

A branch row is: name, a `●` on the branch you are on, the first line of its latest commit, the author, how long ago. Typing filters by any of these. The branch you are on is listed first, then the rest newest first.

---

# Scenarios

## 1 — Happy path: branch, its files, grep

```
Step 1: open Git Branches (<leader>gr), move to feat/chain-keys
  The right side lists the commits it has that main does not.
  The hint offers "<C-g> files changed in feat/chain-keys" and "<C-t> commits in feat/chain-keys".

Step 2: press <C-g>
  Title: "feat/chain-keys › Files Changed (3)". The 3 files are listed; the first one's diff is on the right.

Step 3: press <C-g>
  Title: "3 Files in feat/chain-keys › Live Grep". The prompt is empty.

Step 4: type "chain", move to a result, press <Enter>
  The picker closes and the file opens at that line.
```

## 2 — Branch, a commit, its files, grep

```
Step 1: on feat/chain-keys press <C-t>
  Title: "feat/chain-keys › Commits (3)". The first commit's diff is on the right.

Step 2: move to the second commit and press <C-g>
  Title: "b71e0d4 Wire <C-g> to the… › Files Changed (1)". Only the files that commit changed.

Step 3: press <C-g>
  Grep limited to those files, as in scenario 1.
```

## 3 — Going back

```
From grep: <BS> on an empty prompt (or <C-o>) -> the files list, same highlighted file.
From files / commits: <BS> on an empty prompt (or <C-o>) -> the branch list, same highlighted branch.
From a commit's files: <BS> -> the commits, same highlighted commit.
Nothing is searched again. <Esc> closes the whole chain.
```

## 4 — A branch with no changes of its own

```
The branch you are on is main, or a branch that points at the same commit as main.
<C-g> (files changed): nothing opens and a message says "Nothing changed on this branch against main".
<C-t> (commits): opens the latest 500 commits of that branch, the same list as <leader>gc.
```

## 5 — Branch that changed files you no longer have

```
A file the branch deleted is listed in Files Changed (marked D, its diff on the right) but is not in your
checkout. <C-g> (grep) keeps only the files that exist in your working tree; the title counts those.
If none exist: nothing opens and a message says "None of these files exist in your working tree".
```

## 6 — Open from the list

```
<Enter> on a branch: the picker closes and the branch's latest commit (message, then the diff of every
file) opens in a read-only buffer. Nothing is checked out; the branch you are on never changes.
<Enter> on a commit or a changed file: as in the existing local commit picker.
```

## 7 — Errors and empty

```
Not in a git repository: the list says "Not a git repository" and nothing else. <C-g> / <C-t> do nothing
but show a short note.
A repository with one branch and no commits yet: the list says "No branches".
Too many changes: a branch with more than 300 changed files shows the first 300 and the title ends
"(300, partial)"; a branch with more than 500 commits shows the latest 500 ("(500, partial)").
```

---

# Behavior Rules

- Only local branches are listed (no remote-tracking branches).
- "Against main" means against the point where the branch left the main line: files and commits that the branch added, not what main gained since. The main line is the repository's default branch (`main`, else `master`).
- The files of a branch are the union of what its commits changed, one row per file, with the status letter (A added, M modified, D deleted, R renamed).
- `<C-t>` and `<C-g>` act on the highlighted branch, not on the one you are on.
- `<C-g>` on a commit keeps the existing meaning: the files that commit changed.
- `<C-g>` on a list of changed files (of a branch or a commit) greps the local copies of those files; it never greps old content, so a line number can differ from the diff.
- The hint under the picker always shows the keys that work on the highlighted row, and "back to ..." below the first level.
- Back goes to the level you came from, exactly as you left it (prompt, list, highlighted row).
- Message rows ("No branches", errors) never open anything.
- Only the supported chains exist; any other key press shows "Nothing to open from here".

---

# Open decisions

1. **What "files changed" means for a branch.** Recommended: what the branch added since it left the main line (like the "Files changed" tab of a pull request). Alternative: the difference between the branch tip and main's tip right now (also shows what main gained since).
2. **Commits of a branch.** Recommended: only the commits not on main (3 in the example); on main itself, the latest 500. Alternative: always the full history of the branch.
3. **Key to open the branch list.** Recommended: `<leader>gr`, next to `<leader>gc` for commits (`<leader>gb` and `<leader>gB` are the blame keys).
4. **`<Enter>` on a branch.** Recommended: open its latest commit read-only (safe, changes nothing). Alternative: check the branch out (changes your working tree, so it needs a confirmation and a clean tree; deferred).

---

# Success Criteria

- [ ] `<leader>gr` lists local branches (current one first, marked), each with its latest commit line, author and age; typing filters them.
- [ ] On a branch, `<C-g>` lists the files it changed with status letters and the diff of the highlighted file on the right.
- [ ] On a branch, `<C-t>` lists its commits newest first, with the diff of the highlighted commit on the right.
- [ ] On a commit (from a branch or from `<leader>gc`), `<C-g>` lists the files that commit changed.
- [ ] On a list of changed files, `<C-g>` opens a grep limited to the existing local copies; the title counts them.
- [ ] `<BS>` on an empty prompt and `<C-o>` go back one level at each step without searching again, restoring the prompt and the highlighted row.
- [ ] A branch with no changes of its own says so on `<C-g>` and still lists history on `<C-t>`.
- [ ] Message rows, empty lists and "no local files" never open anything and say why.
- [ ] The hint under the picker shows `<C-g>` and `<C-t>` on a branch, `<C-g>` and `<BS> back` on a commit or a list of files.
- [ ] Opening a branch with `<Enter>` never changes the branch you are on.

---

# Out of Scope

- Checking out, creating, renaming or deleting a branch (see Open decision 4).
- Remote-tracking branches and branches of other repositories.
- Comparing two arbitrary branches.
- Reviewing, committing or cherry-picking from the picker.
