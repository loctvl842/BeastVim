---
name: finder-github-source
description: Add gh_pr and gh_issue live sources to the finder (GitHub search query as prompt text, gh api backend, in-picker preview), plus the small finder changes they need
generated: 2026-11-15
---

> PM Spec: [docs/pm-specs/finder-github-source.md](../pm-specs/finder-github-source.md)

# Summary
Two thin sources, `gh_pr` and `gh_issue`, built from one factory, run `gh api search/issues` with the prompt text as the query and feed the existing stream (live) pipeline. The finder itself needs four small, opt-in capabilities that no source has needed so far: a pre-filled prompt that searches on open, keeping the old list while a new search runs, in-list message rows, and a source-supplied preview renderer. All of them are off by default so `live_grep` behaves exactly as before.

---

# Context

## Problem
The finder's live pipeline assumes "empty prompt = nothing to show", clears the list on every keystroke, and its preview only knows how to show a file. A GitHub source needs the opposite on all three: it must search as soon as it opens (prompt pre-filled with `is:pr state:open `), keep the previous results visible while the next search is in flight, and preview an object that is not a file. Nothing in the finder fetches from GitHub, and there is no per-source title, debounce, or result count.

### Solution
After this change a source can declare `initial_query`, `retain_results`, `run_when_empty`, `debounce_ms`, `title`, `check`, `preview`. The GitHub sources use all of them; every other source declares none and is untouched. GitHub logic lives in `source/gh/` (query building, API calls, preview) and is testable headless with `vim.system` stubbed.

---

# Research

### Repo Search
- Searched for: `live = true` sources, `stream` pipeline, `initial_text`, `set_text`/prompt prefill, `vim.system`, `vim.ui.open`, `Toast(`, count display, `preview` hooks, `open_split`.
- Found:
  - Stream pipeline (`pipeline/stream.lua`) clears `query.items`/`matched` and renders an empty list at the start of every run, and returns early (clears) when `filter.pattern == ""`. It is the only live pipeline and `live_grep` is its only user.
  - `ui/input.lua` has no initial text, no count; it has a right-aligned spinner extmark (`start_spinner`/`stop_spinner`) that can host the "spinner replaces the count" behavior.
  - `ui/preview.lua` `show()` only handles `item.file` (text or image). `render.schedule_preview` calls it directly; `on_preview` is the only hook.
  - `State:new` derives the title from the source name and the input debounce from `source.live` (`config.debounce.live_ms`, 200 ms). No per-source override.
  - `action.open`/`copy_path` assume `item.file`. `keymaps.lua` list-pane `<C-s>`/`<C-v>` close the picker before calling `open_split`, even when `item.file` is nil.
  - Factory pattern for thin sources already exists: `source/lsp.lua` `create(method, label)` plus one-line `lsp_*.lua` files; format functions are looked up by `source.name`.
  - No `vim.system` or `vim.ui.open` use inside `finder/`; no result count anywhere in the finder.
  - Keys for finder pickers live in `lua/beast/init.lua` in `packer.lazy("beast.libs.finder", { keys = ... })`. `<leader>gh*` is free (`<leader>gp` = preview hunk).
  - Tests: `tests/test-finder-*.lua` use a hand-rolled `assert_test`, stub `render`/`ui` via `package.loaded`, run with `nvim --clean --headless -l`. Benches: `scripts/bench-grep.lua` covers the live path; `scripts/bench-ux.sh` covers input-to-paint.
- Reuse opportunity: **Yes** - stream pipeline, `lsp.lua` factory pattern, input spinner, `Toast`, `Util.debounce`, test scaffolding.

### Built-in / Existing Lib Check
- Checked: `vim.system` (async process, kill), `vim.ui.open`, `gh api` / `gh pr view --json` / `gh auth token`, Toast lib, existing view/buf/win helpers.
- Found, verified directly against `gh` 2.102 on this repo:
  - `gh api -X GET search/issues -f q=... -f per_page=100` returns PRs and issues in one list (`pull_request` present on PRs, `draft`, `state`, `labels`, `user`, `html_url`, `created_at`, `updated_at`, `comments`); merged PRs carry `pull_request.merged_at`.
  - `sort:updated-asc` and `author:@me` work inside `q`, so user-typed qualifiers need no translation. Without `sort:` the API default is best match, so we append `sort:created-desc`.
  - **Invalid qualifiers do not error.** `state:opn`, `state:`, `foo:bar` and an unterminated `label:"` all return `total_count: 0` with HTTP 200. Real errors are HTTP 422 (repo not found / no access), 403/429 (rate limit), auth and network failures.
  - Search API limit is 30 requests/minute (`gh api rate_limit` shows `"limit":30`).
  - `gh pr view N --json ...` gives branches, `mergeable`, `additions/deletions/changedFiles`, `statusCheckRollup`, `comments`, `reviews`, `body` in one call; `gh issue view` equivalent. Both take `--repo`.
  - `gh auth token --hostname H` is local (about 60 ms, no network) and exits 1 when not logged in; `git remote get-url origin` is about 5 ms.
  - The reference (snacks) delegates to its own `Api.list` which was not read in detail; behavior above was checked against `gh` directly instead.
- Decision: **Reuse** the stream pipeline and factory pattern; **Use** `gh api` + `vim.system` + `vim.ui.open`; **Build** the query builder, API wrapper, preview renderer, and four opt-in finder capabilities.

---

# PM Spec Gaps (need your call before implementing)

1. **Invalid qualifiers are not errors.** PM spec STATE 5 and scenario 8C promise a line like "The value 'opn' is not valid for qualifier state". GitHub returns an empty result, so the user would see "No results for this search" instead. Real error lines remain for: repo not found (422), rate limit (with reset time), network, auth. **Proposed resolution:** keep the error-line mechanism, change the PM example to "repo not found", and let invalid qualifiers show "No results". PM spec is updated to match if you agree.
2. **"Same count as other pickers" does not exist.** The finder shows no result count today. **Proposed resolution:** add a count (right-aligned in the prompt row, `22/22` style, `100+` at the cap), opt-in for the GitHub sources only, as part of Phase 2. Alternative: drop the count from the PM spec.
3. **`<C-s>` / `<C-v>` "do nothing"** needs a guard: today they close the picker first. Phase 3 adds an `item.file` check. (Noted, not changed: the list-pane `<C-v>` handler calls `open_split` instead of `open_vsplit`, a pre-existing bug outside this feature.)

---

# Architecture Changes

New:
- `lua/beast/libs/finder/source/gh/query.lua` - pure: `build(text, repo)` adds `repo:<slug>` unless text has `repo:`/`org:`/`user:`, adds `sort:created-desc` unless it has `sort:`; quote-aware token scan; `default_text(kind)`.
- `lua/beast/libs/finder/source/gh/api.lua` - `search(q, host, cb)` (spawns `gh api`, returns a handle with `kill()`), normalizes results to finder items, classifies errors; `detail(item, cb)` (`gh pr|issue view --json`), per-picker cache; repo/host detection and local pre-flight (`gh` installed, remote parsed, `gh auth token`).
- `lua/beast/libs/finder/source/gh.lua` - factory `create(kind)`: declares the source fields, `get`, `cancel` with a generation guard so stale responses are dropped.
- `lua/beast/libs/finder/source/gh_pr.lua`, `gh_issue.lua` - one-line instances.
- `lua/beast/libs/finder/source/gh/preview.lua` - renders the preview pane (header from the list item at once, description and conversation when `detail` returns).
- `tests/test-finder-gh-query.lua`, `tests/test-finder-gh-api.lua`, `tests/test-finder-stream-retain.lua`, `tests/test-finder-input-initial.lua`.

Modified:
- `lua/beast/libs/finder/source/init.lua` - extend `ASource` fields (`initial_query`, `retain_results`, `run_when_empty`, `debounce_ms`, `count`, `title`, `check`, `preview`) and the `Source` alias.
- `lua/beast/libs/finder/query.lua` - `Item` fields: `url`, `message`, `is_error`. (Built as: GitHub-specific fields live on `Beast.Finder.Gh.Item` in `source/gh/api.lua`; `count` is a source function `count(items) -> string`, not a flag.)
- `lua/beast/libs/finder/pipeline/stream.lua` - `retain_results` and `run_when_empty` behavior (opt-in; unchanged path otherwise).
- `lua/beast/libs/finder/ui/input.lua` - optional initial text (cursor at end) and `set_count`.
- `lua/beast/libs/finder/state.lua` - use `source.title()`, `source.debounce_ms`, `source.initial_query` (prefill, then run once immediately).
- `lua/beast/libs/finder/init.lua` - run `source.check()` before opening; abort with its toast.
- `lua/beast/libs/finder/render.lua` - preview dispatch to `source.preview` (also for an empty list). The count update lives in `pipeline/stream.lua`.
- `lua/beast/libs/finder/format.lua` - `gh_pr`/`gh_issue` row formatter (state icon, number, title, author, label badges, message rows).
- `lua/beast/libs/finder/highlights.lua` - state icon groups and label badge helper.
- `lua/beast/libs/finder/action.lua` - `open` for `item.url` (`vim.ui.open`), `copy_path` copies `url` when present.
- `lua/beast/libs/finder/keymaps.lua` - `<C-s>`/`<C-v>` do nothing (picker stays) when the item has no file; Enter/`<C-y>` ignore message rows.
- `lua/beast/init.lua` - two keys: `<leader>ghp` (`gh_pr`), `<leader>ghi` (`gh_issue`).
- `docs/CODEMAP/libraries.md` - finder section (via `/update-codemap` at the end).

## Implementation Phases

## Phase 1: Query and API core - pure, tested, no UI
1. **Query builder** (File: `lua/beast/libs/finder/source/gh/query.lua`)
   - Action: tokenizer that respects quotes; `build`, `default_text`; rules from the PM spec (repo scope, sort default, `org:`/`user:` count as scope).
   - Why: the one piece of product logic that must be exactly right and is fully unit-testable.
   - Depends on: None
   - Risk: Low
2. **API wrapper** (File: `lua/beast/libs/finder/source/gh/api.lua`)
   - Action: `search` via `vim.system({"gh","api","-X","GET","search/issues","-f","q=...","-f","per_page=100", "--hostname", host})`; normalize items (kind, state with merged/draft/closed, labels with color, url, author, dates); classify failures (422 not found, 403/429 rate limit with reset, auth, network, other); `kill()`.
   - Why: isolates every `gh` detail behind one module.
   - Depends on: Step 1
   - Risk: Medium (error classification from stderr/JSON)
3. **Tests** (Files: `tests/test-finder-gh-query.lua`, `tests/test-finder-gh-api.lua`)
   - Action: query cases (default text, existing `repo:`, quoted `label:"help wanted"`, `sort:` override, empty text); api cases with stubbed `vim.system` (PR open/draft/merged/closed, issue closed, 422, rate limit, kill, malformed JSON).
   - Depends on: Steps 1-2
   - Risk: Low

## Phase 2: Finder capabilities (opt-in, no GitHub yet)
1. **Source contract** (Files: `source/init.lua`, `query.lua`)
   - Action: document the new optional fields and item fields. No behavior.
   - Depends on: None
   - Risk: Low
2. **Stream pipeline** (File: `lua/beast/libs/finder/pipeline/stream.lua`)
   - Action: when `source.retain_results`: do not clear/render at run start; first arriving batch replaces old items; a run that ends with zero items clears and renders. When `source.run_when_empty`: run with an empty pattern. Also clear the input count at run start.
   - Why: PM STATE 4 (old list stays, no flicker) and "empty text still searches".
   - Depends on: Step 1
   - Risk: High - hot path shared with `live_grep`; every new branch is gated on a source flag.
3. **Prompt prefill and count** (Files: `ui/input.lua`, `state.lua`, `render.lua`)
   - Action: `create(..., initial_text)` writes the text after the prompt prefix, cursor at end; `State:new` applies `source.initial_query`, updates `filter`, and calls `pipeline.run` once without debounce; `source.title()` and `source.debounce_ms` override the defaults; `set_count` shows `n/n` (or `100+`) right-aligned, hidden while the spinner runs.
   - Depends on: Step 2
   - Risk: Medium (prompt buffer text and cursor handling)
4. **Pre-flight check** (File: `lua/beast/libs/finder/init.lua`)
   - Action: before opening, call `source.check()`; a false return aborts and the source has already shown its toast.
   - Depends on: Step 1
   - Risk: Low
5. **Tests** (Files: `tests/test-finder-stream-retain.lua`, `tests/test-finder-input-initial.lua`, existing `tests/test-finder-*.lua`)
   - Action: retain keeps old items until first new item; zero results clear; non-retain source behaves exactly as before; prefill puts text after the prefix and `get_text` returns it; existing finder tests still pass.
   - Depends on: Steps 2-4
   - Risk: Low

## Phase 3: GitHub sources, list, actions, keys (preview off)
1. **Factory and sources** (Files: `source/gh.lua`, `source/gh_pr.lua`, `source/gh_issue.lua`)
   - Action: `create(kind)` sets `live`, `async`, `retain_results`, `run_when_empty`, `count`, `debounce_ms = 400`, `initial_query` from `query.default_text`, `title()` ("Pull Requests - owner/name"), `check()` (gh installed, remote parsed, `gh auth token`; each failure is a Toast per PM scenario 8), `get(filter, cb)` (build query, call `api.search`, emit items, or one message row for empty/error; generation guard), `cancel()`.
   - Depends on: Phase 1, Phase 2
   - Risk: Medium (stale-response guard, rate limit at 30/min)
2. **Row format and highlights** (Files: `format.lua`, `highlights.lua`)
   - Action: `format.gh_pr`/`gh_issue`: state icon (open green, draft grey, merged purple, closed red, issue not-planned grey), `#number` dimmed, title, `@author`, label badges in label color; message rows dimmed.
   - Depends on: Step 1
   - Risk: Low
3. **Actions and keymaps** (Files: `action.lua`, `keymaps.lua`)
   - Action: Enter on a `url` item calls `vim.ui.open`; `<C-y>` copies the URL (Toast); `<C-s>`/`<C-v>` leave the picker open and do nothing for items without a file; message rows ignore Enter and `<C-y>`.
   - Depends on: Step 1
   - Risk: Medium (shared keymaps; verify file pickers unchanged)
4. **Keys** (File: `lua/beast/init.lua`)
   - Action: `<leader>ghp` opens `gh_pr`, `<leader>ghi` opens `gh_issue`, both with `preview = false` for now.
   - Depends on: Step 1
   - Risk: Low

## Phase 4: Preview
1. **Preview renderer** (Files: `source/gh/preview.lua`, `render.lua`, `source/gh.lua`)
   - Action: `source.preview(view, item)`: stage 1 writes title, state, repo, author, dates, labels from the list item immediately; stage 2 calls `api.detail` and fills branches/checks/mergeable/changes, description (markdown filetype), and conversation (oldest first); results cached per picker; a late response for a no-longer-selected item is dropped; PR-only fields omitted for issues. `render.schedule_preview` dispatches to `source.preview` when defined. Keys flip to `preview = true`.
   - Why: PM STATE 1 and 2.
   - Depends on: Phase 3
   - Risk: Medium (async fill vs fast cursor moves; markdown rendering in a float)

## Phase 5: Verification and docs
1. **Regression and perf** - run the full headless suite, `scripts/bench-grep.lua`, and `bench-ux.sh all` with `FIXTURE_LANG=lua FIXTURE_GIT=1` to prove `live_grep` did not regress.
2. **Codemap** - run `/update-codemap` so `docs/CODEMAP/libraries.md` lists the new sources and source fields.
   - Risk: Low

---

# Testing Strategy
- Headless tests: new `tests/test-finder-gh-query.lua`, `test-finder-gh-api.lua`, `test-finder-gh-source.lua`, `test-finder-gh-keys.lua`, `test-finder-gh-preview.lua`, `test-finder-stream-retain.lua`, `test-finder-input-initial.lua`; existing `tests/test-finder-*.lua`, `test-preflight.lua` must still pass. Run each as `nvim --clean --headless -l tests/<file>`.
- Bench: `scripts/bench-grep.lua` and `scripts/bench-ux.sh all` (stream pipeline touched). Compare against numbers before Phase 2.
- Type check: the `lua-language-server --check` command from DEVELOPMENT.md.
- Manual (use `NVIM_APPNAME=BeastVim`, in this repo which has a GitHub remote): PM scenarios 1 to 9 as written in the PM spec. Scenario 8A/8B: run from `/tmp` and with `PATH` lacking `gh`. Scenario 7: type quickly and confirm one search and no stale overwrite. Take screenshots and check the row, preview and prompt-row pixel layout against the PM mockups.

# Success Criteria
- [x] `<leader>ghp` and `<leader>ghi` open pickers whose prompt holds `is:pr state:open ` and `is:issue state:open ` with the cursor at the end, and results appear without typing.
- [x] The list shows the current repo's open PRs / issues, newest created first, with state icon, number, title, author, colored label badges.
- [x] Editing the text (state, author, label, words, other repo, `is:pr` to `is:issue`, `sort:`) matches what github.com shows for that text.
- [x] The preview shows metadata, description and conversation; header is instant; revisiting an item is instant.
- [x] Fast typing runs one search; a slower older response never replaces a newer one.
- [x] While a search runs the old list stays and a spinner replaces the count; zero results clear the list.
- [x] Empty results and real errors (repo not found, rate limit, network) show one in-list line, never a popup.
- [x] No remote / no `gh` / not logged in shows a toast and does not open a picker.
- [x] Enter opens the browser, `<C-y>` copies the URL, `<C-s>`/`<C-v>` leave the picker open, Esc closes with no side effects.
- [x] Technical: all headless tests pass, `live_grep` bench within noise of baseline, luals check clean, no `vim.notify` or lib-config keymaps in the new code.

---

## Completed

2026-11-15. All five phases: query/API core, opt-in finder live features, GitHub sources with list/actions/keys, preview pane, verification and docs.

- `8ed02c7` feat(finder): add github query builder and gh api wrapper
- `262f472` feat(finder): opt-in live source features (prefilled prompt, keep results while searching, count, custom title/preview/check) (also drops callbacks of cancelled runs in the stream pipeline, found in review)
- `bb0670f` feat(finder): github pull request and issue pickers (<leader>ghp, <leader>ghi) (also: title follows `repo:`, copy confirms via Toast, count blank after an error)
- `5d6027f` feat(finder): preview pane for github pull requests and issues
- `ed32889` fix(finder): message rows show no selection marker, cursorline or preview line number (found in the real-terminal check)

Verification: new headless tests pass (query 22, api 82, source 49, keys 27, preview 70, stream-retain 24, input-initial 14) and every existing `tests/test-finder-*.lua` and `test-preflight.lua` still pass; luals check clean; stylua clean. `bench-ux.sh all` (FIXTURE_LANG=lua FIXTURE_GIT=1) all PASS and equal to a baseline run of the starting commit within noise (keymaps p50 1.83 vs 1.84 ms, p99 35.9 vs 35.9 ms). `bench-grep.lua` only measures the bigram index, so it cannot see the pipeline change. Checked live in a real wezterm pane against GitHub: default open, query edit to `is:merged`, preview, issue picker, `repo:` not found error rows, Esc, no-remote toast.

Not exercised live (covered by stubbed tests only): opening the browser on Enter, copying to the clipboard, `gh` missing / not logged in toasts, rate-limit message, flipping `is:pr` to `is:issue` inside one picker.

Deviations from the plan: `count` is a source function, not a `show_count` flag; GitHub item fields live on `Beast.Finder.Gh.Item`; extra tests `test-finder-gh-source.lua`, `test-finder-gh-keys.lua`, `test-finder-gh-preview.lua`; `is_bot` dropped as unused; preview title line is not right-aligned like the PM mockup.
