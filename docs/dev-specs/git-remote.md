---
name: git-remote
description: New libs/git/remote.lua that reads a project's git remotes and answers Git.providers() / Git.has_provider(name) / Git.remote(provider); the startup GitHub keys and the finder's GitHub source delegate to it instead of parsing remotes themselves
generated: 2026-11-17
---

> PM Spec: none. Not a UI feature; the requirements below come straight from the request (shape suggested: `Git.providers()` / `Git.has_provider(name)`, defined in `libs/git/remote.lua`).

# Summary
Add `lua/beast/libs/git/remote.lua`, a small module that lists the remotes of a project, maps each remote host to a known provider (`github`, `gitlab`) and exposes `providers(root?)` and `has_provider(name, root?)`. `Git` becomes a global like `Key`/`View`. `lua/beast/init.lua` and the finder's GitHub source stop running their own `git remote get-url origin`, URL parser and host test; they ask the git lib instead, so no other lib defines remote logic. This is groundwork: the lazy registration of provider keys is refactored on top of it in a follow-up.

---

# Context

## Problem
"Is this project on GitHub?" is answered inline inside `sync_gh_keys` (`lua/beast/init.lua`): it spawns `git remote get-url origin`, calls `finder.source.gh.api.parse_remote`, and tests the host with `find("github", 1, true)`. The remote parser lives in the finder, the provider test lives in the startup file, and nothing can ask the question for GitLab or for a second remote. The git lib has no notion of remotes at all.

### Solution
`libs/git/remote.lua` owns URL parsing (moved out of the finder, not re-exported), host to provider classification, and a per-root cache of the remotes. `providers()` and `has_provider()` answer "which providers", `remote(provider)` returns the host and `owner/name` slug the finder needs; the first call for a root runs one `git config --get-regexp` synchronously. `lua/beast/init.lua` calls `Git.has_provider("github", root)` and keeps only the key set/del logic; `finder/source/gh/api.lua` calls `Git.remote("github", cwd)` and keeps only GitHub API logic.

---

# Research

### Repo Search
- Searched for: `parse_remote`, `remote get-url`, `"remote"`, `github` host checks, `Util.mod`, `packer.lazy` `cond`/`keys`, existing `tests/test-finder-gh-*.lua`
- Found:
  - `lua/beast/libs/finder/source/gh/api.lua:53` `M.parse_remote(url)`: https, `ssh://` and scp-like parsing into `{ host, slug }`. Covered by `tests/test-finder-gh-api.lua`.
  - `lua/beast/libs/finder/source/gh/api.lua:75` `M.repo(cwd)`: origin only, `vim.system(...):wait()`; tests mock `vim.system` keyed on `git -C /x remote get-url origin`, so this function must not change.
  - `lua/beast/init.lua:421-447` `sync_gh_keys`: the only caller that classifies a host (`find("github", 1, true)`), runs on `VimEnter`, `DirChanged`, `BufEnter`, async via `vim.system`.
  - `lua/beast/libs/git/repo.lua` already wraps async git calls per buffer; it has no remote concept.
- Also scanned: every `vim.system({ "git", ... })` outside `libs/git` (see "Audit of other git code" below).
- Reuse opportunity: Yes. Move `parse_remote` as-is into the git lib (and delete it from the finder); reuse the substring host rule; follow `repo.lua` for `vim.system` use.

### Built-in / Existing Lib Check
- Checked: `vim.system`, `git config --get-regexp`, `Util.root()`, `Util.mod`, `libs/git/init.lua` public surface
- Found: `git config --get-regexp '^remote\..*\.url$'` lists every remote URL in one process, with includes and worktrees handled by git itself. `libs/git/init.lua` requires config/diff/hunks/signs at top, so requiring the whole lib at startup costs more than requiring `git.remote` alone.
- Decision: **Reuse** (parser) + **Build** (`remote.lua`). No new dependency.

---

# Decisions

| # | Question | Recommendation | Alternative |
|---|---|---|---|
| D1 | Sync or async API | **Sync, cached per root.** Matches the requested return shape (`-> string[]`, `-> boolean`); one ~3 ms spawn per root per session | Async `refresh(root, cb)` + cache reads; more moving parts, `has_provider` would be wrong until the first callback |
| D2 | Which remotes count | **All remotes** (so a repo with `origin` on GitHub and `mirror` on GitLab reports both) | `origin` only; cannot produce the two-element example |
| D3 | Host to provider rule | **Substring of the host**: `github` in host is `github`, `gitlab` in host is `gitlab` (keeps GitHub Enterprise working, same rule as today) | Exact hosts only; breaks enterprise hosts |
| D4 | `_G.Git` global | **Yes (confirmed in review).** `_G.Git = Util.mod("beast.libs.git") ---@type Beast.Git` next to `Key`/`View` in `lua/beast/init.lua`. `Util.mod` only loads the file, not `setup()`, but `git/init.lua` requires config/diff/hunks/signs at top; if the startup bench regresses, make those requires lazy inside `git/init.lua` | No global, `require("beast.libs.git.remote")` at call sites |
| D5 | Cache invalidation | **Manual `invalidate(root?)` plus `FocusGained`** (a `git remote add` in a terminal shows up when focus returns) | Never invalidate; stale after remote changes |
| D6 | Finder keeps its own `parse_remote` | **No (confirmed in review).** Delete it; `gh/api.lua` uses `Git.remote("github", cwd)`. One parser, one place to fix bugs | Re-export from git lib |
| D7 | Hosts that do not contain `github`/`gitlab` (e.g. `git.acme.dev` GHE) | **Config map** `Git.setup({ remote = { hosts = { ["git.acme.dev"] = "github" } } })`, empty by default. Needed because the finder used to accept any host `gh` was logged into; routing it through the provider rule would otherwise drop those hosts | Accept the regression |

---

# Architecture Changes
- **New** `lua/beast/libs/git/remote.lua`: `parse(url)`, `provider_of(host)`, `list(root)`, `remote(provider, root?)`, `providers(root?)`, `has_provider(name, root?)`, `invalidate(root?)`.
- **Modified** `lua/beast/libs/git/init.lua`: public `M.remote`, `M.providers`, `M.has_provider` (each requires `git.remote` on call, no new top-level require).
- **Modified** `lua/beast/libs/git/config.lua`: `remote = { hosts = {} }` (host to provider overrides, D7).
- **Modified** `lua/beast/libs/finder/source/gh/api.lua`: `parse_remote` deleted; `M.repo(cwd)` returns `Git.remote("github", cwd)`. `M.check` keeps its `gh` checks.
- **Modified** `lua/beast/init.lua`: `_G.Git = Util.mod("beast.libs.git")`; `sync_gh_keys` calls `Git.has_provider("github", root)`; the `vim.system` + parse + `find("github")` block and its `vim.schedule` wrapper go away.
- **Modified** `tests/test-finder-gh-api.lua`: `parse_remote` cases move to the new test; `repo`/`check` mocks script `git -C /x config --get-regexp ...` instead of `remote get-url origin`.
- **New** `tests/test-git-remote.lua`.

## Audit of other git code
Scanned every git process or `.git` lookup outside `lua/beast/libs/git/`. Only the first two are remote logic and are in this spec; the rest are candidates for their own specs (this one stays under 5 core files).

| Where | What it does | Verdict |
|---|---|---|
| `lua/beast/init.lua:427` | `git remote get-url origin` + host test | **Move now** (Phase 2) |
| `libs/finder/source/gh/api.lua:53,76` | `parse_remote`, `repo()` spawn | **Move now** (Phase 2) |
| `libs/finder/source/git/log.lua:28` | `git log` / `git show` runner + parsers into finder row shapes | Follow-up spec `git-log`: runner and parsers belong in the git lib, the finder keeps row/preview mapping |
| `libs/statusline/components/git_commit.lua:24` | `git log -1 --format=%an (%cr) -- file` per buffer | Follow-up: `Git.last_commit(file, cb)`, statusline only renders |
| `libs/statusline/components/git_branch.lua` | own `.git` walk + HEAD file reader + fs watchers | Follow-up: `Git.branch(dir)` and a change event from the git lib (it already resolves `gitdir` in `repo.lua`) |
| `libs/explorer/git.lua:309,358,455` + `explorer/health.lua:371` | `git status --porcelain=v2` engine, own `.git` lookup | Follow-up: `Git.status(root, cb)`; largest move, explorer keeps propagation/badges |
| `util/root.lua:360` | `.git` marker in project-root detection | Leave: generic root heuristic, not git behavior |
| `libs/packer/ui.lua:1530` | `git ls-remote` on a plugin source | Leave: plugin manager reaching a third-party URL, unrelated to the project repo |

## Implementation Phases

## Phase 1: remote module — the API exists, `Git` is global, tested
1. **Move the parser** (File: `lua/beast/libs/git/remote.lua`)
   - Action: copy `parse_remote` body from `finder/source/gh/api.lua:50-71` as `M.parse(url)` returning `{ host, slug }` or nil. Define `---@class Beast.Git.Remote { name, url, host, slug, provider }`.
   - Why: the git lib is the natural owner of remote knowledge; the finder only consumes it.
   - Depends on: None
   - Risk: Low
2. **Classify and list** (File: `lua/beast/libs/git/remote.lua`)
   - Action: `provider_of(host)` returns `"github"` / `"gitlab"` / nil by lowercase substring. `list(root)` runs `git -C root config --get-regexp ^remote\..*\.url$`, one entry per line, parsed with `parse`; failures (not a repo, git missing) return `{}`.
   - Why: D2, D3.
   - Depends on: Step 1
   - Risk: Low
3. **Public API + cache** (File: `lua/beast/libs/git/remote.lua`, `lua/beast/libs/git/config.lua`)
   - Action: `providers(root?)` returns the sorted, de-duplicated provider names of `list(root)` (default root `Util.root()`); `has_provider(name, root?)` is membership in that list; `remote(provider, root?)` returns the first remote of that provider (`origin` preferred), shape `{ name, url, host, slug, provider }`. `provider_of` consults `config.remote.hosts` before the substring rule. Results cached in `cache[root]`; `invalidate(root?)` clears one root or all. A `FocusGained` autocmd (own augroup, created on first use) calls `invalidate()`.
   - Why: D1, D5; `has_provider("bitbucket")` is false because only known providers are ever listed.
   - Depends on: Step 2
   - Risk: Medium (autocmd created from a lazily required module; keep it created once)
4. **Public surface + global** (File: `lua/beast/libs/git/init.lua`, `lua/beast/init.lua`)
   - Action: add `M.remote`, `M.providers`, `M.has_provider` that `require("beast.libs.git.remote")` on call; add `_G.Git = Util.mod("beast.libs.git") ---@type Beast.Git` beside `Key`/`View`. Run the startup bench; if it regresses, make the lib's internal requires lazy.
   - Why: gives the requested `Git.providers()` shape (D4).
   - Depends on: Step 3
   - Risk: Low
5. **Tests** (File: `tests/test-git-remote.lua`)
   - Action: stub `vim.system`; cases: https/ssh/scp URLs parse (the `parse_remote` cases from `test-finder-gh-api.lua`); `remote("github")` prefers `origin` and returns host and slug; `config.remote.hosts` maps a custom host; GitHub Enterprise host is `github`; `origin`=github + `mirror`=gitlab gives `{ "github", "gitlab" }`; unknown host gives `{}`; `has_provider("bitbucket")` is false; non-repo (`code ~= 0`) gives `{}`; second call hits the cache (one spawn); `invalidate` forces a second spawn.
   - Why: logic is pure and cheap to pin down.
   - Depends on: Step 3
   - Risk: Low

## Phase 2: consumers — remove the inline logic
1. **Finder delegates** (File: `lua/beast/libs/finder/source/gh/api.lua`, `tests/test-finder-gh-api.lua`)
   - Action: delete `parse_remote`; `M.repo(cwd)` returns `Git.remote("github", cwd)` (host + slug, same `Beast.Finder.Gh.Repo` shape); update the test mocks and move the parse cases to `test-git-remote.lua`.
   - Why: the finder defines no remote code of its own (D6). `check()` messages stay identical.
   - Depends on: Phase 1
   - Risk: Low
2. **Startup keys** (File: `lua/beast/init.lua`)
   - Action: in `sync_gh_keys`, drop the `vim.system` / `parse_remote` / `find("github")` code and compute `on_github = remote.has_provider("github", root)` synchronously; keep the `gh_root` short-circuit, the `gh_keys_set` guard and the `Key.safe_set` / `Key.del` calls as they are.
   - Why: the question is answered by the git lib now; no async hop and no `vim.schedule` needed.
   - Depends on: Step 1
   - Risk: Medium (first `BufEnter` in a new root now blocks for one spawn; verify with the startup bench)

---

# Testing Strategy
- Headless tests: `nvim --clean --headless -l tests/test-git-remote.lua` (new); re-run (and update where they mock the origin command) every `tests/test-finder-gh-*.lua`.
- Bench: `./scripts/bench-startup.sh` before and after Phase 2 (hyperfine numbers are authoritative); `for f in scripts/bench-*.lua; do nvim --clean --headless -l "$f"; done`.
- Type check: `lua-language-server --check . --checklevel=Warning` (command in DEVELOPMENT.md).
- Manual: `NVIM_APPNAME=BeastVim nvim` inside a GitHub repo, `<leader>ghp` and `<leader>ghi` open the pickers; `:cd` to a non-GitHub directory, both keys disappear from the cheatsheet; `:cd` back, they return; in a repo with `git remote add mirror git@gitlab.com:o/n.git`, `:lua print(vim.inspect(require("beast.libs.git").providers()))` prints both providers.

# Success Criteria
- [x] `Git.providers()` returns `{ "github", "gitlab" }` for a repo with a GitHub and a GitLab remote, `{}` for a non-repo
- [x] `Git.has_provider("github")` / `("gitlab")` are true there, `("bitbucket")` is false
- [x] `lua/beast/init.lua` and `finder/source/gh/api.lua` no longer spawn git for remotes or parse URLs; `parse_remote` exists only in the git lib
- [x] `Git` is a global; `Git.remote("github")` returns `{ host, slug }`
- [x] A host mapped in `config.remote.hosts` is classified as its provider
- [x] `tests/test-git-remote.lua` and all `tests/test-finder-gh-*.lua` pass
- [x] Startup bench shows no regression; type check clean
- [x] GitHub Enterprise hosts (`github.acme.dev`) still count as `github`

## Completed

2026-11-17. Phase 1: `libs/git/remote.lua`, `Git.remote/providers/has_provider`, global `Git`. Phase 2: finder and startup keys read remotes from the git lib.

- `cab8772` feat(git): remote providers (Git.providers, Git.has_provider, Git.remote) and a global Git
- `96d33ab` refactor(git): finder and startup keys read remotes from the git lib (also wires `cfg.git` into `Git.setup` and seeds `config.remote.hosts` eagerly so D7 is reachable)
- `2837867` style(finder): stylua format keymaps (pre-existing format drift, unrelated)

Verification: `tests/test-git-remote.lua` 38 passed; all `tests/test-finder-*.lua` and `tests/test-git-*.lua` pass; lua-language-server clean; startup bench (nvim-internal mean) 36.9 ms at Phase 1, 38.0-38.3 ms after Phase 2 (about +1 ms: one synchronous `git config` at VimEnter, was async).
