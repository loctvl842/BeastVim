---
name: finder-continuous
description: Chain finder pickers - drill from one picker into a follow-up picker scoped by what you found, and step back with backspace
generated: 2026-11-15
---

# Summary
Today every finder picker starts from nothing. This feature lets you press one key on a result list to open a follow-up picker that only looks inside what you just found (files, buffers or help pages -> grep in those; pull request -> the files that PR changed -> grep in those), and step back to the earlier picker, exactly as you left it, with backspace.

---

# Problem

You find a set of files, then want to search inside only those files. Today you close the picker, open grep, and grep searches the whole project, so the work of narrowing down is thrown away. You can retype the filter as a glob, but that is slow and only works for file names.

The same happens with pull requests: you find the PR you care about, but to see what it changed you leave the editor and open GitHub. After looking at a file you want to go back to the PR list and pick another one, and you lose the list and the search you typed.

## Why now
The finder already has a prompt, a list, a preview and two very different kinds of pickers (local files, GitHub). A follow-up picker is the natural next step, and the GitHub pickers just shipped with the "pick a PR" half of use case 2.

---

# Target Behavior

(The HTML review copy has a clickable simulator of these states.)

One idea: **a chain of pickers**. Each level narrows the next. The title bar shows where you are, the prompt of a follow-up picker starts empty, and backspace on an empty prompt goes one level back.

```
STATE 0 - Prerequisite: Files and Buffers rows get the same look as grep results

Today (path first, folder in front):
┌─ Files ────────────────────────────────────────────┐
│ > finder                                      38/912│
├────────────────────────────────────────────────────┤
│▌  lua/beast/libs/finder/init.lua                   │
│   lua/beast/libs/finder/state.lua                  │
└────────────────────────────────────────────────────┘
┌─ Buffers ──────────────────────────────────────────┐
│ > █                                              3 │
├────────────────────────────────────────────────────┤
│▌ [4] lua/beast/libs/finder/init.lua [+]            │
│  [7] README.md                                     │
└────────────────────────────────────────────────────┘

After (file icon, file name, then the folder dimmed; same as a file row in Live Grep):
┌─ Files ────────────────────────────────────────────┐
│ > finder                                      38/912│
├────────────────────────────────────────────────────┤
│▌  init.lua  lua/beast/libs/finder                  │
│   state.lua  lua/beast/libs/finder                 │
└────────────────────────────────────────────────────┘
┌─ Buffers ──────────────────────────────────────────┐
│ > █                                              3 │
├────────────────────────────────────────────────────┤
│▌  init.lua  lua/beast/libs/finder  [+]             │
│   README.md                                        │
└────────────────────────────────────────────────────┘

─────────────────────────────────────────────────────────────
STATE 1 - Level 1: find files (you typed "lua/finder")

┌─ Files ────────────────────────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > lua/finder█                                 38/912││ local M = {}                                   │
├────────────────────────────────────────────────────┤│ ...                                            │
│▌ ● init.lua  lua/beast/libs/finder                 ││                                                │
│  ● state.lua  lua/beast/libs/finder                ││                                                │
│  ● render.lua  lua/beast/libs/finder               ││                                                │
│  ...                                               ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                                     <C-g> grep 38 files

─────────────────────────────────────────────────────────────
STATE 2 - Level 2: grep inside those 38 files (after <C-g>)

┌─ 38 Files › Live Grep ─────────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > █                                                ││                                                │
├────────────────────────────────────────────────────┤│                                                │
│  (type to search inside the 38 files)              ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                                      <BS> back to Files

─────────────────────────────────────────────────────────────
STATE 3 - Level 2 with a query (grouped like Live grep: file, then its matching lines)

┌─ 38 Files › Live Grep ─────────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > preview                                      7/7 ││ 41 │ function M.show(view, item)               │
├────────────────────────────────────────────────────┤│ 42 │   local st = state_of(view)               │
│  ● render.lua  lua/beast/libs/finder               ││                                                │
│▌ 41:12    function M.show(view, item)              ││                                                │
│  57:3     -- preview the item                      ││                                                │
│  ● init.lua    lua/beast/libs/finder               ││                                                │
│  90:8     local preview = require("...")           ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                                      <BS> back to Files

─────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > preview                                      7/7 ││ 41 │ function M.show(view, item)               │
├────────────────────────────────────────────────────┤│ 42 │   local st = state_of(view)               │
│▌ lua/beast/libs/finder/render.lua:41  preview(...  ││                                                │
│  lua/beast/libs/finder/init.lua:90    preview ...  ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                                      <BS> back to Files

─────────────────────────────────────────────────────────────
STATE 4 - Use case 2, level 1: pull requests

┌─ Pull Requests - loctvl842/jarvix ─────────────────┐
│ > is:pr is:merged hub                          3/3 │
├────────────────────────────────────────────────────┤
│▌● #11  fix: publish each package with its own ..   │
│ ● #3   feat: hub state tracking @loctvl842         │
└────────────────────────────────────────────────────┘
                            <C-g> files changed in #11

─────────────────────────────────────────────────────────────
STATE 5 - Use case 2, level 2: files changed in PR #11 (file paths only, diff in the preview)

┌─ PR fix: publish each pack... › Files Changed (5) ─┐┌─ preview: lua/hub/state.lua ───────────────────┐
│ > █                                            5/5 ││ M  +42 -3                                      │
├────────────────────────────────────────────────────┤│ @@ -12,6 +12,9 @@ function M.track(node)        │
│▌ ● state.lua  lua/hub                              ││    local st = hubs[node.hub]                   │
│  ● track.lua  lua/hub                              ││ -  st.last = os.time()                         │
│  ● README.md                                       ││ +  st.last = clock.now()                       │
│  ● old.lua    lua/hub                              ││ +  st.seen[node.id] = true                     │
│  ● b.lua      lua/hub  (was a.lua)                 ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                              <BS> back to Pull Requests

─────────────────────────────────────────────────────────────
STATE 6 - Use case 3, level 3: grep inside the files changed by the PR

┌─ 4 PR Files › Live Grep ───────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > seen                                         2/2 ││ 29 │ local st = hubs[node.hub]                 │
├────────────────────────────────────────────────────┤│ 30 │ st.last = clock.now()                     │
│  ● state.lua  lua/hub                              ││ 31 │ st.seen[node.id] = true                   │
│▌ 31:2     st.seen[node.id] = true                  ││                                                │
│  ● track.lua  lua/hub                              ││                                                │
│  17:3     self.seen = {}                           ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                           <BS> back to Files Changed

─────────────────────────────────────────────────────────────
STATE 7 - Use case 4: Issues, then grep inside the issue text

┌─ 3 Issues › Live Grep ─────────────────────────────┐┌─ preview ──────────────────────────────────────┐
│ > dot                                          2/2 ││ Hub crashes when a node name has a dot   #41   │
├────────────────────────────────────────────────────┤│                                                │
│  ○ #41  Hub crashes when a node name has a dot     ││ `jarvix node run --node a.b` exits silently    │
│▌ 3:12   a name like a.b is split on the dot        ││ when a name like a.b is split on the dot.      │
│  ○ #35  Pane labels are lost after restart         ││                                                │
│  5:20   labels with a dot are dropped              ││                                                │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
                                                                                <BS> back to Issues
```

- Key hints are dim tooltip-like text on a line just below the picker's bottom border, right-aligned to the picker's right edge (outside the frame, never a row in the list): the key that goes deeper (only where the picker has a next step) and, below level 1, the key that goes back, naming the destination ("back to Files"). When there is no room below the picker on screen, the hint is hidden.
- The title reads "scope › this picker": "38 Files › Live Grep", "PR <title> › Files Changed (5)". A long PR title is cut with `...` so the rest of the title stays visible. Level 1 keeps its own title.
- Rows use the Live grep list look: a file row is the file name plus its dim parent folder; in Grep, the matching lines sit indented under their file, each with `line:col`.
- Level 2 of the PR chain is a plain list of the changed file paths (file name, dim folder, an icon for added/modified/deleted). The diff, including `+`/`-` counts, shows in the preview on the right.
- A diff preview uses the usual diff colors: added lines green, removed lines red, hunk headers dim.

---

## Prerequisite change to existing pickers

The chain only looks right if Files and Buffers rows already look like grep results, so this ships first (STATE 0): icon, file name, then the folder dimmed. This changes how the normal Files and Buffers pickers look for everyone, with or without a chain. Buffers keeps its `[+]` modified marker (moved to the end of the row). Other pickers are unchanged.

---

# Scenarios

## 1 - Files, then grep inside them (happy path)

```
Step 1: Press <leader>f, type "lua/finder".
  38 of 912 files match.

Step 2: Press <C-g>.
  Picker switches to "38 Files › Live Grep", prompt empty, list empty
  with a quiet line "type to search inside the 38 files".

Step 3: Type "preview".
  Matching lines from those 38 files only appear, with the line in the preview.
  Matches in other files do not appear.

Step 4: Press <Enter> on a match.
  The file opens at that line. The whole chain closes.
```

## 2 - Go back and change the first query

```
Step 1: From scenario 1 step 3, clear the prompt (<C-u>) and press <BS> on the empty prompt.
  (or press <C-o> at any time)
  Picker returns to "Files", prompt "lua/finder", same highlighted row as before.

Step 2: Change the prompt to "lua/explorer".
  List updates as usual.

Step 3: Press <C-g> again.
  New level 2 over the new file set. The earlier grep text is gone.
```

## 3 - Pull request, then its changed files (use case 2)

```
Step 1: Press <leader>ghp, move to #11.

Step 2: Press <C-g>.
  Title "PR fix: publish each pack... › Files Changed (5)". A spinner shows while loading (no count yet), then
  the changed file paths appear (name, dim folder). The preview shows the
  highlighted file's diff with its status and +/- counts.

Step 3: Move down with <C-j>.  The preview follows with each file's diff.
        Type "state".  The list is fuzzy-filtered by path.

Step 4: Press <BS> on an empty prompt (or <C-o>).
  Back on the PR list with the same text ("is:pr is:merged hub"), the same
  results and #11 highlighted. No new search is made.

Step 5: Move to #3 and press <C-g> again.
  The files changed in #3.
```

## 4 - Open a changed file's diff

```
Step 1: Press <Enter> on lua/hub/state.lua in "Files changed".
  The chain closes. The file's changes open in a read-only buffer with diff
  colors, cursor on the first change.
```

## 5 - Nothing to go deeper into

```
Step 1: On Live Grep or any picker with no next step, press <C-g>.
  A brief toast "Nothing to open from here". The picker stays as it was.
  (These pickers show no <C-g> hint.)

Step 2: On a picker whose list is empty, press <C-g>.
  Same toast. Nothing to scope to.
```

## 6 - Still scanning

```
Step 1: Open Files in a huge project and press <C-g> while the spinner is still running.
  Toast "Still searching - try again in a moment". The picker stays as it was.
```

## 7 - Cancel

```
Step 1: At level 2 press <Esc> (or <C-c>).
  The whole chain closes, not just one level. Nothing is kept.

Step 2: At level 1 press <BS> on an empty prompt.
  Nothing happens (there is nowhere to go back to).
```

## 8 - PR files cannot load

```
Step 1: Press <C-g> on a PR but the network is down or the PR is gone.
  Level 2 opens with one quiet line "Could not load the changed files:
  <reason>", like the GitHub list errors. <BS> still goes back.
```

## 9 - Large PR

```
Step 1: Press <C-g> on a PR with a very large diff.
  Only the first 300 changed files are listed (our cap, to keep it fast); the title ends
  with "(partial)" and the count reads "300+". Behavior is otherwise the same.
```

## 10 - Buffers, then grep inside them

```
Step 1: Press <leader>b and type "lua".  The open buffers that match are listed.
Step 2: Press <C-g>.
  Title "6 Buffers › Live Grep", empty prompt. Hint below: "<BS> back to Buffers".
Step 3: Type "preview".  Matches only from those 6 buffers' files appear.
        (Buffers with no file, like scratch buffers, are not part of the scope.
        Grep reads the saved file, so unsaved edits are not searched.)
```

## 11 - Help, then grep inside the matching help pages

```
Step 1: Press <leader>h and type "window".  Matching help tags are listed.
Step 2: Press <C-g>.
  Title "4 Help Files › Live Grep". The scope is the help pages those tags live in
  (each page once), not only the tag lines.
Step 3: Type "split".  Matching lines inside those help pages appear.
```

## 12 - Pull request, then its files, then grep inside them (three levels)

```
Step 1: <leader>ghp, move to #11, press <C-g>.  "PR ... › Files Changed (5)".
Step 2: Press <C-g> again.
  Title "4 PR Files › Live Grep", empty prompt, quiet line
  "type to search your local copies of the 4 files".
  Files deleted by the PR, or not present in your working tree, are left out
  (that is why it says 4, not 5).
Step 3: Type "seen".  Matches appear grouped by file (STATE 6).
Step 4: <BS> goes to "Files Changed", <BS> again goes to the PR list, each exactly as left.
Step 5: If none of the files exist locally: toast "None of these files exist in your
        working tree" and the picker stays.
```

## 13 - Issues, then grep inside the issue text

```
Step 1: <leader>ghi.  Issues open as usual (STATE 2 of the GitHub spec).
Step 2: Press <C-g>.
  Title "3 Issues › Live Grep", empty prompt, quiet line
  "type to search the text of the 3 issues". Hint below: "<BS> back to Issues".
Step 3: Type "dot".  Matching lines of each issue's title and description appear
        under an issue row (number, title), with line:col. Issues without a match disappear.
        The preview shows the whole issue.
Step 4: <Enter> opens that issue in the browser; <BS> returns to the issue list as left.
        (Comments are not searched; only title and description.)
```

---

# Behavior Rules

- **One key goes deeper:** `<C-g>`. It always means "continue inside what I see".
  - Files, Buffers, Help and a PR's changed files -> **grep inside** the files currently matching (for Help: the help pages of the matching tags).
  - Pull Requests -> the files changed by the highlighted PR.
  - Issues -> **grep inside the text** (title and description) of the listed issues. Issues are not files, so this is the closest meaning of "grep" there.
  - Pickers with no next step (Live Grep itself) do not show the hint.
- **Scope = everything that currently matches, not only the highlighted row.** An empty prompt means the whole list. For Pull Requests the scope is the highlighted PR.
- **Grep reads files on disk in your working tree.** Buffers with no file, files deleted by a PR and files missing locally are left out of the scope; the count in the title reflects what is left.
- **A follow-up picker always starts with an empty prompt.**
- **Back is a stack, not a history.** `<BS>` on an empty prompt, or `<C-o>` at any time, returns to the previous level. Going back and forward again starts the deeper level fresh.
- **Going back restores** the earlier prompt text, results and highlighted row. GitHub lists are not searched again. File lists are re-run (cheap) and the highlighted row is restored by name.
- **`<Esc>` / `<C-c>` close the whole chain.** Opening any picker later starts at level 1 as usual.
- **Opening a result closes the chain.** `<Enter>`, `<C-s>`, `<C-v>` act on the result as in any picker.
- **`<C-y>` copies** the highlighted result's path (or URL for PRs) at any level, as today.
- **Depth is not limited.** Today's longest chain has three levels (PR > Files Changed > Live Grep).
- **The next level can't start while the current one is still collecting results.** Toast instead, no partial scope.
- **Files and Buffers rows use the grep file look** (icon, name, dim folder) everywhere, chain or not. The buffer number is no longer shown in the row.
- **Title and hint** always show the chain and the destination of `<BS>`. Hints sit below the picker, right-aligned, and are hidden when there is no room.
- **Level 2 can fail alone.** An error is shown as one quiet line in the list; `<BS>` still works.

---

# Success Criteria

- [ ] In Files, Buffers and Help, `<C-g>` opens a grep that only returns matches inside the files (or help pages) that matched the prompt.
- [ ] In Issues, `<C-g>` greps the title and description of the listed issues and shows matches under each issue.
- [ ] From a PR's changed files, `<C-g>` greps the local copies of those files; deleted or missing ones are left out and the title count says how many remain.
- [ ] In Pull Requests, `<C-g>` lists the files changed by the highlighted PR (paths only), with the diff, status and +/- counts in the preview; typing filters by path.
- [ ] `<BS>` on an empty prompt and `<C-o>` return to the earlier picker with the same prompt, results and highlighted row.
- [ ] Going back to the PR list makes no GitHub search.
- [ ] `<Esc>` closes the whole chain; `<Enter>` on a result closes it too.
- [ ] The title bar shows the chain; the hint below the picker shows `<C-g>` only where there is a next step and `<BS>` only below level 1.
- [ ] `<C-g>` on a picker with no next step, an empty list, or a still-scanning list shows a short toast and changes nothing.
- [ ] A failed or huge changed-files listing is handled in-list as in scenarios 8 and 9.
- [ ] Files and Buffers rows show icon, file name and dim folder (STATE 0); Buffers still marks modified buffers with `[+]`.
- [ ] Files and Buffers rows show icon, file name and dim folder (STATE 0); Buffers still marks modified buffers with `[+]`.
- [ ] Apart from that row look, opening a picker normally (no chain) looks and behaves exactly as before.

---

# Out of Scope

- **Forward navigation / full history** (a browser-style forward button): going back and deeper again starts fresh, which keeps the model to one stack.
- **More chains** (Grep -> files with matches, Issues -> linked PRs, searching issue comments, PR -> grep inside the PR description, PR -> grep inside the diff text, LSP references -> grep): the design allows them, each one needs its own decision on what the scope means.
- **Selecting several rows by hand** as a scope: the scope is always "all that currently match".
- **Showing the whole PR diff as one document** or reviewing/commenting: browsing only.
- **GitLab:** deferred until the GitHub side is settled.
