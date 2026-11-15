---
name: finder-diff-preview
description: A GitHub-style diff on the right of the Files Changed lists - line numbers, red/green lines, the exact changed words, wrapped long lines
generated: 2026-11-16
---

# Summary
When you highlight a file in "Files Changed" (of a pull request, or of one commit), the right side shows its diff the way GitHub does: old and new line numbers, whole red and green lines, the exact changed words emphasized, and long lines wrapped instead of cut. Reviewing a change no longer needs the browser.

---

# Problem

The finder already lists the files a pull request or a commit changed, and previews each one. But the preview is the raw patch text: `@@ -20,7 +20,7 @@` lines, a `-` or `+` in the first column, and nothing else. There are no line numbers, so you cannot tell where in the file you are. A line that was edited shows as two nearly identical lines with nothing marking the difference. Long lines run off the right edge and are cut, so the part you need is often the part you cannot see.

To really review a change you end up opening the pull request in the browser, where GitHub shows exactly what is missing. You would rather stay in the terminal.

## Why now
The finder now walks Pull Requests, Commits and Files Changed. Reading the diff is the whole point of that walk, and it is the one step that still feels like a raw patch. The patch for each file is already fetched; only its presentation is missing.

---

# Target Behavior

Today (what the preview shows):

```
┌─ packages/cli/README.md ───────────────────────────────┐
│ modified  +5 -6                                        │
│ @@ -20,7 +20,7 @@ mesh = jarvis >> planner >> (coder & t │
│  - The file may define other graphs or loose nodes; on │
│ -- `harness`, `cwd`, `model` and `prompt` are read fro │  <- cut at the edge
│ +- `harness`, `cwd`, `model` and `prompt` are read fro │  <- cut at the edge
```

After - STATE 1, a file with two changed places:

```
┌─ packages/cli/README.md ─────────────────────────────────────────┐
│ modified   +5 -6   ■■■■■□□□□□                                    │
├──────────────────────────────────────────────────────────────────┤
│  ⋯  19 unchanged lines above                                     │
│  ▸ @@ -20,7 +20,7 @@ mesh = jarvis >> planner >> (coder & tests)    │
│  20  20    (blank)                                               │
│  21  21     - The file may define other graphs or loose nodes;   │
│  22  22     - `A >> B` means A may message B. `&` groups sibling │
│  23     -   - `harness`, `cwd`, `model` and `prompt` are read    │  red line
│              from each node. `prompt` is the node's task, ...    │  (wrapped)
│      23 +   - `harness`, `cwd`, `model` and `prompt` are read    │  green line
│              from each node. `prompt` is the node's task, added  │  (wrapped)
│              to its system prompt [(nothing else is)]; for ...   │  [ ] = stronger green
│  24  24     - A node with no `cwd` runs in its parent's folder   │
│  25  25     - A node that is defined but not connected to ...    │
│  26  26     - A node written as a function (no `harness`) ...    │
│  ⋯  13 unchanged lines                                           │
│  ▸ @@ -40,14 +40,13 @@ jarvix mesh down                             │
│  40  40    (blank)                                               │
│  41  41    `jarvis` is the one pane you talk to. It does not ... │
└──────────────────────────────────────────────────────────────────┘
```

Row anatomy, left to right: old line number, new line number, a `-` / `+` / blank mark, the text.

```
 old new
  21  21     unchanged line       default text colors
  23     -   removed line         soft red across the whole row
      23 +   added line           soft green across the whole row
```

STATE 2 - one edited line, the exact change emphasized (same rule as the hunk preview in git):

```
│  43     -  Its system prompt has three layers: ... then your own text. Your text comes last ... │
│      43 +  Its system prompt has three layers: ... then your own text[, the `prompt` of the `jarvis` node]. Your text ... │
                                                                         └ stronger green on the new words only
```

STATE 3 - a new file (only a new-line column, everything green) and a deleted file (only old-line column, everything red):

```
┌─ packages/cli/src/jarvix/cli/prompts.py ──────────────┐   ┌─ docs/old-notes.md ────────────────────────┐
│ added   +42 -0   ■■■■■■■■■■                           │   │ removed   +0 -18   ■■■■■■■■■■              │
├───────────────────────────────────────────────────────┤   ├────────────────────────────────────────────┤
│  ▸ @@ -0,0 +1,42 @@                                   │   │  ▸ @@ -1,18 +0,0 @@                        │
│     1 +  """Prompt text for the nodes."""             │   │   1     -  # Old notes                     │
│     2 +                                               │   │   2     -                                  │
│     3 +  from __future__ import annotations           │   │   3     -  Nothing here is used any more.  │
```

STATE 4 - a renamed file, and a file with no readable diff:

```
┌─ packages/cli/tests/test_prompts.py ───────────────────┐   ┌─ assets/logo.png ──────────────────────────┐
│ renamed   +3 -1   (was packages/cli/tests/test_p.py)   │   │ modified                                   │
├────────────────────────────────────────────────────────┤   ├────────────────────────────────────────────┤
│  ▸ @@ -4,7 +4,9 @@ ...                                │   │                                            │
│   ...                                                  │   │  (diff too large or binary)                │
```

---

# Scenarios

## 1 - Happy path: review a pull request file by file

```
Step 1: open Pull Requests (<leader>ghp), move to a PR, press <C-g>
  Title: "PR Refactor m4 › Files Changed (5)". The first file is highlighted and its
  diff fills the right side as in STATE 1.

Step 2: press <Down>
  The next file's diff replaces it. It starts at the top. Nothing flickers or jumps.

Step 3: scroll the preview with the usual preview scroll keys
  Rows move together: line numbers, marks and text never separate.
  A wrapped line is never half off screen.

Step 4: press <Enter> on a file
  Unchanged from today: the picker closes and the diff opens in a read-only buffer.
```

## 2 - A long line

```
A changed line is longer than the preview is wide.
  The line wraps onto the next rows. The wrapped rows have empty number columns and the same
  red or green background, so it reads as one line. Nothing is cut at the right edge.
  Making the preview narrower or wider (resize the terminal) re-wraps the lines.
```

## 3 - An edited line: which words changed

```
A removed line and an added line that are almost the same (an edit):
  the words that differ get a stronger red (old) and a stronger green (new).
A removed line and an added line that share little: soft red and soft green only.
Pure additions or pure deletions: soft color only, no stronger highlight.
```

## 4 - Several changed places in one file

```
Between two changes, a muted row says how many unchanged lines are hidden ("13 unchanged lines")
followed by the change's own header (lines and the nearest function or heading, as git prints it).
If the first change is not at the top of the file, a row says "19 unchanged lines above".
Line numbers keep counting correctly across the gap (23, 24, 25, 26, then 40).
```

## 5 - Added, deleted and renamed files

```
Added file: only the new-line column has numbers, every row is green, header says "added  +42 -0".
Deleted file: only the old-line column has numbers, every row is red, header says "removed  +0 -18".
Renamed file: the header says "renamed" and "(was <old path>)"; unchanged content inside shows normally.
```

## 6 - No diff to show

```
A binary file, an image, or a diff GitHub considers too large:
  the preview shows the file name, its status and "(diff too large or binary)". No rows, no error.
```

## 7 - The commits of a PR use the same look

```
Step 1: from the PR's commits level, highlight a commit
  The right side shows the commit's message, its file list, then each file's diff - each diff drawn
  as in STATE 1 (line numbers, red/green, changed words, wrapped lines).

Step 2: <C-g> to a commit's Files Changed
  Same preview as scenario 1.
```

## 8 - Changing the colorscheme

```
Press the colorscheme picker, or :colorscheme with a diff open.
  Red, green, the stronger shades, and the number columns follow the new colorscheme (dark and light).
  The finder keeps its own colors while open, as it does for everything else.
```

## 9 - Moving fast and going back

```
Hold <Down> across many files: the preview follows without lag; only the file you stop on is drawn.
<BS> on an empty prompt or <C-o> goes back one level as before; the diff of the previous level
is shown again for the same highlighted row.
```

---

# Behavior Rules

- Applies to the preview of Files Changed for a pull request and for a commit, and to the per-file diffs in a commit's preview.
- The look is one column of diff (unified), top to bottom, like GitHub's "unified" view. No side-by-side.
- Number columns are as wide as the largest line number in that file, so rows stay aligned.
- The `@@ ... @@` text is never shown raw in the body; each hunk is one muted row (see STATE 1).
- The small bar in the header is proportional to additions vs deletions, five or ten blocks, like GitHub's.
- Marks and numbers are not part of the text: nothing but the code is selected or yanked if you copy from the preview.
- Whitespace-only and "No newline at end of file" lines are shown (the latter as a muted note).
- Only the lines GitHub returns (changes plus a few lines of context) exist; hidden lines cannot be expanded here.
- Colors come from the colorscheme; there are no fixed colors.
- Enter keeps opening the raw diff buffer; this spec does not change it.

---

# Open decisions

1. **Long lines.** Recommended: wrap (like GitHub). Alternative: keep cutting and scroll sideways.
2. **Code coloring.** Recommended: the code is also colored for the file's language (keywords, strings) on top of the red/green. Alternative: plain text color on the red/green, simpler and faster.
3. **Commit preview.** Recommended: the same look for the per-file diffs inside a commit's preview, so the whole chain is consistent. Alternative: only the Files Changed level.
4. **Enter.** Recommended: unchanged (raw diff in a read-only buffer, easy to copy or search). Alternative: open the same drawn diff in a full window.

---

# Success Criteria

- [ ] Highlighting a file in Files Changed shows the header (status, +N -M, bar) and the diff with old and new line numbers.
- [ ] Removed lines are red and added lines green across the whole row; unchanged context is neutral.
- [ ] On an edited line, only the words that changed get the stronger shade.
- [ ] A line longer than the preview wraps with empty number columns and keeps its color; nothing is cut at the edge.
- [ ] Gaps between changes show "N unchanged lines"; numbers stay correct across the gap.
- [ ] Added, deleted, renamed, binary and too-large files each render as in STATES 3 and 4.
- [ ] A commit's preview draws each file's diff in the same style.
- [ ] Changing the colorscheme recolors the diff correctly in dark and light.
- [ ] Moving through files is as fast as before; the diff always starts at the top.
- [ ] `<Enter>`, `<BS>`, `<C-o>` and `<C-g>` behave exactly as before.

---

# Out of Scope

- Side-by-side (split) view - the preview is half the screen wide.
- Expanding the hidden unchanged lines (needs the full file from the pull request's commit; deferred).
- Review features: comments, "Viewed" checkmarks, approving, suggestions.
- Toggling the changed-word emphasis off; it is always on, as in the git preview.
- Diffs of local changes (git hunk preview), which already has its own look.
