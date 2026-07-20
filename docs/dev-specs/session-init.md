---
name: session-init
description: New `session` lib — auto-save on VimLeavePre keyed by cwd + git branch, manual load() and exists() API
generated: 2026-07-20
---

> PM Spec: [docs/pm-specs/session-init.md](../pm-specs/session-init.md)

# Summary

Add a new lib `lua/beast/libs/session/` that silently saves the current window/buffer layout on quit (via `:mksession!`), keyed by the working directory and — for non-`main`/`master` branches — the git branch. It exposes exactly two public calls: `load()` (source the session for the current dir+branch, falling back to the plain dir session) and `exists()` (same lookup, no side effect). No listing, no "last session," no auto-restore.

---

# Context

## Problem

BeastVim has no session-persistence lib. `lua/beast/option.lua:74` already sets `sessionoptions = { buffers, curdir, tabpages, winsize }`, so Neovim's own `:mksession` machinery is ready to use — nothing is missing there. What's missing is: (1) something to call `:mksession!` automatically on quit, (2) a per-directory + per-branch naming scheme so different projects/branches don't collide, and (3) a couple of small read APIs (`load`, `exists`) the user can invoke manually.

### Solution

A new lib, `session`, follows the exact structure every other BeastVim lib uses: `config.lua` (pure, readonly-metatable config store) + `init.lua` (state + `M.meta` + `M.setup` + the public API). It is wired into `beast/init.lua` with `packer.lazy` on `VimEnter` (deferred), the same trigger tier as `statusline`/`tabline`, so the `VimLeavePre` autocmd is registered moments after startup regardless of whether the user ever calls `load()`.

---

# Research

### Repo Search
- Searched for: `mksession`, `VimLeavePre`, `sessionoptions`, `show-current`, `git branch`, `fs_stat(".git")`
- Found:
  - `lua/beast/option.lua:74` already sets `sessionoptions` — nothing to add there.
  - `lua/beast/profile.lua` uses `VimLeavePre` for an unrelated purpose (dumping a profiler report) — no conflict, but confirms the autocmd name/pattern is free to reuse for a different augroup.
  - No existing git-branch lookup, no existing session/mksession wrapper anywhere in the repo.
- Reuse opportunity: No — nothing in the repo does per-directory/per-branch session naming or wraps `:mksession`.

### Built-in / Existing Lib Check
- Checked: `vim.uv`/`vim.loop` (`fs_stat`), `vim.fn.systemlist`, `vim.cmd("mksession!")`, `lua/beast/util/root.lua` (`Util.root()` / `Util.root.git()`), `lua/beast/libs/git/repo.lua` (`M.resolve`, async git plumbing).
- Found:
  - `Util.root()` / `Util.root.git()` exist and can find a git root, but they're **buffer-driven** (LSP workspace folders, language-marker patterns keyed off the current buffer's filetype) and can resolve to a different directory than `vim.fn.getcwd()` — e.g. in a monorepo, or before any buffer/filetype is set. Session identity must be the literal directory the user `cd`'d into and launched Neovim from, per the PM spec's workflow, so reusing `Util.root()` risks a mismatch between "what dir was saved under" and "what dir the user is in."
  - `git/repo.lua`'s `M.resolve` is async (`vim.system` + callback) and buffer-scoped (caches per-buffer git context for the gutter-signs/blame feature) — a different concern from "is `getcwd()` inside a git repo, and what branch." Reusing it would mean threading an async callback through what needs to be a synchronous, cwd-scoped lookup at `VimLeavePre` / `load()` / `exists()` time.
  - Nothing existing wraps `git branch --show-current` synchronously against an arbitrary directory.
- Decision: **Build** a small synchronous branch helper local to `session` (mirrors the same technique `persistence.nvim` itself uses: `vim.uv.fs_stat(".git")` guard + `vim.fn.systemlist("git branch --show-current")`), and **use** the built-in `sessionoptions` + `:mksession!` as-is. Do not reuse `Util.root()` or `git/repo.lua` — different scoping (buffer vs. cwd) and different sync/async needs.

---

# Architecture Changes

- New file: `lua/beast/libs/session/config.lua` — pure config store (one field: `dir`), same readonly-metatable pattern as `lua/beast/libs/scroll/config.lua` / `lua/beast/libs/breadcrumb/config.lua`.
- New file: `lua/beast/libs/session/init.lua` — `M.meta`, `M.setup(opts)`, private `identity()`/`plain_path()`/`branch_path()`/`branch_name()`/`has_real_buffer()`/`save()` helpers, public `M.load()` and `M.exists()`.
- Modified file: `lua/beast/init.lua` — add `---@field session? Beast.Session.Config` to the setup-opts annotation block, and a `packer.lazy("beast.libs.session", { event = { name = "VimEnter", defer = true }, setup = function(s) s.setup(cfg.session or {}) end })` block, placed alongside the other `VimEnter`-deferred libs (near `statusline`/`breadcrumb`/`tabline`).
- New file: `tests/test-session.lua` — headless test for path/identity computation, the buffer-count save guard, and the load-fallback rule.

## Implementation Phases

## Phase 1: `session` lib — save, load, exists

1. **Config store** (File: `lua/beast/libs/session/config.lua`)
   - Action: Define `defaults = { dir = vim.fn.stdpath("state") .. "/sessions/" }`; readonly metatable `__index`/`__newindex` exactly like `scroll/config.lua`; `methods.setup(opts)` does `vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})` — no side effects (no mkdir here, matching the "config.lua is pure" convention observed in every existing lib).
   - Why: One knob only (`dir`); no `need`/`branch` toggle since the PM spec fixes that behavior (buffer-count guard is always on, main/master always share the plain file) rather than asking for it to be configurable — avoids speculative flexibility per project convention.
   - Depends on: None
   - Risk: Low

2. **Identity + path helpers** (File: `lua/beast/libs/session/init.lua`)
   - Action: `local function encode(s) return (s:gsub("[\\/:]+", "%%")) end`; `local function plain_path() return Config.dir .. encode(vim.fn.getcwd()) .. ".vim" end`; `local function branch_name()` — returns `nil` unless `vim.uv.fs_stat(".git")` is truthy, `vim.v.shell_error == 0` after `vim.fn.systemlist("git branch --show-current")`, and the result is non-empty and not `"main"`/`"master"`; `local function branch_path()` returns `nil` if `branch_name()` is `nil`, else `Config.dir .. encode(cwd) .. "%%" .. encode(branch) .. ".vim"`.
   - Why: Mirrors the exact naming scheme already proven in `persistence.nvim` (which the user is replacing), so the fallback semantics ("no branch-specific file → use the plain one") fall out naturally: main/master never produce a branch file in the first place.
   - Depends on: Step 1
   - Risk: Low

3. **Save guard + autocmd** (File: `lua/beast/libs/session/init.lua`)
   - Action: `local function has_real_buffer()` iterates `vim.api.nvim_list_bufs()`, returns `true` if any buffer has `buftype == ""` and a non-empty name; `local function save()` returns early unless `has_real_buffer()`, else runs `vim.cmd("mksession! " .. vim.fn.fnameescape(branch_path() or plain_path()))`; `M.setup(opts)` calls `Config.setup(opts)`, `vim.fn.mkdir(Config.dir, "p")`, then registers `vim.api.nvim_create_autocmd("VimLeavePre", { group = vim.api.nvim_create_augroup("BeastSession", { clear = true }), callback = save })`.
   - Why: Implements the PM spec's "skip save when 0 real file buffers are open" rule directly; augroup name `BeastSession` matches the `Beast<LibName>` convention used by every other lib (`BeastBreadcrumb`, `BeastScroll`, `BeastTabline`, …).
   - Depends on: Step 2
   - Risk: Low — worst case of a bug here is a stale or missing session file, not a crash.

4. **Public `load()` / `exists()`** (File: `lua/beast/libs/session/init.lua`)
   - Action: `function M.load()` picks `branch_path()` if it's readable (`vim.fn.filereadable(...) == 1`), else `plain_path()`; if that file is readable, `vim.cmd("silent! source " .. vim.fn.fnameescape(file))`; otherwise no-op. `function M.exists()` returns `true` if either the branch path or the plain path is readable, else `false`. Add `M.meta = { name = "session", description = "Auto-saves and restores the editor session per project directory and git branch" }`.
   - Why: Directly implements the two APIs the PM spec asks for; both reuse the Step 2 path helpers so the fallback rule can't drift between `load` and `exists`.
   - Depends on: Step 2, Step 3
   - Risk: Low

5. **Wire into `beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action: Add `---@field session? Beast.Session.Config` next to the other `---@field` lines near the top of the setup-opts annotation block; add a `packer.lazy("beast.libs.session", { event = { name = "VimEnter", defer = true }, setup = function(s) s.setup(cfg.session or {}) end })` call in the same run of `VimEnter`-deferred registrations as `statusline`/`breadcrumb`/`tabline`.
   - Why: `VimEnter` (deferred) is the lightest trigger tier that still guarantees the `VimLeavePre` autocmd is registered without any user action — matching the PM spec's "auto-save happens with no explicit user step." A `keys`/`module`-only trigger (like `confirm`) would NOT satisfy this, since auto-save must work even in sessions where the user never calls `require("beast.libs.session")` at all.
   - Depends on: Step 4
   - Risk: Low

## Phase 2: Tests

6. **Headless test** (File: `tests/test-session.lua`)
   - Action: Following the `tests/test-tabline-edge-trim.lua` structure (`nvim --clean --headless -l`, local `assert_test` helper, exit code 0/1), cover: (a) `plain_path()` encodes `cwd` with `%%`-substituted separators and a `.vim` suffix; (b) `branch_name()` returns `nil` outside a git repo (`vim.uv.fs_stat` stubbed/false) and returns `nil` for `main`/`master`; (c) `save()` (invoked via `vim.cmd("doautocmd VimLeavePre")` inside a temp cwd after `M.setup`) does not create a session file when no real file buffer is open, and does create one once a real file buffer exists; (d) `M.load()` prefers the branch file when present, falls back to the plain file when the branch file is absent, and no-ops when neither exists; (e) `M.exists()` agrees with `M.load()`'s fallback outcome in each case.
   - Why: These are exactly the PM spec's Scenarios 1–4 and the "check existence" success criterion, expressed as assertions instead of manual steps.
   - Depends on: Step 4
   - Risk: Low

---

# Testing Strategy

- Headless tests: `nvim --clean --headless -l tests/test-session.lua` (new, Step 6) — run standalone; add to the `for f in scripts/bench-*.lua` / test-loop mentioned in `DEVELOPMENT.md` if/when such a test-runner loop is formalized (today tests are run individually per `tests/test-*.lua` file, matching existing convention).
- Bench: None — `session` only runs on `VimEnter` (once) and `VimLeavePre` (once); it is not a per-keystroke or per-frame hot path, so it's not a candidate for `scripts/bench-*.lua`.
- Manual: Walk PM spec Scenarios 1–4 by hand in a scratch git repo:
  1. `cd` into a scratch repo on `main`, open files, quit, reopen, `:lua require("beast.libs.session").load()` → layout restored.
  2. Checkout a feature branch, open different files, quit; switch back to `main`, confirm the `main` session is untouched; return to the feature branch, `load()` → feature-branch layout restored, not `main`'s.
  3. Create a brand-new branch with no session yet, `load()` → falls back to the plain project session.
  4. Open Neovim with no real file buffer (dashboard only), quit immediately → confirm the previously saved session file's mtime is unchanged (not overwritten).

---

# Success Criteria

- [ ] Quitting Neovim after editing at least one real file silently saves the layout for the current dir (+ branch, unless main/master).
- [ ] Quitting with no real file buffers open never overwrites a previously saved session.
- [ ] `:lua require("beast.libs.session").load()` restores the exact layout last saved for the current dir + branch.
- [x] On a branch with no session of its own, `load()` falls back to the plain project-level session instead of doing nothing.
- [x] `load()` is a no-op with no error when nothing has ever been saved for the current dir (in either branch-specific or plain form).
- [x] `exists()` reports session presence for the current dir + branch, honoring the same fallback rule, without triggering a load.
- [x] main/master branches never produce a separate suffixed session file — they always share the plain project-level session.
- [x] `tests/test-session.lua` passes headless (`nvim --clean --headless -l tests/test-session.lua`).

## Completed

2026-07-21 — Phase 1 (lib + wiring) and Phase 2 (headless test, 15 assertions)
both landed and verified. Note: `lua/beast/libs/session/init.lua` has since
seen further local edits beyond this spec's scope (fold-state restore on
load) — not covered by this dev spec.
