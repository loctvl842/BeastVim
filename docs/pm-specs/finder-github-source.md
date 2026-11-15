---
name: finder-github-source
description: Browse GitHub pull requests and issues of the current repo in the finder, where the prompt text is the GitHub search query itself
generated: 2026-11-15
---

# Summary
Two new pickers, one for pull requests and one for issues, let the user scan a GitHub repo without leaving the editor. The prompt is not a fuzzy filter: it holds a real GitHub search query (`is:pr state:open` by default) that the user can edit freely, so one key per kind is enough and "open", "closed", "merged", "mine" and so on are just different text.

---

# Problem

To skim what is going on in a repo (which PRs are open, what bugs were reported, what did I merge last week) the user has to leave the editor, open a browser, find the right tab and type filters into GitHub's search box. Copying a PR number back into the editor, or finding the PR that touches the code in front of them, is a context switch every time.

A picker that offers a separate key per view (open PRs, all PRs, open issues, all issues, my PRs ...) does not fix this either: it multiplies key bindings, and still cannot express a view nobody thought of ahead of time.

## Why now
The finder already has the pieces: a prompt, a list, a preview pane, and live sources that re-run when the user types. GitHub's own search syntax is already known to the user and is more powerful than any set of fixed views. Making the prompt text the query gives every view for free with two key bindings.

---

# Target Behavior

STATE 1 - Pull request picker just opened. The prompt is pre-filled with the default query and the cursor sits at its end. The list is the current repo's open PRs, newest first (same order as GitHub's own pages). The preview shows the highlighted PR:

```
┌─ Pull Requests - loctvl842/jarvix ─────────────────┐┌─ PR #30 ───────────────────────────────────────┐
│ > is:pr state:open █                         22/22 ││ feat(cli): function nodes that send and #30    │
├────────────────────────────────────────────────────┤│                                                │
│ ○ #32  Refactor m4 @loctvl842                      ││ Status:    ● Merged   main <- function-nodes   │
│▌● #30  feat(cli): function nodes that send and     ││ Repo:      loctvl842/jarvix                    │
│        receive in their own pane @loctvl842        ││ Author:    loctvl842                           │
│ ● #28  feat(cli): Jarvis supervisor prompt @loc..  ││ Created:   2 weeks ago                         │
│ ● #26  feat(cli): show every node's events ..      ││ Updated:   2 weeks ago                         │
│ ◌ #25  wip: retry policy  @loctvl842  [draft-idea] ││ Checks:    ✓ 1                                 │
│ ✕ #4   Feat/claude m3 @loctvl842                   ││ Changes:   21 files  +832 -37                  │
│ ● #3   feat: hub state tracking @loctvl842         ││                                                │
│                                                    ││ ---------------------------------------------- │
│                                                    ││ ## Summary                                     │
│                                                    ││ A node written as a plain function now runs    │
│                                                    ││ in its own tmux pane and can send and receive. │
│                                                    ││ ...                                            │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
  icons: ○ open   ◌ draft   ● merged   ✕ closed   (Nerd Font git icons in the real UI)
```

- Same look and keys as the other finder pickers: prompt on top, list on the left, preview on the right, same selection marker. A result count in the prompt row is new and shown for these pickers.
- Row: state icon, `#number`, title, `@author`, then label badges in each label's own GitHub color. A long title wraps or is cut like in other pickers.
- The title bar names the repo being searched.

─────────────────────────────────────────
STATE 2 - Issue picker just opened. Same screen, other default text and other preview:

```
┌─ Issues - loctvl842/jarvix ────────────────────────┐┌─ Issue #41 ────────────────────────────────────┐
│ > is:issue state:open █                      7/7   ││ Hub crashes when a node name has a dot   #41   │
├────────────────────────────────────────────────────┤│                                                │
│▌○ #41  Hub crashes when a node name has a dot      ││ Status:    ○ Open                              │
│        @loctvl842  [bug]                           ││ Repo:      loctvl842/jarvix                    │
│ ○ #39  Document the mesh down flag @loctvl842      ││ Author:    loctvl842                           │
│        [docs]                                      ││ Labels:    [bug]                               │
│ ○ #35  Pane labels are lost after restart          ││ Created:   3 days ago                          │
│        @loctvl842  [bug] [tmux]                    ││ Comments:  2                                   │
│                                                    ││ ---------------------------------------------- │
│                                                    ││ ## What happens                                │
│                                                    ││ `jarvix node run --node a.b` exits silently... │
│                                                    ││                                                │
│                                                    ││ ## Conversation                                │
│                                                    ││ @someone  1 day ago                            │
│                                                    ││ Reproduced on main.                            │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
```

- Pull-request-only fields (branches, checks, mergeable, changes) are simply absent for issues.
- Below the description the preview shows the conversation (comments, and review summaries for PRs) read-only, oldest first.

─────────────────────────────────────────
STATE 3 - The user edited the text. The list follows GitHub's answer to exactly that text:

```
┌─ Pull Requests - loctvl842/jarvix ─────────────────┐
│ > is:pr is:merged author:@me hub               3/3 │
├────────────────────────────────────────────────────┤
│▌● #11  fix: publish each package with its own ..   │
│ ● #3   feat: hub state tracking @loctvl842         │
│ ● #2   feat(mux): tmux integration @loctvl842      │
└────────────────────────────────────────────────────┘
```

─────────────────────────────────────────
STATE 4 - A new search is running (user just typed). The previous list stays on screen so nothing flickers; a small spinner replaces the count:

```
│ > is:pr state:open fix                       ⠋     │
├────────────────────────────────────────────────────┤
│▌○ #32  Refactor m4 @loctvl842                      │   <- old results, until the new ones land
```

─────────────────────────────────────────
STATE 5 - Search failed (repo not found, rate limit, network) or found nothing. One quiet line in the list, no popup:

```
│ > repo:nope/nope is:pr                             │
├────────────────────────────────────────────────────┤
│  GitHub could not run this search:                 │
│  repository not found or no access to it           │
```

```
│ > is:pr label:does-not-exist                  0/0  │
├────────────────────────────────────────────────────┤
│  No results for this search                        │
```

---

# Scenarios

## 1 - Skim open pull requests (happy path)

```
Step 1: Press <leader>ghp inside a repo that has a GitHub remote.
  The picker opens with "is:pr state:open " in the prompt, cursor at the end.
  The list fills with the repo's open PRs, newest first.

Step 2: Press Down / Up (or Ctrl-n / Ctrl-p) to move through the list.
  The preview follows. The header (title, state, author, labels) appears at once;
  the description and conversation fill in a moment later.

Step 3: Go back to a PR already visited.
  Its preview appears instantly, it is not fetched again while the picker is open.
```

## 2 - Look at closed or merged work by editing the text

```
Step 1: In the PR picker, change "state:open" to "is:merged".
  Prompt: "is:pr is:merged"
  A spinner shows briefly, then the list becomes merged PRs only.

Step 2: Append "author:@me".
  Only merged PRs authored by the user remain.
```

No separate key and no extra menu: the text is the filter.

## 3 - Search by words and qualifiers together

```
Step 1: Type " hub" after the default text.
  Prompt: "is:pr state:open hub"
  The list shows open PRs where GitHub finds "hub" (title, description, comments).

Step 2: Type " label:bug".
  The list narrows further.
```

Words are matched by GitHub, the same as the search box on github.com, not by the finder's fuzzy matcher.

## 4 - Switch from PRs to issues without closing the picker

```
Step 1: In the PR picker, replace "is:pr" with "is:issue".
  Prompt: "is:issue state:open"
  The list becomes issues; icons and the preview change to the issue style.
```

## 5 - Look at another repo

```
Step 1: Type "repo:neovim/neovim is:issue label:bug" (replacing the default text).
  The list shows bug issues from that repo. The title bar now reads
  "Issues - neovim/neovim".
```

Without a `repo:`, `org:` or `user:` qualifier, the search is always limited to the current repo.

## 6 - Open or copy the highlighted item

```
Step 1: Press Enter on a row.
  The picker closes and the PR or issue opens in the default web browser.

Step 2 (alternative): Press Ctrl-y instead.
  The URL is copied, the picker stays open, and a toast confirms the copy.
```

## 7 - Typing fast, slow network

```
Step 1: Type "fix" quickly, then keep typing "ing the bug".
  Only one search starts, after the user pauses for a moment (a little longer than for local pickers).
  If a slower, older search finishes after a newer one, its results are thrown away.
  The list always matches the text currently in the prompt.
```

## 8 - Cannot run (error and edge cases)

```
Case A: Run <leader>ghp in a folder that is not a GitHub repo.
  The picker does not open. A toast says: "No GitHub remote found for this directory".

Case B: "gh" is not installed, or not logged in.
  The picker does not open. A toast says what is missing and how to fix it
  ("GitHub CLI (gh) is not installed" / "Run `gh auth login` first").

Case C: The user types a half-written or unknown qualifier ("is:pr state:", "foo:bar").
  GitHub does not reject these, it just finds nothing: "No results for this search" (case D).
  Finishing the qualifier brings results back on its own.

Case C2: The search really fails (repo not found or no access, rate limit, network, login expired).
  The list shows the one-line reason (STATE 5), never a popup. A rate limit says when it resets.

Case D: The search is valid but finds nothing.
  The list shows "No results for this search" and the count reads 0/0.

Case E: More than 100 matches.
  The newest 100 are shown and the count reads "100+" so the user knows to narrow the query.
```

## 9 - Cancel

```
Step 1: Press Esc (normal mode) or Ctrl-c at any time.
  The picker closes. Nothing is opened or copied. A running search is dropped.
```

---

# Behavior Rules

- The prompt text is sent to GitHub as-is. It is never fuzzy-filtered locally. Whatever works in the github.com search box works here.
- Default text is `is:pr state:open ` for the PR picker and `is:issue state:open ` for the issue picker, with a trailing space so the user can keep typing. The default is only a starting point, the user can delete or replace any of it.
- The text decides what is listed, including kind: if no `is:pr` / `is:issue` is left in the text, PRs and issues appear together, told apart by their icon.
- Results are limited to the repo of the current directory unless the text contains `repo:`, `org:` or `user:`.
- Order: newest created first, exactly like GitHub's own PR and issue pages, unless the text has its own `sort:` qualifier (e.g. `sort:updated-desc`).
- At most 100 results are loaded. The list is not paginated.
- A new search starts only after typing pauses. While it runs, the old list stays and a spinner replaces the count. Out-of-date answers never overwrite newer ones.
- Errors from GitHub and empty results are shown inside the list, not as popups. Only "cannot start at all" problems (no remote, no `gh`, not logged in) use a toast.
- The preview shows what is already known from the list instantly, then fills in description and conversation when they arrive. Fetched previews are kept until the picker closes.
- The preview is read-only. Long descriptions scroll with the same keys as other previews.
- Reopening the picker starts again from the default text, not from the last query.
- Enter opens the item in the browser. Ctrl-y copies its URL. Ctrl-s and Ctrl-v (splits) do nothing, since there is no file.
- Key bindings: `<leader>ghp` opens the PR picker, `<leader>ghi` opens the issue picker. (`<leader>gp` is already "Preview hunk".)
- Colors of state icons: open green, draft grey, merged purple, closed red. Issues closed as "not planned" are grey, others purple.

---

# Decisions

Defaults chosen in this spec, change any of them in review:

1. **Keys** (confirmed): `<leader>ghp` / `<leader>ghi`. No clash, grouped as "GitHub". Both keys stay even though the text can switch kind, since opening straight on the wanted kind is the common case.
2. **Deleting `is:pr` / `is:issue`** (confirmed): show both kinds together. The text is the single source of truth.
3. **Enter**: open in the browser (recommended for a first version). Alternative: open an in-editor read-only page for the item.
4. **Default order** (confirmed): behave like GitHub browsing, newest created first. Users can add `sort:` to change it.

---

# Success Criteria

- [ ] `<leader>ghp` and `<leader>ghi` open a picker whose prompt holds `is:pr state:open ` and `is:issue state:open ` with the cursor at the end.
- [ ] The list shows the current repo's open PRs / issues with state icon, number, title, author and colored label badges.
- [ ] Editing the text (state, author, label, words, other repo, flipping `is:pr` to `is:issue`) changes the list to match what github.com would show for that text.
- [ ] Moving the cursor shows a preview with metadata, description and conversation; revisiting an item is instant.
- [ ] Typing fast results in one search, and the list never shows results for an older text.
- [ ] While a search runs the old list stays visible and a spinner replaces the count.
- [ ] Failed searches (repo not found, rate limit, network) and empty results show one in-list line, not a popup. Unknown qualifiers simply give no results.
- [ ] No remote / no `gh` / not logged in shows a clear toast and does not open an empty picker.
- [ ] Enter opens the browser, Ctrl-y copies the URL, Esc closes without side effects.
- [ ] Look and keys match the existing finder pickers.

---

# Out of Scope

- Write actions: commenting, closing, merging, labeling, assigning, reacting. Deferred, v1 is for scanning.
- Checking out a PR branch and viewing a PR's diff inside the editor. A natural follow-up once scanning is solid.
- An in-editor page for a PR or issue (Enter opens the browser instead).
- Highlighting or auto-completing qualifiers (`state:`, `label:` ...) in the prompt.
- Paging beyond 100 results.
- Remembering the last query between openings.
- Opening the picker outside a GitHub repo to search by `repo:` only.
- GitLab (planned as a follow-up, own spec). Its filtering differs: UI filter tokens, the GLQL query language, and `glab` flags, so it is not a copy of the GitHub query box.
- Other forges (Bitbucket, Gitea).
