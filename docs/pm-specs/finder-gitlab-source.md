---
name: finder-gitlab-source
description: Browse GitLab merge requests and issues of the current repo in the finder (gitlab.com or self-hosted, host read from the git remotes), with the same drill-down into files, commits and text search as the GitHub source; the prompt holds simple filter flags instead of a query language
generated: 2026-11-17
---

# Summary
Two new pickers, one for merge requests and one for issues, let the user scan a GitLab project without leaving the editor, exactly like the GitHub pull request and issue pickers. The project and the server (gitlab.com or a company's own GitLab) are found from the repo's git remotes, so nothing needs configuring for the common case. The prompt holds readable filter flags (`state:opened author:@me label:bug`) plus free words, and the same drill-down keys as GitHub lead from a merge request to its files, its commits and a text search inside them.

---

# Problem

A user whose repo lives on GitLab gets none of the GitHub pickers: the keys are absent, and to skim merge requests or issues they have to leave the editor, open the web page, and click through GitLab's filter bar. Many people work on both GitHub and a company GitLab, and the editor treats only one of them as a first-class citizen.

Copying GitHub's design one to one does not work, because GitLab has no GitHub-style search box syntax: its web filter is a row of tokens, and "open", "merged", "mine" are values of fixed fields, not free text. The picker has to offer something equally quick to type but honest about what GitLab can filter on.

## Why now
The finder already has the live, prompt-driven source, the preview, and the drill-down chains for GitHub. The git remote reader already recognizes GitLab hosts. What is missing is the GitLab side of the same experience.

---

# Target Behavior

STATE 1 - Merge request picker just opened. The prompt is pre-filled with `state:opened ` and the cursor sits at its end. The list is the project's open merge requests, newest first. The preview shows the highlighted one:

```
┌─ Merge Requests - platform/payments/api ───────────┐┌─ MR !412 ──────────────────────────────────────┐
│ > state:opened █                             14/14 ││ Retry failed webhooks with backoff        !412 │
├────────────────────────────────────────────────────┤│                                                │
│ ○ !418  Bump rails to 7.1 @mina                    ││ Status:    ○ Open   retry-backoff -> main      │
│▌○ !412  Retry failed webhooks with backoff @dao    ││ Project:   platform/payments/api               │
│         [backend] [payments]                       ││ Author:    dao                                 │
│ ◌ !409  Draft: ledger export @sam  [wip]           ││ Reviewers: mina, lee                           │
│ ○ !405  Fix typo in README @lee                    ││ Created:   3 days ago                          │
│ ○ !398  Cache currency rates @mina  [perf]         ││ Updated:   5 hours ago                         │
│                                                    ││ Pipeline:  ✓ passed                            │
│                                                    ││ Changes:   6 files  +141 -23                   │
│                                                    ││ Merge:     can be merged                       │
│                                                    ││ ---------------------------------------------- │
│                                                    ││ ## What                                        │
│                                                    ││ Webhooks that fail with 5xx are retried up to  │
│                                                    ││ five times with exponential backoff...         │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
  icons: ○ open   ◌ draft   ● merged   ✕ closed   (Nerd Font git icons in the real UI)
```

- Same look, keys and selection marker as the GitHub pickers and the other finder pickers. The result count sits in the prompt row.
- Row: state icon, `!number` for merge requests (`#number` for issues, the way GitLab writes them), title, `@author`, then label badges. GitLab "scoped" labels (`priority::high`) show as written.
- The title bar names the project, with the full group path (`platform/payments/api`). For a self-hosted server the host is added: `Merge Requests - git.acme.dev/platform/payments/api`.

─────────────────────────────────────────
STATE 2 - Issue picker just opened. Same screen, other default text and other preview:

```
┌─ Issues - platform/payments/api ───────────────────┐┌─ Issue #207 ───────────────────────────────────┐
│ > state:opened █                              5/5  ││ Webhook signature check fails on retries  #207 │
├────────────────────────────────────────────────────┤│                                                │
│▌○ #207  Webhook signature check fails on retries   ││ Status:    ○ Open                              │
│         @dao  [bug] [payments]                     ││ Project:   platform/payments/api               │
│ ○ #203  Document sandbox keys @lee  [docs]         ││ Author:    dao                                 │
│ ○ #199  Currency rounding off by one cent @sam     ││ Assignees: mina                                │
│         [bug]                                      ││ Labels:    [bug] [payments]                    │
│                                                    ││ Milestone: 2026.4                              │
│                                                    ││ Created:   3 days ago                          │
│                                                    ││ Comments:  2                                   │
│                                                    ││ ---------------------------------------------- │
│                                                    ││ ## Steps                                       │
│                                                    ││ 1. Send a webhook that returns 500...          │
│                                                    ││                                                │
│                                                    ││ ## Conversation                                │
│                                                    ││ @mina  1 day ago                               │
│                                                    ││ Reproduced on main.                            │
└────────────────────────────────────────────────────┘└────────────────────────────────────────────────┘
```

- Merge-request-only fields (branches, reviewers, pipeline, changes, merge status) are absent for issues.
- Below the description the preview shows the conversation, oldest first, read-only. Automatic system lines ("added label ~bug", "changed milestone") are left out; only what people wrote is shown.

─────────────────────────────────────────
STATE 3 - The user edited the text. The list follows exactly those filters:

```
┌─ Merge Requests - platform/payments/api ───────────┐
│ > state:merged author:@me webhook              3/3 │
├────────────────────────────────────────────────────┤
│▌● !377  Webhook delivery log @loctvl842            │
│ ● !350  Move webhook config to settings @loctvl..  │
│ ● !341  Webhook timeouts @loctvl842  [backend]     │
└────────────────────────────────────────────────────┘
```

Free words (`webhook`) are searched by GitLab in title and description. Flags narrow by field.

─────────────────────────────────────────
STATE 4 - A new search is running (user just typed). The previous list stays on screen; a small spinner replaces the count:

```
│ > state:opened author:@me retry              ⠋     │
├────────────────────────────────────────────────────┤
│▌○ !418  Bump rails to 7.1 @mina                    │   <- old results, until the new ones land
```

─────────────────────────────────────────
STATE 5 - Search failed, a flag is wrong, or nothing was found. One quiet line in the list, no popup:

```
│ > state:opened author:nobody-here                  │
├────────────────────────────────────────────────────┤
│  GitLab could not run this search:                 │
│  user "nobody-here" was not found                  │
```

```
│ > state:opened colour:red                          │
├────────────────────────────────────────────────────┤
│  Unknown filter "colour:". Available: state,       │
│  author, assignee, reviewer, label, milestone,     │
│  draft, source, target, sort, project              │
```

```
│ > state:opened label:does-not-exist           0/0  │
├────────────────────────────────────────────────────┤
│  No results for this search                        │
```

─────────────────────────────────────────
STATE 6 - Drill-down, same keys as the GitHub pickers. From a merge request, one key shows the files it changes and another its commits; from there a key shows a commit's files, and a key searches text inside the chosen set:

```
┌─ MR Retry failed webhooks with backoff > Files Changed (6) ─┐
│▌ app/jobs/webhook_retry.rb                                  │
│  app/models/webhook.rb                                      │
│  config/initializers/sidekiq.rb                             │
│  ...                                                        │
└─────────────────────────────────────────────────────────────┘
   <BS> back   <C-t> commits   Enter open diff
```

The path crumbs, hints and rows look like the GitHub chain, only the wording says "MR" instead of "PR".

---

# Scenarios

## 1 - Skim open merge requests (happy path)

```
Step 1: Press <leader>gmr inside a repo that has a GitLab remote.
  The picker opens with "state:opened " in the prompt, cursor at the end.
  The list fills with the project's open merge requests, newest first.

Step 2: Press Down / Up (or Ctrl-n / Ctrl-p) to move through the list.
  The preview follows. The header (title, state, author, labels, branches) appears at once;
  the description and conversation fill in a moment later.

Step 3: Go back to one already visited.
  Its preview appears instantly, it is not fetched again while the picker is open.
```

## 2 - Look at merged or closed work by editing the text

```
Step 1: Change "state:opened" to "state:merged".
  A spinner shows briefly, then the list is merged requests only.

Step 2: Append "author:@me".
  Only merged requests authored by the user remain.

Step 3: Append "label:backend label:payments".
  Only requests carrying both labels remain.
```

## 3 - Words and flags together

```
Step 1: Type " retry" after the default text.
  Prompt: "state:opened retry"
  GitLab finds open requests mentioning "retry" in title or description.

Step 2: Type ' "exponential backoff"'.
  Quoted words are searched as one phrase.
```

## 4 - Draft, branches and ordering (merge requests)

```
Step 1: Add "draft:no" to hide work-in-progress requests, or "draft:yes" to see only them.
Step 2: Add "target:main" or "source:retry-backoff" to filter by branch.
Step 3: Add "sort:updated" to order by last update instead of newest created.
```

## 5 - Another project

```
Step 1: Type "project:platform/billing/core state:opened".
  The list shows that project's open merge requests. The title bar now reads
  "Merge Requests - platform/billing/core". The server is still the one found from the remotes.
```

Without `project:`, the search is always limited to the current project.

## 6 - Self-hosted GitLab

```
Step 1: The repo's remote is git@git.acme.dev:platform/payments/api.git and the host name contains "gitlab"
  (for example gitlab.acme.dev). Press <leader>gmr.
  The picker opens, title "Merge Requests - gitlab.acme.dev/platform/payments/api".
  Nothing was configured: the server comes from the remote.

Step 2: The host name does NOT contain "gitlab" (git.acme.dev).
  The keys are not offered and a direct open shows a toast:
  'git.acme.dev is not known as a GitLab server. Add it to the remote hosts setting.'
  After adding it once, the keys appear and everything above works.
```

## 7 - Open or copy the highlighted item

```
Step 1: Press Enter on a row.
  The picker closes and the merge request or issue opens in the default web browser.

Step 2 (alternative): Press Ctrl-y instead.
  The URL is copied, the picker stays open, a toast confirms.
```

## 8 - Drill into a merge request

```
Step 1: On a merge request press the same key as GitHub's "files changed".
  The picker becomes the list of files the request changes; the preview is that file's diff.
  Enter opens the diff in a scratch buffer, Backspace on an empty prompt goes back.

Step 2: Back on the request, press the "commits" key.
  The picker lists the request's commits, newest first, with a diff preview per commit.
  From a commit, the "files" key lists that commit's files, the "search" key searches text
  inside the commits' changes.

Step 3: On an issue, press the "search" key.
  A text search runs over the title and description of the issues currently listed.
```

A very large merge request can be cut by GitLab itself; the list then ends with a line saying that more files exist ("showing the first N files, open in the browser for all").

## 9 - Typing fast, slow network

```
Step 1: Type "retry" quickly, then keep typing " label:backend".
  Only one search starts, after the user pauses for a moment.
  A slower, older search that finishes after a newer one is thrown away.
```

## 10 - Cannot run (error and edge cases)

```
Case A: <leader>gmr in a folder with no GitLab remote.
  The keys are not offered; a direct open shows the toast "No GitLab remote found for this directory".

Case B: "glab" is not installed.
  Toast: "GitLab CLI (glab) is not installed".

Case C: glab is installed but not logged in to this server.
  Toast: "Run `glab auth login --hostname gitlab.acme.dev` first" (names the actual host).

Case D: A flag the picker does not know (colour:red), or a value GitLab rejects (author:nobody).
  One line in the list (STATE 5), never a popup. Fixing the text brings results back on its own.

Case E: The search really fails (project not found or no access, rate limit, network, login expired).
  One-line reason in the list. A rate limit says when it resets.

Case F: Valid search with no matches.
  "No results for this search", count 0/0.

Case G: More than 100 matches.
  The newest 100 are shown and the count reads "100+".

Case H: The repo has both a GitHub and a GitLab remote (a mirror).
  Both sets of keys are offered; each picker uses its own remote.

Case I: A very old self-hosted GitLab lacks a field (for example the pipeline status).
  That line is simply missing in the preview. Nothing errors.
```

## 11 - Cancel

```
Step 1: Press Esc (normal mode) or Ctrl-c at any time.
  The picker closes. Nothing is opened or copied. A running search is dropped.
```

---

# Behavior Rules

- The picker is a separate pair of pickers for GitLab; the GitHub pickers behave exactly as before.
- Merge requests and issues are never mixed in one list (GitLab has no combined search). The kind is chosen by the key, not by the text.
- The prompt has two kinds of parts: `flag:value` pairs and free words. Free words are searched by GitLab (title and description), not fuzzy-matched locally. Double quotes keep a phrase together.
- Flags, with their values:
  - `state:` `opened` (also `open`), `closed`, `merged` (merge requests only), `all`. Default `opened`.
  - `author:` `assignee:` `reviewer:` a username, or `@me` for the logged-in user. `reviewer:` is for merge requests. `assignee:none` finds unassigned.
  - `label:` a label name (quotes for spaces). Repeating it requires all of them. `label:none` finds unlabelled.
  - `milestone:` a milestone title.
  - `draft:` `yes` / `no` (merge requests only).
  - `source:` `target:` a branch name (merge requests only).
  - `sort:` `created` (default, newest first) or `updated`, with an optional `-asc` suffix.
  - `project:` the full path of another project on the same server.
- A flag that does not apply to the picker (`draft:` in the issue picker, `state:merged` for issues) is reported like an unknown one, in the list.
- Results are limited to the project of the current directory unless the text has `project:`.
- At most 100 results are loaded. The list is not paginated.
- A new search starts only after typing pauses. While it runs, the old list stays and a spinner replaces the count. Out-of-date answers never overwrite newer ones.
- Errors and empty results appear inside the list. Only "cannot start at all" problems (no remote, no `glab`, not logged in, host not known as GitLab) use a toast.
- Preview: what is known from the list shows instantly; description and conversation arrive after. Fetched previews are kept until the picker closes. The preview is read-only.
- Reopening starts from the default text, not the last query.
- Enter opens in the browser. Ctrl-y copies the URL. Ctrl-s and Ctrl-v do nothing.
- Chains and their keys are the same as the GitHub pickers (files changed, commits, commit files, search text); the crumbs say "MR".
- Key bindings: `<leader>gmr` merge requests, `<leader>gmi` issues, group "GitLab". Offered only when the project has a GitLab remote.
- Colors of state icons: open green, draft grey, merged purple, closed red. Same palette as GitHub.
- The server is never typed by the user: it always comes from the git remotes (the first GitLab remote, `origin` preferred), so nested groups and custom ports in the remote work as written.

---

# Success Criteria

- [ ] In a repo with a gitlab.com remote, `<leader>gmr` and `<leader>gmi` open pickers with `state:opened ` in the prompt and the cursor at its end.
- [ ] In a repo whose remote is a self-hosted GitLab (host name containing "gitlab"), the same keys work with no configuration and the title names that server.
- [ ] A host that does not contain "gitlab" works after being added once to the remote hosts setting; before that, the user gets a toast that names the host and what to do.
- [ ] The list shows state icon, `!`/`#` number, title, author and label badges; nested group paths are shown in full.
- [ ] Editing flags and words changes the list accordingly: state, author (`@me` too), label (several), draft, branches, sort, milestone, another project.
- [ ] Moving the cursor shows a preview with metadata, description and conversation (human comments only); revisiting is instant.
- [ ] Typing fast results in one search; the list never shows results for an older text; the old list stays while the spinner runs.
- [ ] Unknown or inapplicable flags, rejected values, failed searches and empty results each show one in-list line, no popup.
- [ ] No remote / no `glab` / not logged in shows a clear toast naming the host, and does not open an empty picker.
- [ ] Enter opens the browser, Ctrl-y copies the URL, Esc closes without side effects.
- [ ] Merge request: files changed, commits, commit files and search text work with the same keys as GitHub; a cut-short file list says so.
- [ ] Issue: search text over the listed issues works with the same key as GitHub.
- [ ] The GitHub pickers are unchanged.
- [ ] Look and keys match the existing finder pickers.

---

# Out of Scope

- Write actions: commenting, approving, merging, closing, labelling. Deferred, v1 is for scanning.
- Checking out a merge request branch or reviewing its diff as a review thread.
- An in-editor page for a merge request or issue (Enter opens the browser).
- Pipelines, jobs, environments, releases and other GitLab areas.
- Mixed merge request and issue list; GitLab's own query language (GLQL) as the prompt.
- Autocomplete or highlighting of flags in the prompt.
- Paging beyond 100 results, remembering the last query.
- Choosing a different remote than the first GitLab one (a repo with two different GitLab servers).
- Other forges (Bitbucket, Gitea).
