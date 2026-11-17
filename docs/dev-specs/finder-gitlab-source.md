---
name: finder-gitlab-source
description: GitLab merge request and issue pickers in the finder on top of `glab api`, with the same drill-down as GitHub; the shared chain, preview and commit sources dispatch on `item.provider`, the host and project path come from `Git.remote("gitlab")`
generated: 2026-11-18
---

> PM Spec: [docs/pm-specs/finder-gitlab-source.md](../pm-specs/finder-gitlab-source.md)

# TL;DR
Read only this; the rest is detail for the implementer.
- **Order:** refactor first, feature after. Phase 2 extracts the shared pieces (pager, forge dispatcher, `tokens`) with every GitHub test unchanged, so GitLab code never copies GitHub code.
- **Phase 1:** `Git.remote` accepts nested group paths (`platform/payments/api`). Tiny.
- **Phase 2:** the refactor above. No behavior change for GitHub.
- **Phase 3:** `<leader>gmr` / `<leader>gmi` pickers with filter flags and preview.
- **Phase 4:** drill-down (files, commits, commit files, issue grep) reusing the existing sources.
- **Phase 5:** self-hosted replay tests, live run on your test project, docs.
- **Only decision that changes the approved PM spec:** D1, the MR preview shows `Changes: N files` without `+a -d` (GitLab's API has no totals).

---

# Summary
Add two live sources, `gl_mr` and `gl_issue`, that turn the prompt text (`state:opened author:@me label:bug retry`) into GitLab REST parameters, run them through `glab api --hostname <host>`, and feed normalized items into the same finder pipeline the GitHub sources use. Drill-down reuses the existing `gh_pr_files`, `gh_commits`, `gh_commit_files` and `gh_issue_grep` sources: items carry a `provider`, and a small `source/forge.lua` picks the GitHub or GitLab API module for them. Host detection is already done by `Git.remote("gitlab")`; it only needs to accept nested group paths.

---

# Context

## Problem
The finder's GitHub support is a vertical slice that knows only GitHub: `gh/api.lua` shells out to `gh`, normalizes GitHub JSON into `Beast.Finder.Gh.*` shapes, and the shared sources (`gh_pr_files`, `gh_commits`, `gh_commit_files`, `gh_issue_grep`, `gh/preview.lua`, `gh/commit_preview.lua`) call that module directly. Nothing parses GitLab's API, its query model (REST filter parameters, not a search string), its states, its `!iid` references or its nested project paths. `Git.parse` also rejects a remote such as `git@git.acme.dev:platform/payments/api.git` because it only accepts `owner/name`.

### Solution
After this change a `gl/` API module normalizes GitLab JSON into the same item, file, commit and detail shapes, `gl/query.lua` turns prompt flags into parameters, and `gl.lua` is the live-source factory (twin of `gh.lua`). The shared sources and the preview get their API from `forge.api(item)` (GitHub when `item.provider` is nil, so every existing GitHub test is untouched), and show `!12`/`#12`, "MR"/"PR" and "Project"/"Repo" from item fields instead of literals. Keys `<leader>gmr` and `<leader>gmi` are registered with `cond = on_gitlab`.

---

# Research

### Repo Search
- Searched for: `parse_remote`, `Git.remote`, `has_provider`, `gh_pr`, `gh_issue`, `gh_commits`, `gh_pr_files`, `provider`, `"gh"`, `reltime`, `item.url`, `pr_label`, `gh_state`, `format.gh`, `tests/helpers/gh.lua`, chain `edges`.
- Found:
  - `lua/beast/libs/git/remote.lua:41` `M.parse(url)`: https, `ssh://` (with port) and scp-like; its last check `path:match("^[^/]+/[^/]+$")` rejects nested groups. `provider_of(host)` already returns `"gitlab"` for any host containing "gitlab" or listed in `config.remote.hosts`; `Git.remote("gitlab", root)` and `has_provider` already exist.
  - `lua/beast/init.lua:381` `on_github()` + `cond = on_github` on `<leader>ghp`/`<leader>ghi`; `cfg.git` is applied to the git config before the check (`remote.hosts` override works for self-hosted).
  - `finder/source/gh.lua`: live-source factory (generation counter, `retain_results`, `run_when_empty`, `debounce_ms`, `initial_query`, `count`, `title`, `check`, message rows). `gh_pr.lua`/`gh_issue.lua` are one-liners.
  - `finder/source/gh/api.lua`: `repo`, `check`, `normalize`, `classify`, `search`, `files`/`commits`/`commit` (shared local `pages()` paginator, `FILES_PAGES = 3`, truncation probe), `detail`/`normalize_detail`. Returns `Beast.Finder.Gh.Handle` (`kill`) and always calls back on the main loop.
  - `finder/source/gh/preview.lua`: `build(item, detail, failure)` is pure and testable; literals `#%d`, "Repo", "PR"/"Issue" title, `Checks`/`Mergeable`/`Changes` block; `epoch()` ignores a UTC offset in a timestamp (GitLab commit timestamps are `+07:00`).
  - `finder/source/gh/commit_preview.lua`: `M.detail` calls `api.commit(item.pr, sha)`; the commit message is read from `item.body`, `detail.message` is unused.
  - `finder/chains.lua`: closed edge table keyed `from|to`; `files_in_pr`, `commits_in_pr`, `grep_issues` hints use `"#" .. number`; `pr_files`/`pr_commits` open `ctx = { pr = pr }`. `format.pr_label` hardcodes "PR ". `finder/action.lua:12` prints `"%s#%d: %s"`.
  - `tests/helpers/gh.lua`: scripted `vim.system` keyed by command-line prefix (generic, not GitHub specific), builders for items/files/commits; `tests/test-finder-source-contract.lua` lists every source with a sample item.
  - `finder/source/init.lua:28` `Beast.Finder.Source` alias enumerates source names.
- Live probe against gitlab.com with `glab 1.130.0` (results that fix the design):
  - `glab api -X GET <path> -f k=v` sends `k=v` as query parameters; field names containing `[]` are rejected in JSON bodies (POST only matters for test setup).
  - `--include` prints status line and headers before the body, also for a 404 (so `Retry-After` / `RateLimit-Reset` are readable on a 429 without a second request). List responses carry `X-Total` (absent for very large sets), `X-Next-Page`.
  - Errors: exit 1, stdout `{"message":"404 Project Not Found"}`, stderr `glab: 404 Project Not Found (HTTP 404)`. Unknown host: exit 1, stderr `ERROR Get "https://git.acme.dev/api/v4/user": ... no such host`. `glab auth status --hostname H` exits 0 when logged in, 1 otherwise.
  - A nonexistent `author_username` returns `[]` with exit 0 (no error), so "user not found" needs a second request (`GET users?username=`, `[]` when absent).
  - Params verified on the list endpoints: `state` (opened/closed/merged/all), `draft=yes|no`, `labels=a,b` (AND), `assignee_id=None`, `reviewer_username`, `author_username`, `order_by=created_at|updated_at`, `sort`, `search` (+ `in=title,description` for issues), `with_labels_details=true` (labels become `{name, color:"#rrggbb"}`; without it, plain names).
  - MR single GET has `head_pipeline.status`, `detailed_merge_status`, `changes_count` (a string), `reviewers`, `assignees`, `milestone`, `merged_at`, `closed_at`, `target_branch`, `source_branch`; it has NO line additions/deletions.
  - `/merge_requests/:iid/diffs` and `/repository/commits/:sha/diff`: per file `old_path`, `new_path`, `new_file`, `deleted_file`, `renamed_file`, `too_large`, `collapsed`, `diff` (hunks only, starts at `@@`, same as GitHub's `patch`), no addition/deletion counts.
  - `/merge_requests/:iid/commits` is NEWEST first (GitHub's is oldest first); commit `created_at` carries an offset (`2026-11-18T00:06:11.000+07:00`); fields `id`, `short_id`, `title`, `message`, `author_name`.
  - `/notes` has `system` (true for "added label ~bug" lines); `user_notes_count` is on the list payload; the list payload carries `description`, `references.full`, `web_url`.
- Test project for live runs (created for this feature): https://gitlab.com/loctvl842/glab-finder-test, local clone `~/Documents/Playground/glab-finder-test`. Merge requests: !1 draft, !2 open (docs), !3 merged, !4 closed, !5 open with conflicts, !6 open with 3 commits, a rename, an added and a deleted file, one reviewer and one note. Issues: #1 (bug, backend, milestone, one note), #2 docs, #3 bug + scoped `priority::high`, #4 closed.
- Reuse opportunity: Yes. Reuse the live-source skeleton, preview builder, diff renderer, commit preview, chain machinery, label badges and state highlights as they are; extract `tokens` from `gh/query.lua` and the paginator from `gh/api.lua`.

### Built-in / Existing Lib Check
- Checked: `vim.system`, `vim.json.decode`, `vim.uri_encode`, `vim.ui.open`, `Git.remote`, `finder.format`, `finder.highlights`, `libs/git/config.lua`.
- Found: `Git.remote("gitlab")` returns `{ host, slug, url, name }`; `vim.uri_encode(slug, "rfc3986")` leaves `/` as is, so the project id needs `slug:gsub("/", "%%2F")` (plain gsub, no lib needed). Nothing in the repo speaks GitLab.
- Decision: **Reuse** (everything above) + **Build** (`gl/api.lua`, `gl/query.lua`, `gl.lua`, `gl_mr.lua`, `gl_issue.lua`, `forge.lua`) + small **Modify** of the shared sources. No new dependency.

---

# Decisions

| # | Question | Recommendation | Alternative |
|---|---|---|---|
| D1 | MR "Changes" line | **`Changes: 6 files`** (from `changes_count`), no `+a -d`: GitLab's REST MR payload has no line totals. **This differs from the PM spec mock (`+141 -23`); the PM spec mock must be fixed to match** | One extra GraphQL call (`diffStatsSummary`) per MR preview; untestable on old self-hosted, more code |
| D2 | Names of the shared chain sources | **Keep `gh_pr_files`, `gh_commits`, `gh_commit_files`, `gh_issue_grep`**, dispatch on `item.provider`; document that they are forge-neutral. Zero churn in tests and configs | Rename to `forge_*` now (touches ~10 tests, chain edge ids, user chain config) |
| D3 | `@me` | **Resolve the username once per host** (`glab api user`, cached per session) and send `*_username` | Use `scope=created_by_me/assigned_to_me`; breaks when two `@me` flags combine |
| D4 | Unknown username (`author:nobody`) | **When the result is empty and a user flag was used, ask `users?username=`; empty answer shows `user "nobody" was not found`** (keeps the PM spec promise, one extra request only on empty results) | Plain "No results" |
| D5 | Rate limit reset time | **Read `Retry-After` / `RateLimit-Reset` from the `--include` headers of the failed call** (no extra request) | Fixed message without time |
| D6 | Not-logged-in check at open | **`glab auth status --hostname H` synchronously (timeout 5 s)**, like gh's `auth token` check but with one network round trip | Skip the check, let the first search return 401 (picker opens empty, then shows the error) |
| D7 | Pagination helper | **Extract `gh/api.lua`'s local `pages()` into `source/pager.lua`** (takes a `run(page, done)`), used by both | Copy it into `gl/api.lua` (35 duplicated lines) |
| D8 | Keys | **`<leader>gmr`, `<leader>gmi`**, group "GitLab" (`<leader>gl` is blame, a `gl` prefix would clash) | `<leader>gg*` |
| D9 | `item.kind` for a merge request | **Stay `"pr"`** (internal kind); the user-facing word comes from `provider` | New kind `"mr"`; every `kind == "pr"` branch changes |

---

# Architecture Changes

## Normalized shapes (no new types for the shared code)
`Beast.Finder.Gh.Item` gains optional `provider` (`"github"` default | `"gitlab"`) and `ref` (display reference `"#30"`, `"!412"`, set by both APIs; GitHub gets `"#"..number` in `normalize`). `Detail` gains optional `pipeline` (string), `reviewers`, `assignees` (`string[]`), `milestone` (string); GitHub leaves them nil and keeps `checks`. `File`, `Commit`, `CommitDetail` are unchanged: the GitLab API fills them (additions/deletions counted from the hunks, status from `new_file/deleted_file/renamed_file`, commits reversed to oldest first, `short = short_id`).

## Files
| Path | New/Modified | What |
|---|---|---|
| `lua/beast/libs/git/remote.lua` | Modified | `parse` accepts nested group paths (`a/b/c`); GitHub slugs unchanged |
| `lua/beast/libs/finder/source/forge.lua` | New | `api(item)` (`gh/api` or `gl/api` by `item.provider`), `name(item)` ("GitHub"/"GitLab"), `words(item)` (`MR`/`PR`, `Project`/`Repo`), tiny and pure |
| `lua/beast/libs/finder/source/pager.lua` | New | generic page loop with the `FILES_PAGES` cap and truncation probe, extracted from `gh/api.lua` |
| `lua/beast/libs/finder/source/gh/api.lua` | Modified | uses `pager`; items get `ref` |
| `lua/beast/libs/finder/source/gh/query.lua` | Modified | export `tokens` (was local); no behavior change |
| `lua/beast/libs/finder/source/gl/api.lua` | New | `repo`, `check`, `me`, `search`, `files`, `commits`, `commit`, `detail`, `user_exists`; all `glab api` calls, `classify`, normalizers |
| `lua/beast/libs/finder/source/gl/query.lua` | New | `default_text`, `parse(text, kind)` -> params / words / project / error, `scope`, flag tables |
| `lua/beast/libs/finder/source/gl.lua` | New | `create(kind)` factory twin of `gh.lua` |
| `lua/beast/libs/finder/source/gl_mr.lua`, `gl_issue.lua` | New | one-line instances |
| `lua/beast/libs/finder/source/init.lua` | Modified | add `gl_mr`, `gl_issue` to `Beast.Finder.Source` |
| `lua/beast/libs/finder/source/gh_pr_files.lua`, `gh_commits.lua`, `gh_commit_files.lua`, `gh_issue_grep.lua` | Modified | `forge.api(owner)` instead of the `gh` module; messages say the provider name; commit url per provider |
| `lua/beast/libs/finder/source/gh/preview.lua` | Modified | `ref`, MR/PR and Project/Repo words, optional extra fields (pipeline, reviewers, assignees, milestone), `epoch()` honors a UTC offset, detail via `forge.api(item).detail` |
| `lua/beast/libs/finder/source/gh/commit_preview.lua` | Modified | `forge.api(item.pr).commit` |
| `lua/beast/libs/finder/format.lua` | Modified | `gh` and `gh_issue_grep_header` print `item.ref`; `pr_label` says MR for GitLab |
| `lua/beast/libs/finder/chains.lua` | Modified | edges `gl_mr -> gh_pr_files` (`<C-g>`), `gl_mr -> gh_commits` (`<C-t>`), `gl_issue -> gh_issue_grep` (`<C-g>`); hints use `ref` |
| `lua/beast/libs/finder/action.lua` | Modified | the `owner#number: file` line uses `ref` |
| `lua/beast/init.lua` | Modified | `on_gitlab()` + two keys |
| `tests/test-git-remote.lua` | Modified | nested path cases |
| `tests/helpers/gl.lua` | New | builders for GitLab JSON (MR, issue, diff file, commit, note) over `tests/helpers/gh.lua`'s scripted `vim.system` |
| `tests/test-finder-gl-query.lua`, `-gl-api.lua`, `-gl-source.lua`, `-gl-preview.lua`, `-gl-chains.lua`, `-gl-selfhosted.lua` | New | see Testing Strategy |
| `tests/fixtures/gitlab/*.json` | New | JSON recorded from gitlab.com, replayed under a fake host |
| `tests/test-finder-source-contract.lua` | Modified | `gl_mr`, `gl_issue` samples |
| `docs/CODEMAP/libraries.md` | Modified | finder section: new files, forge dispatch |

## Request map (`glab api -X GET --hostname H --include <path> -f ...`, `ID` = project path with `/` as `%2F`)

| Need | Path | Parameters |
|---|---|---|
| list MRs / issues | `projects/ID/merge_requests` / `projects/ID/issues` | from the prompt + `per_page=100`, `with_labels_details=true`, default `state=opened`, `order_by=created_at`, `sort=desc` |
| me | `user` | none (cached per host) |
| user exists | `users` | `username=X` |
| MR / issue detail | `projects/ID/merge_requests/IID`, `projects/ID/issues/IID` | none |
| conversation | `.../IID/notes` | `sort=asc`, `order_by=created_at`, `per_page=100`; entries with `system=true` dropped |
| MR files | `.../merge_requests/IID/diffs` | `per_page=100`, `page=N` |
| MR commits | `.../merge_requests/IID/commits` | `per_page=100`, `page=N`; reversed to oldest first |
| commit files | `projects/ID/repository/commits/SHA/diff` | `per_page=100`, `page=N` |

Flag translation (`gl/query.lua`): `state` (`open`->`opened`; `merged` MR only) -> `state`; `author` -> `author_username`; `assignee` -> `assignee_username` (`none` -> `assignee_id=None`); `reviewer` (MR) -> `reviewer_username`; `label` (repeatable) -> `labels=a,b` (`none` -> `labels=None`); `milestone` -> `milestone`; `draft` (MR) `yes|no` -> `draft`; `source` -> `source_branch`; `target` -> `target_branch`; `sort` (`created|updated` + `-asc`) -> `order_by`, `sort`; `project` -> the path of the request, not a parameter; free words -> `search` (+ `in=title,description` for issues). `@me` is replaced by the cached username. Unknown or inapplicable flag -> an error string and no request.

## Implementation Phases

## Phase 1: Remote accepts nested groups — a self-hosted slug like `platform/payments/api` survives `Git.remote`
1. **Allow nested paths** (File: `lua/beast/libs/git/remote.lua`)
   - Action: change the final path test in `M.parse` from exactly two segments to two or more (`^[^/]+/.+$`); keep stripping `.git` and trailing `/`. `provider_of` and the rest are untouched.
   - Why: GitLab projects live under groups and subgroups; today such a remote is dropped silently and the keys never appear.
   - Depends on: None
   - Risk: Low (a GitHub URL with extra segments, which is not valid, now parses instead of returning nil)
2. **Tests** (File: `tests/test-git-remote.lua`)
   - Action: add `https://gitlab.acme.dev/platform/payments/api.git`, `git@git.acme.dev:a/b/c/d.git`, `ssh://git@host:2222/g/sub/p.git` (port), a URL with `oauth2:token@`; assert `slug`, `host`, and `provider_of` with `config.remote.hosts = { ["git.acme.dev"] = "gitlab" }`. Existing cases must still pass.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Forge seams — the finder dispatches on `item.provider`, GitHub unchanged
1. **Pager** (File: `lua/beast/libs/finder/source/pager.lua`, `gh/api.lua`)
   - Action: move the page loop out of `gh/api.lua`'s local `pages()` into `pager.collect(run, normalize, cb)` where `run(page, done)` performs one request and calls `done(err_result | list)`; `gh/api.lua` passes its `gh api ...` runner. Keep `M.FILES_PAGES`, `M.PER_PAGE`, kill semantics and the truncation probe byte-for-byte equivalent.
   - Why: D7. Two users of one algorithm.
   - Depends on: None
   - Risk: Medium (pagination and `kill()` timing); `tests/test-finder-gh-files-api.lua` and `-gh-commits-api.lua` are the net.
2. **Forge helper** (File: `lua/beast/libs/finder/source/forge.lua`)
   - Action: `api(item)` returns `require("beast.libs.finder.source.gl.api")` for `item.provider == "gitlab"`, else `gh.api` (nil provider = GitHub); `name(item)`, `words(item)` as in the table above.
   - Why: single place that knows two providers.
   - Depends on: None
   - Risk: Low
3. **References** (File: `gh/api.lua`, `format.lua`, `chains.lua`, `action.lua`, `gh_issue_grep.lua`)
   - Action: `gh/api.normalize` sets `provider = "github"`, `ref = "#"..number`; every place that formats `"#" .. number` or `"PR "` reads `item.ref` / `forge.words(item)` with a `"#"..number` fallback for items built without `ref` (tests, other sources).
   - Why: `!412` and "MR" must come from the data, not literals.
   - Depends on: Step 2
   - Risk: Low
4. **Shared sources use the dispatcher** (File: `gh_pr_files.lua`, `gh_commits.lua`, `gh_commit_files.lua`, `gh/commit_preview.lua`, `gh/preview.lua`)
   - Action: replace `api.files/commits/commit/detail` by `forge.api(owner).…`; "GitHub could not list ..." becomes `forge.name(owner) .. " could not list ..."`; the commit `url` comes from `forge.api(pr).commit_url(pr, sha)`; `preview.build` draws `ref`, the Project/Repo label, an MR/PR title and the optional extra fields only when present; `checks_text` is skipped when `detail.checks` is nil. `epoch()` parses an optional `.fff` and `Z|±hh:mm` suffix.
   - Why: lets Phase 3 and 4 plug in without touching these again.
   - Depends on: Steps 1 to 3
   - Risk: Medium (preview is used by every GitHub picker): run all `tests/test-finder-gh-*.lua` and `-chain-*.lua`.
5. **Extract `tokens`** (File: `gh/query.lua`)
   - Action: expose the local `tokens` function as `M.tokens`.
   - Depends on: None
   - Risk: Low
6. **Tests** (File: `tests/test-finder-gh-preview.lua`, new case)
   - Action: `epoch`/`reltime` with `+07:00`, `.000Z`, and plain `Z`; an item without `ref` still draws `#n`.
   - Depends on: Step 4
   - Risk: Low

## Phase 3: Browse — merge request and issue pickers with preview, `<leader>gmr` / `<leader>gmi`
1. **Query** (File: `lua/beast/libs/finder/source/gl/query.lua`, `tests/test-finder-gl-query.lua`)
   - Action: `default_text(kind)` = `"state:opened "`; `parse(text, kind)` splits with `gh.query.tokens`, handles quoted values and the flag table above, returns `{ params, project, words, users }` or `{ error }` with the PM spec wording (`Unknown filter "colour:". Available: ...`, the list differs for MR and issue); `scope(text, slug)` returns the project for the title bar.
   - Why: the prompt-to-parameters contract, pure and fully unit-testable.
   - Depends on: Phase 2 step 5
   - Risk: Low
2. **API: repo, check, search** (File: `lua/beast/libs/finder/source/gl/api.lua`)
   - Action: `repo(cwd)` = `Git.remote("gitlab", cwd)`; `check(cwd)`: `glab` executable, a GitLab remote (else, if another remote exists, name its host and point at the remote hosts setting), then `glab auth status --hostname H` (D6) with "Run `glab auth login --hostname H` first"; `me(host, cb)` cached; `search(kind, project, params, host, cb)` runs the list request with `--include`, splits headers and body, builds items (`provider="gitlab"`, `kind` pr|issue, `state` opened/open, merged, closed, `draft`, locked->closed, `ref` `!iid`/`#iid`, labels from `with_labels_details` with `#` stripped from the color, `comments = user_notes_count`, `body = description`, `url = web_url`, `repo` = project path, `author`), `total` from `X-Total` else `#items` plus "more" when `X-Next-Page` is set; `classify` maps 401/403/404/429/network/"no such host" to the PM spec messages and reads the reset time from the headers (D5); `user_exists(host, name, cb)` (D4). Same `Handle.kill` contract and callback-on-main-loop as gh.
   - Why: all network access of the feature in one module.
   - Depends on: Step 1
   - Risk: Medium (header/body split of `--include`, error shapes): covered by recorded fixtures.
3. **Source factory** (File: `lua/beast/libs/finder/source/gl.lua`, `gl_mr.lua`, `gl_issue.lua`, `source/init.lua`)
   - Action: copy the structure of `gh.lua` (generation guard, `live`, `retain_results`, `run_when_empty`, `debounce_ms = 400`, `initial_query`, `count`, `title`, `check`, `format = format.gh`, message rows); `get` parses the query first and answers with message rows when it has an error, sends one request otherwise, and on an empty answer with user flags runs `user_exists` before saying "No results" (D4). Titles "Merge Requests" / "Issues"; the title bar adds the host unless it is `gitlab.com`.
   - Why: PM spec States 1 to 5, scenarios 1 to 5, 9, 10.
   - Depends on: Steps 1 and 2
   - Risk: Medium
4. **Detail for the preview** (File: `gl/api.lua`)
   - Action: `detail(item, cb)` runs the item request and the notes request together and joins them: `body`, `base`=`target_branch`, `head`=`source_branch`, `mergeable` text from `detailed_merge_status` (`mergeable` -> "can be merged", `conflict` -> "conflicts", other -> its words with spaces), `files` from `changes_count`, `pipeline` from `head_pipeline.status` ("passed", "failed", "running", ...), `reviewers`, `assignees`, `milestone`, `closed`, `merged`, `conversation` from non-system notes. `commit_url(item, sha)` = `https://host/path/-/commit/sha`.
   - Why: preview fields of PM spec STATE 1 and 2 (with D1).
   - Depends on: Step 2
   - Risk: Low
5. **Keys** (File: `lua/beast/init.lua`)
   - Action: `on_gitlab()` = `Git.has_provider("gitlab", Util.root())`; add `<leader>gmr` (`open("gl_mr")`) and `<leader>gmi` (`open("gl_issue")`), `group = "GitLab"`, `cond = on_gitlab`, next to the GitHub keys.
   - Why: D8.
   - Depends on: Step 3
   - Risk: Low
6. **Tests** (File: `tests/test-finder-gl-api.lua`, `-gl-source.lua`, `-gl-preview.lua`, `tests/helpers/gl.lua`, contract test)
   - Action: list normalization for each state, `@me` once, flag-to-argv translation, `--include` split, each error class, stale-response drop, empty + unknown user, title with host, preview `build` for MR and issue, contract samples for `gl_mr` and `gl_issue`.
   - Depends on: Steps 1 to 4
   - Risk: Low

## Phase 4: Drill-down — files, commits, commit files, issue grep
1. **API: files, commits, commit** (File: `gl/api.lua`)
   - Action: `files(item, cb)` and `commits(item, cb)` through `pager` (the commits reversed to oldest first so `gh_commits` stays unchanged); `commit(item, sha, cb)` reads `repository/commits/SHA/diff`; normalizers per the Research (status from flags, patch nil when `too_large` or `collapsed`, additions and deletions counted from the hunks; commit `short` = `short_id`, `author` = `author_name`, `date` = `created_at`); `truncated` follows the same rule as gh.
   - Why: scenario 8.
   - Depends on: Phase 3
   - Risk: Medium (large diffs flagged `too_large`)
2. **Chains** (File: `lua/beast/libs/finder/chains.lua`)
   - Action: add edges `gl_mr -> gh_pr_files` (`<C-g>`, crumb "Merge Requests"), `gl_mr -> gh_commits` (`<C-t>`), `gl_issue -> gh_issue_grep` (`<C-g>`); hints say `files changed in !412`. All edges leaving `gh_commits`, `gh_pr_files`, `gh_commit_files` already apply because the level is the same source.
   - Why: full parity (PM spec scenario 8).
   - Depends on: Step 1
   - Risk: Low
3. **Tests** (File: `tests/test-finder-gl-chains.lua`, `-gl-api.lua`)
   - Action: files/commits/commit normalization from fixtures, commit order, truncation, the new edges (id, key, hint, `open` ctx), unchanged GitHub edges, `grep_local_copies` through a GitLab commit's files.
   - Depends on: Steps 1 and 2
   - Risk: Low

## Phase 5: Self-hosted coverage, E2E and docs
1. **Recorded fixtures** (File: `tests/fixtures/gitlab/`, `tests/test-finder-gl-selfhosted.lua`)
   - Action: record the real responses of the test project (`glab api --include ...`), replay them through the scripted `vim.system` under host `git.acme.dev` and project `platform/payments/api`; assert every argv contains `--hostname git.acme.dev`, a `%2F`-encoded project, that `check` names the host in its login message, that a remote with an unknown host gives the "add it to the remote hosts setting" toast and works after `config.remote.hosts` maps it, and that an nginx-style HTML 502 or a non-JSON body gives "unexpected response from GitLab".
   - Why: the user has no self-hosted GitLab: the only thing that differs there is the host, the path depth and the server version, all of which the replay pins.
   - Depends on: Phase 4
   - Risk: Low
2. **Live E2E on gitlab.com** (no file; follow the Testing Strategy list)
   - Action: run the PM spec scenarios in a real Neovim against `~/Documents/Playground/glab-finder-test` (and read-only against a public project for `project:`); report any visual problem found, even unrelated.
   - Depends on: Phase 4
   - Risk: Low
3. **Docs** (File: `docs/CODEMAP/libraries.md`, `lua/beast/libs/finder/docs/`)
   - Action: finder section lists the new files, the forge dispatch and the two keys; the chains doc lists the three new edges.
   - Depends on: Phase 4
   - Risk: Low

---

# Testing Strategy
- **Headless tests** (`nvim --clean --headless -l tests/<file>`, exit 0 = pass): new `test-finder-gl-query.lua`, `-gl-api.lua`, `-gl-source.lua`, `-gl-preview.lua`, `-gl-chains.lua`, `-gl-selfhosted.lua`; extended `test-git-remote.lua`, `test-finder-gh-preview.lua`, `test-finder-source-contract.lua`. Gate: the whole `tests/test-*.lua` set, especially every `test-finder-gh-*.lua` and `test-finder-chain-*.lua`, passes unchanged.
- **Type check:** `lua-language-server --check` as in DEVELOPMENT.md (new `@class` fields `provider`, `ref`, `pipeline`, ...).
- **Bench:** the finder is touched but no hot path (`matcher`, `topk`, `queue`, files pipeline) is; run `scripts/bench-finder-matcher.lua` once as a guard and the startup bench (`./scripts/bench-startup.sh`) because `lua/beast/init.lua` gains two keys and one `Git.has_provider` call at startup.
- **Manual (live, `NVIM_APPNAME=BeastVim`, in `~/Documents/Playground/glab-finder-test`):**
  - PM scenario 1: `<leader>gmr` shows !1 (draft), !2, !5, !6 open; preview of !6 shows branches `retry-backoff -> main`, reviewers, pipeline (none), `Changes: 5 files`, conversation without system notes.
  - Scenario 2/3/4: `state:merged` -> !3; `state:closed` -> !4; `state:opened label:backend`; `draft:yes` -> !1; `sort:updated`; `target:main`.
  - Scenario 5: `project:gitlab-org/cli` on a public project.
  - Scenario 7/8/9: Enter, `<C-y>`, `<C-g>` on !6 (5 files incl. rename, add, delete), `<C-t>` (3 commits, listed newest first), `<C-g>` on a commit, `<C-f>` on a commit; `<C-g>` on the issue list for the grep.
  - Scenario 10: no remote (a temp dir), `glab` removed from `PATH`, a logged-out host (`glab auth logout --hostname` on a copy of the config via `GLAB_CONFIG_DIR`), `colour:red`, `author:nobody`, a rate limit simulated by a fake `glab` script on `PATH`.
  - Scenario 6 (self-hosted) cannot run live; it is covered by the replay test (Phase 5 step 1) plus the unknown-host toast check done by setting the remote URL of a scratch clone to `git@git.acme.dev:platform/payments/api.git`.
  - Pixel check of every screen (alignment of `!6` vs `#12` columns, label badges for scoped labels, title bar with host).

# Success Criteria
(PM spec criteria, plus technical gates)
- [ ] In a repo with a gitlab.com remote, `<leader>gmr` and `<leader>gmi` open pickers with `state:opened ` in the prompt and the cursor at its end.
- [ ] A self-hosted remote (host containing "gitlab", nested group path) works with no configuration; the title names the server; every request carries `--hostname` and an encoded project path.
- [ ] A host without "gitlab" works after one `remote.hosts` entry; before that a toast names the host and the setting.
- [ ] Rows show state icon, `!`/`#` number, title, author and label badges (scoped labels as written).
- [ ] All flags work: state, author (incl. `@me`), assignee, reviewer, label (several, `none`), milestone, draft, source, target, sort, project; words are sent as `search`.
- [ ] Preview shows metadata, description and the human conversation; revisited previews are instant.
- [ ] Typing fast sends one search; stale answers are dropped; the old list stays with a spinner.
- [ ] Unknown or inapplicable flags, unknown users, failed searches (404, 401, 429 with reset time, network) and empty results each give one in-list line.
- [ ] No remote / no `glab` / not logged in gives a toast naming the host and does not open an empty picker.
- [ ] Enter opens the browser, `<C-y>` copies the URL, Esc closes without side effects.
- [ ] MR drill-down (files, commits, commit files, search text) and issue grep work with the same keys as GitHub; large or cut-short lists say so.
- [ ] Every existing GitHub test and picker behaves exactly as before (no diff in `tests/test-finder-gh-*.lua`).
- [ ] Type check, all headless tests, the finder bench and the startup bench show no regression.
- [ ] The PM spec STATE 1 mock is corrected for D1 (no `+a -d`) after the decision is confirmed.
