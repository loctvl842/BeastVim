---
name: finder-pr-commits
description: Pull requests lead to their commits (diff preview) and from a commit to a grep in its files; the chain edges and the keys that move between steps become configurable
generated: 2026-11-15
---

> PM Spec: [docs/pm-specs/finder-pr-commits.md](../pm-specs/finder-pr-commits.md)

# Summary
Add the `gh_pr -> gh_commits -> live_grep` chain on top of the existing chain machinery (`chains.lua`, `chain.lua`, Session levels), and make the chain configurable: every built-in edge can be switched off or given another key, and the keys that go back can be changed. The set of edges stays closed (only built-in pairs exist); configuration chooses among them and an invalid configuration raises at setup. A commit's files need a network call, so an edge can now finish asynchronously.

---

# Context

## Problem
`chains.lua` has one fixed key (`<C-g>`) per source and `keymaps.lua` binds it at module load, so a PR list cannot have two ways down (files changed, commits), nothing can be remapped or disabled, and `open(ctx)` is synchronous while the files of a commit are only known after a GitHub request. There is no commits source, no per-commit diff fetch, and the hint line assumes one edge per level.

### Solution
Edges get an id (`"gh_pr|gh_commits"`) and a default key; `config.chains` can disable an edge (`false`) or change its key, and changes the back keys. `chain.lua` looks edges up by `(source, key)` among the *enabled* ones, `keymaps.lua` binds the keys of the enabled edges at mount, and the hint lists every enabled edge of the level shown. A new `gh_commits` match source lists a PR's commits and previews the highlighted commit's diff; an edge may return a waiting function so `<C-g>` on a commit can fetch its files first.

---

# Research

### Repo Search
- Searched for: `chain.KEY`, `chains` group in `keymaps.lua`, `config.setup`, `cfg.finder` in `lua/beast/init.lua`, `source.preview` for gh, `api.files`/`classify` in `source/gh/api.lua`, `host.busy`, `ui.input.start_spinner`, `open_diff` in `action.lua`.
- Found: the single `chain.KEY` bound in a static `chains` group at module load; user config reaches the finder through `packer.lazy("beast.libs.finder", { setup = finder.setup(cfg.finder) })`; `api.files` pages `pulls/{n}/files` with a truncation probe and a `kill` handle; `gh/preview.lua` has a per-view cache and stale-fetch guard to copy for the commit diff; `host.busy` + the prompt spinner already show "working"; `tests/helpers/gh.lua` scripts `gh` for tests.
- Reuse opportunity: Yes - the paging helper pattern of `api.files`, the preview state/cache pattern, `action.open_diff` (extend for a commit), `classify` for errors, the test helper.

### Built-in / Existing Lib Check
- Checked: `vim.tbl_deep_extend`, `vim.validate`, GitHub REST `GET repos/{o}/{r}/pulls/{n}/commits` (max 250, `sha`, `commit.message`, `commit.author.{name,date}`, `author.login`) and `GET repos/{o}/{r}/commits/{sha}` (`files[]` with `filename`, `status`, `patch`, up to 300 files, `commit.message`).
- Found: both endpoints answer with `gh api` like the existing calls; `patch` is absent for binary or huge diffs.
- Decision: **Reuse** the chain machinery, gh api helpers and preview patterns; **Build** `gh_commits`, the commit detail fetch, chain config + validation, and async edge support. No new dependency.

### Corrections / notes on the PM spec
1. The PM spec says `<BS>` goes back on an empty prompt. With configurable back keys, `<BS>` keeps that meaning (it is a normal backspace otherwise); any other key listed in `back` goes back whenever pressed.
2. "Configurable" is read as: choose among built-in edges and keys. Defining a new pair, or a key that clashes with a picker key, raises at setup (earlier decision: the edge set is closed).

---

# Architecture Changes
- `lua/beast/libs/finder/config.lua` - modified: `chains = { back = { "<BS>", "<C-o>" }, edges = {} }` defaults.
- `lua/beast/libs/finder/chains.lua` - modified: each edge gets `id` (`from .. "|" .. to`) and a default `key`; new rows `gh_pr|gh_commits` (key `<C-t>`) and `gh_commits|live_grep`; `open` may return a *waiting function* (see Design).
- `lua/beast/libs/finder/chain.lua` - modified: `enabled()` (edges after config), `from(source)` (all enabled edges of a source), `find(source, key)`, `keys()`; `validate(chains_cfg)` raises on unknown ids, non-string keys, a key clash (two enabled edges of one source, or a picker key); `drill(session, key)`; waiting-edge handling; `hint_text` lists every enabled edge and the first back key.
- `lua/beast/libs/finder/init.lua` - modified: `setup` validates `config.chains` (raises); `finder.chains()` returns the enabled edges with their keys.
- `lua/beast/libs/finder/keymaps.lua` - modified: the static `chains` group is built at mount from `chain.keys()` (one `drill` binding per distinct key, in all three panes) and the configured back keys (`<BS>` keeps the empty-prompt `expr` mapping, other keys call `back`); exports `reserved()` (the picker's own keys) for validation.
- `lua/beast/libs/finder/source/gh/api.lua` - modified: `commits(item, cb)` (pages of `pulls/{n}/commits`, 3 pages + truncation probe) and `commit(item, sha, cb)` (one commit with its files), normalizers.
- `lua/beast/libs/finder/source/gh_commits.lua` - **new**: match source over `filter.ctx.pr`; rows `sha  subject  author  age`; `title`, `count`, `preview` (message, file list, diffs; cached per sha), `open` (full commit in a scratch buffer).
- `lua/beast/libs/finder/source/gh/preview.lua` or sibling `source/gh/commit_preview.lua` - **new/modified**: pure `build(commit)` + window drawing with cache and stale guard.
- `lua/beast/libs/finder/action.lua` - modified: `open_commit(win, item, commit)`.
- `lua/beast/libs/finder/format.lua` - modified: `gh_commit` row formatter.
- `lua/beast/libs/finder/source/init.lua` - modified: `"gh_commits"` in the source alias.
- `lua/beast/libs/finder/ui/hint.lua` - unchanged; text comes from `chain.hint_text`.
- `tests/test-finder-chain-config.lua`, `test-finder-gh-commits-api.lua`, `test-finder-gh-commits.lua`, `test-finder-chain-commit-grep.lua` - **new**; `test-finder-chain.lua` - modified (seven edges, config-aware pair test); `tests/helpers/gh.lua` - modified (commit fixtures).
- `docs/CODEMAP/libraries.md`, `INDEX.md`, `lua/beast/libs/finder/docs/` - updated at the end.

## Design (shared by all phases)

```lua
-- config (user side, through cfg.finder in lua/beast/init.lua)
chains = {
  back  = { "<BS>", "<C-o>" },                 -- keys that go back; "<BS>" only on an empty prompt
  edges = {                                    -- by edge id; absent = built-in default
    ["gh_pr|gh_commits"]   = { key = "<C-t>" },
    ["gh_pr|gh_pr_files"]  = false,            -- switched off: no key, not in the hint
    ["files|live_grep"]    = { key = "<M-g>" },
  },
}

-- chains.lua (built-in, closed)
{ id = "gh_pr|gh_commits", from = "gh_pr", to = "gh_commits", key = "<C-t>", crumb = "Pull Requests",
  hint = commits_in_pr, open = pr_commits }

-- an edge whose next level needs a request returns a waiting function instead of options
open = function(ctx) return function(resume)        -- resume(opts | message | nil)
  return api.commit(ctx.selected, ctx.selected.sha, function(res) resume(res.error and res.error.message or scope(res.commit)) end)
end end
```

Validation (`chain.validate`, run by `finder.setup`, raises with the offending id/key named): every key of `edges` is a known id (`finder: unknown chain 'a>b' (known: ...)`); the value is `false` or a table whose `key` is a non-empty string; no two enabled edges of one source share a key; no enabled edge key or back key equals a picker key (`keymaps.reserved()`); `back` is a non-empty list of strings. A waiting edge: `<C-g>` starts the prompt spinner and calls the function; the answer is applied only if the session is open and still on the same level and the user did not press `<BS>`; another drill key while waiting shows "Still loading - try again in a moment".

## Implementation Phases

## Phase 1: Configurable chain (no new chain yet)
1. **Config and ids** (Files: `config.lua`, `chains.lua`)
   - Action: defaults for `chains`; every edge gets `id` and `key` (`<C-g>` for all existing edges). Depends on: None. Risk: Low
2. **Lookup by enabled edges** (File: `chain.lua`)
   - Action: `enabled()`, `from(source)`, `find(source, key)`, `keys()`, `validate()`, `drill(session, key)`; `hint_text` lists all enabled edges of the level; back hint uses `config.chains.back[1]`. `chain.edge(from, to)` still raises for pairs not in `chains.lua` (disabled edges still *exist*). Depends on: Step 1. Risk: Medium
3. **Keys from config** (File: `keymaps.lua`, `init.lua`)
   - Action: bind at mount: one `drill` binding per distinct enabled key in all three panes (the action knows its key), the back keys in the input; `reserved()` exported; `setup` calls `chain.validate`. Defaults reproduce today's keys exactly. Depends on: Step 2. Risk: Medium (insert-mode `<C-o>` stays as today)
4. **Tests** (Files: `test-finder-chain-config.lua` new, `test-finder-chain.lua`)
   - Action: defaults unchanged; disabled edge: no hint, key toasts "Nothing to open from here"; remapped key works and the old one does not; custom back key; invalid configs raise (unknown id, clash with `<C-j>`, two edges one key, non-string key, empty back); `finder.chains()` shows keys. Risk: Low

## Phase 2: Commits of a pull request
1. **API** (File: `source/gh/api.lua`)
   - Action: `M.commits(item, cb)` pages `pulls/{n}/commits` (3 pages of 100, probe for a 4th like `files`), returns `{ sha, short, subject, message, author, date }` and `truncated`; `M.commit(item, sha, cb)` returns `{ message, files = { path, status, additions, deletions, patch? }, truncated? }` (the endpoint lists up to 300 files); errors through `classify`; both return a `kill` handle. Risk: Medium
2. **Source** (Files: `source/gh_commits.lua` new, `format.lua`, `source/init.lua`)
   - Action: match-pipeline async source over `filter.ctx.pr` (same shape as `gh_pr_files`): item `text = sha subject author`, fields for the row (`sha`, `subject`, `author`, `date`), message rows for errors; `title(filter, items)` = `PR <title...> › Commits (N)` (`, partial` when cut); `count = format.ratio`; `format.gh_commit` row = short sha (dim), subject, author and age right-aligned.
   - Risk: Medium
3. **Commit preview and open** (Files: `source/gh/commit_preview.lua` new, `action.lua`)
   - Action: `preview(view, item)` draws message + per-file `status +a -d` + each diff (`filetype=diff`) once `api.commit` answers; per-view cache by sha, stale-fetch guard, "(diff too large or binary)" per file without a patch, loading line meanwhile. `source.open` = `action.open_commit`: uses the cached commit (or fetches, with the picker already closed and a toast on error) and opens message + diffs in a read-only scratch buffer named `owner/name@<short sha>`.
   - Risk: Medium
4. **Edge** (File: `chains.lua`)
   - Action: `gh_pr|gh_commits`, key `<C-t>`, crumb "Pull Requests", hint `commits in #N` (real PR row only), `open` returns `{ ctx = { pr = selected }, title = ... }`.
   - Risk: Low
5. **Tests** (Files: `test-finder-gh-commits-api.lua`, `test-finder-gh-commits.lua` new)
   - Action: paging/truncation/errors; the picker through the real keys with scripted `gh`: both hints on a PR, `<C-t>` lists commits oldest first, filter by subject/author/sha with `n/total`, diff preview and its cache (one fetch per sha), Enter opens the commit buffer, `<BS>` back with no new request, message row refuses. Risk: Low

## Phase 3: Commit to grep (async edge)
1. **Waiting edges** (File: `chain.lua`)
   - Action: when `open(ctx)` returns a function, start the prompt spinner, call it with `resume`; apply the answer only if the session is open, still on the same level and no pop happened (token); a second drill while waiting toasts "Still loading - try again in a moment"; the spinner stops either way. Risk: Medium
2. **Edge** (File: `chains.lua`)
   - Action: `gh_commits|live_grep`, key `<C-g>`: `ctx.selected` commit, waits for `api.commit` (instant when the preview cached it), scope = changed files not `removed` that exist under the project root; title `N Files in <short sha> › Live Grep`; none exist -> "None of these files exist in your working tree"; merge commit with no files -> nil ("Nothing to open from here"); placeholder via `ctx.local_copies = true`; hint `grep the files changed in <short sha>`.
   - Risk: Medium
3. **Tests** (File: `test-finder-chain-commit-grep.lua` new)
   - Action: three-level chain with real temp files; removed/missing dropped, none-exist, merge commit, error from the commit request, `<BS>` while waiting drops the answer, double `<C-g>`, closing the picker while waiting; remap `<C-g>` of this edge through config. Risk: Low

## Phase 4: Docs and wrap-up
1. `docs/CODEMAP/libraries.md` + `INDEX.md` (config, edge ids, waiting edges, `gh_commits`); a short "Configuring chains" note with the config example in `lua/beast/libs/finder/docs/`; update the pair test to the seven built-in edges; final verification below. Risk: Low

---

# Testing Strategy
- Headless: new tests above plus `for f in tests/test-finder-*.lua tests/test-preflight*.lua; do nvim --clean --headless -l "$f"; done` with `NVIM_APPNAME=BeastVim`; `stylua --check lua tests`; luals as in DEVELOPMENT.md.
- Bench: `scripts/bench-finder-matcher.lua` (the match engine gains a title refresh only) and `bench-ux.sh all` (keymaps scenario opens the pickers) against the starting commit.
- Manual (real nvim in tmux, `NVIM_APPNAME=BeastVim`; a public repo with a multi-commit PR): PM spec scenarios 1-7; plus the default keys, a remapped key, a disabled edge, an invalid config message at startup. Not testable offline: live GitHub paging beyond the scripted fixtures.

# Success Criteria
- [ ] Every PM spec success criterion (PR -> commits with diff, filter, grep in the commit's local files, back at each step, Enter opens the diff, refusals, `(partial)` caps, hint keys).
- [ ] With no configuration, every existing chain key behaves exactly as before; `<C-t>` is the new commits key.
- [ ] `chains.edges[id] = false` removes the edge (key, hint, behavior); `{ key = ... }` rebinds it; `chains.back` changes the back keys.
- [ ] An unknown edge id, a key clash, or a malformed value raises at setup with a message naming it; no way to define a new pair.
- [ ] A slow commit request never opens a level after the user went back or closed the picker.
- [ ] Technical gates: all finder tests pass, luals and stylua clean, matcher bench and `bench-ux.sh all` within noise, Toast (no `vim.notify`).
