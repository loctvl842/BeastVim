---
name: key-cond
description: Add a `cond` field to Beast.KeymapBase; boolean and quick functions gate registration, slow functions (done callback) register a toast-only placeholder that is swapped for the real keymap or removed when the check ends
generated: 2026-11-17
---

> PM Spec: [docs/pm-specs/key-cond.md](../pm-specs/key-cond.md)

# Summary

`Key.safe_set` learns an optional `cond`. A boolean or a function that returns true/false decides registration immediately. A function that returns nothing and calls `done(ok)` later is a slow check: the key is registered at once as a placeholder (toast only), then swapped for the real keymap on yes, or removed on no/error/timeout. The slow-check bookkeeping lives in a new `key/cond.lua`; `core.lua` only calls into it. The packer lazy-key trigger forwards `cond` so `packer.lazy` `keys` can use it.

---

# Context

## Problem
`Beast.KeymapBase` has no way to say "register only if X". Callers hand-roll an `if` (e.g. `sync_gh_keys` in `lua/beast/init.lua`, which spawns `git remote get-url origin` and then sets/deletes keys). When X needs an external command, the only simple options are to block on `vim.system():wait()` or to register the key unconditionally and leave a dead key in the hint and cheatsheet.

### Solution
`core.safe_set` evaluates `cond` once per call before `set`. Quick answers are applied inline. Slow answers go through `key/cond.lua`, which owns the pending table (one entry per keymap id and buffer), the 10 second timer, and the swap/remove. `core.set` and `core.del` get small hooks so a pending entry is cancelled when the same keys are deleted or re-registered, and so the swap does not look like a duplicate registration to the conflict tracker.

---

# Research

### Repo Search
- Searched for: `KeymapBase`, `cond`, `safe_set`, `M.managed`, `vim.system`, `BeastKeysChanged`, `record_call`, `Toast`, `nvim_buf_is_valid` under `lua/beast/libs/key` and callers.
- Found:
  - `lua/beast/libs/key/core.lua:1-14` `Beast.KeymapBase` (no `cond`); `core.lua:280` `skip` table decides which spec fields are NOT forwarded to `vim.keymap.set` (`has`, `group`, `once` already there). `core.lua:375` `safe_set` loops modes and calls `set`/`del`/label.
  - `core.lua:314` `M.set` installs the map, stores `M.managed[id]`, calls `record_call` (conflict history keyed by `resolve_call_site`, which walks the stack and dedupes by `(source, line)`), and emits `BeastKeysChanged`. `core.lua:299` `M.del` removes map, `managed`, conflict record, emits DEL.
  - `lua/beast/libs/key/hint/index.lua` rebuilds from `M.managed` on `BeastKeysChanged`, so placeholder entries and their removal appear in the hint with no hint change. Cheatsheet reads the same registry.
  - `lua/beast/libs/lsp/attach.lua:30,169` `Beast.Lsp.KeySpec` extends `Beast.KeymapSpec` and re-declares `cond?: string` (an LSP method). It reads `spec.cond` itself and never forwards it to `safe_set`, so there is no runtime clash, but a type clash once `KeymapBase` gains `cond`.
  - `lua/beast/libs/packer/triggers/keys.lua:26-39` builds `map_opts` from a fixed list (`nowait`, `silent`, `expr`, `remap`, `noremap`), so `cond` on a `packer.lazy` key would be silently dropped.
  - `lua/beast/libs/packer/init.lua:239`, `import.lua:88`, `triggers/event.lua:13` already use a `cond` function on plugin specs (`cond == nil or cond()`): same name, same "false means skip" meaning.
  - `lua/beast/libs/toast/init.lua:52` `Toast(msg, level, opts)` is the notice channel per the lib conventions; repeated toasts already stack as `x2` (`toast-repeat-count`).
  - `lua/beast/init.lua:428` `sync_gh_keys` is the motivating caller (async `vim.system`, key set/del on `VimEnter`/`DirChanged`/`BufEnter`). Replaced in Phase 4.
  - Tests: `tests/test-key-hint.lua` is a manual `:luafile` script; headless tests stub `vim.system` (see `tests/test-git-remote.lua`) and run with `nvim --clean --headless -l`.
- Reuse opportunity: Yes. Reuse `M.set`/`M.del` for placeholder install/remove, `M.managed` + `BeastKeysChanged` for hint/cheatsheet, `Toast` for messages, `vim.uv.new_timer`/`vim.defer_fn` for the timeout.

### Built-in / Existing Lib Check
- Checked: `vim.system` callback context (fast event, API calls need `vim.schedule`), `vim.defer_fn`, `vim.api.nvim_buf_is_valid`, `libs/async.lua` (coroutine scheduler for CPU-budgeted work).
- Found: `libs/async.lua` solves time-sliced CPU work, not waiting on a process, so it adds nothing here. A plain callback (`done`) is the lightest contract and matches how `vim.system` reports back.
- Decision: **Build** `key/cond.lua` on top of existing `core.set`/`core.del`; **Use** `vim.defer_fn`, `Toast`.

---

# Architecture Changes

- `lua/beast/libs/key/core.lua` (modified): add `cond` to `Beast.KeymapBase`, add `cond` to the `skip` table, evaluate `cond` in `safe_set`, let `set` accept an optional pre-resolved call site, make `del` cancel a pending check.
- `lua/beast/libs/key/cond.lua` (new): `resolve(spec, buffer, on_yes)` classify and run a condition; pending table, placeholder install, swap, removal, timeout, toasts.
- `lua/beast/libs/packer/triggers/keys.lua` (modified): forward `cond` to the temporary lazy-load key only (the real keymap installed after plugin load is not re-gated).
- `lua/beast/libs/lsp/attach.lua` (modified, type only): rename the LSP-method field to `method` to avoid the type clash (see Decisions).
- `lua/beast/init.lua` (modified): replace `sync_gh_keys` and its autocmd with two `cond` keys in the existing `beast.libs.finder` `packer.lazy` `keys` (Phase 4).
- `tests/test-key-cond.lua` (new): headless tests.
- `docs/CODEMAP/libraries.md` (modified): list `cond.lua` under `key/`.

## Implementation Phases

## Phase 1: Quick conditions — boolean and returning function
Mergeable alone. Minimum slice: boolean and quick function. Until Phase 2 lands, a function that returns nothing is treated as a no.

1. **Type and opts filter** (File: `lua/beast/libs/key/core.lua`)
   - Action: add `---@field cond? boolean|fun(done: fun(ok: boolean)): boolean?` to `Beast.KeymapBase`; add `cond = true` to `skip`.
   - Why: `cond` must never reach `vim.keymap.set`; the type documents all three forms.
   - Depends on: None
   - Risk: Low
2. **Evaluate in `safe_set`** (File: `lua/beast/libs/key/core.lua`)
   - Action: before the mode loop, if `opts.cond ~= nil` hand the spec to `Cond.resolve` once per call; `false` or a quick false returns (no set, no label); `true` or a quick true continues to the existing set/label branches. Deletion (`rhs == false/vim.NIL`) ignores `cond`.
   - Why: single choke point; once per call so a `"nv"` string runs a slow check once, not once per mode.
   - Depends on: Step 1
   - Risk: Medium (must not change the no-`cond` path; guard with `opts.cond == nil` early exit)
3. **`cond.lua` quick path** (File: `lua/beast/libs/key/cond.lua`)
   - Action: `resolve` returns `"yes"`, `"no"` or `"pending"`. Boolean maps directly. A function runs under `pcall`; a boolean return is quick; a thrown error is a no with a one-time toast naming the keymap (`desc` or lhs).
   - Why: isolates condition semantics from registration code.
   - Depends on: Step 2
   - Risk: Low
4. **Tests** (File: `tests/test-key-cond.lua`)
   - Action: cover `cond = true/false/nil`, quick true/false, error in cond, multi-mode spec, `rhs = false` ignoring cond, no `cond` key leaking into `nvim_get_keymap` options.
   - Depends on: Step 3
   - Risk: Low

## Phase 2: Slow conditions — placeholder, done, timeout
1. **Pending table** (File: `lua/beast/libs/key/cond.lua`)
   - Action: `pending[id .. "\0" .. bufkey] = token` where `bufkey` is the resolved buffer number or `"g"` for global. `buffer == true/0` resolves to the current buffer at registration. A new registration for the same key replaces the token; the old token is marked stale.
   - Why: makes "late answer discarded" a single identity check.
   - Depends on: Phase 1
   - Risk: Medium
2. **Slow classification and placeholder** (File: `lua/beast/libs/key/cond.lua`, `core.lua`)
   - Action: a function that returns nil and has not called `done` synchronously is slow. Install the placeholder with `core.set` using the spec with `rhs` replaced by a function that calls `Toast("<desc>: still checking", "INFO")`, `expr`/`once` stripped, `desc` kept. A `done` called synchronously inside the function counts as quick. A label-only spec (no rhs) installs no placeholder and waits.
   - Why: PM spec states pressing a pending key only toasts and is never queued.
   - Depends on: Step 1
   - Risk: Medium
3. **Hook `core.set` for the swap** (File: `lua/beast/libs/key/core.lua`)
   - Action: `M.set(spec, buffer, site)` takes an optional call site and passes it to `record_call(id, km, site)`; the placeholder install captures `resolve_call_site` at registration, the swap passes the same site. `record_call` uses `site or resolve_call_site(...)`.
   - Why: the swap runs from a `vim.system` callback where `resolve_call_site` finds no user frame (`source = "?"`) and would be recorded as a duplicate registration of the same keys.
   - Depends on: Step 2
   - Risk: Medium
4. **`done(ok)`** (File: `lua/beast/libs/key/cond.lua`)
   - Action: `done` is idempotent (first call wins), `vim.schedule`s its body (callers are usually fast-event callbacks), then: stale token or invalid buffer (`nvim_buf_is_valid`) returns silently; `ok == true` clears the token and swaps via `core.set(real_spec, buffer, site)`; anything else clears the token and removes via `core.del`, with no toast for a plain `false`.
   - Why: PM rules "late answer thrown away", "plain no is silent", "only a clear yes counts".
   - Depends on: Steps 1-3
   - Risk: Medium
5. **Timeout and errors** (File: `lua/beast/libs/key/cond.lua`)
   - Action: `vim.defer_fn(..., M.timeout_ms)` (default 10000) calls the same path with a reason; error or timeout removes the placeholder and shows one `Toast(..., "WARN", { title = "key" })` such as `<leader>gp disabled: check timed out (10s)`. The timer is stopped when `done` wins.
   - Why: PM rules for fail/hang.
   - Depends on: Step 4
   - Risk: Low
6. **Cancel on delete** (File: `lua/beast/libs/key/core.lua`)
   - Action: `M.del` and `M.set` call `Cond.cancel(id, buffer)`, which drops the pending entry; the later `done` or timer finds nothing live and does nothing (the timer is not stopped early).
   - Why: PM scenario 8, a late yes must not bring a deleted key back.
   - Depends on: Step 1
   - Risk: Low
7. **Tests** (File: `tests/test-key-cond.lua`)
   - Action: placeholder exists in `Key.managed` and `nvim_get_keymap` right after registration; pressing it (call the mapped function) toasts and does not run the real rhs; yes swaps to the real rhs and does not add a conflict record; no removes silently; error and timeout toast once (set `Cond.timeout_ms = 50`); stale token (re-register, then answer the old `done`); closed buffer; delete while pending; label-only entry; `done` called twice.
   - Depends on: Steps 1-6
   - Risk: Low

## Phase 3: Callers
1. **Packer lazy keys** (File: `lua/beast/libs/packer/triggers/keys.lua`)
   - Action: add `cond = key_spec.cond` to the `map_opts` used for the temporary `Key.safe_set` only; build a second `real_opts` without `cond` for the re-set after plugin load.
   - Why: otherwise `packer.lazy` `keys = { { "<leader>gp", ..., cond = ... } }` silently ignores the field; re-gating the real key would run the check twice.
   - Depends on: Phase 2
   - Risk: Medium (a pending placeholder temporarily replaces the lazy-load trigger; pressing it toasts instead of loading the plugin, matching the PM rule)
2. **LSP field rename** (File: `lua/beast/libs/lsp/attach.lua`)
   - Action: `Beast.Lsp.KeySpec` field `cond` becomes `method`; line 169 reads `spec.method`. Update every `keys = {...}` entry that sets it: none in this repo, but the language plugins in `~/Documents/Beast/Developments/neovim_plugins` (python, typescript, lua_ls, cpp, json) use it 17 times; renamed there too (outside this repo, decided 2026-11-17).
   - Why: remove the type clash; `cond` now means one thing everywhere in key specs.
   - Depends on: None
   - Risk: Low
3. **Codemap** (File: `docs/CODEMAP/libraries.md`)
   - Action: add `cond.lua` to the `key/` tree and one line of API (`cond = bool|fn|fn(done)`).
   - Depends on: Phase 2
   - Risk: Low

## Phase 4: Refactor the GitHub keys (first real caller)
Depends on Phase 3 step 1 (packer lazy keys forward `cond`). A quick condition, so no placeholder is involved.

1. **Move the keys into the finder's `packer.lazy`** (File: `lua/beast/init.lua`)
   - Action: add `<leader>ghp` and `<leader>ghi` to the `keys` of `packer.lazy("beast.libs.finder", ...)` with `group = "GitHub"` and `cond = function() return Git.has_provider("github", Util.root()) end`. Delete `gh_keys`, `gh_root`, `gh_keys_set`, `sync_gh_keys` and the `BeastGithubKeys` autocmd. Keep the `if cfg.git then require("beast.libs.git.config").setup(cfg.git) end` block above them: the host overrides must apply before the first `cond` runs.
   - Why: the lazy trigger already loads the finder on first press, so the manual `load_lib` call goes away too.
   - Depends on: Phase 3 step 1
   - Risk: Medium (behavior change below)
2. **Behavior change, accepted**: the keys are decided once, when `packer.lazy` registers them at startup. Entering a project on another remote after startup (`:cd`, or a buffer from another project) no longer adds or removes them until the next start. Decision recorded 2026-11-17.
3. **Verify** (see Testing Strategy): start nvim in a GitHub repo, a non-GitHub repo and a folder with no repo.

### Shape after Phase 4

```lua
packer.lazy("beast.libs.finder", {
	setup = function(finder)
		finder.setup(cfg.finder or {})
	end,
	keys = {
		-- ...existing finder keys...
		{ "<leader>ghp", function() require("beast.libs.finder").open("gh_pr") end, desc = "GitHub pull requests", group = "GitHub", cond = on_github },
		{ "<leader>ghi", function() require("beast.libs.finder").open("gh_issue") end, desc = "GitHub issues", group = "GitHub", cond = on_github },
	},
})
```

with, above it, one shared quick check (a sync cached lookup, no placeholder):

```lua
local function on_github() return Git.has_provider("github", Util.root()) end
```

About 45 lines (`gh_keys` table, state flags, `sync_gh_keys`, autocmd) become about 8.

# Testing Strategy
- Headless tests: new `tests/test-key-cond.lua`, run with `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-key-cond.lua`. Uses a fake slow cond (`vim.defer_fn`) and a stubbed `vim.system`. Also run `tests/test-finder-keys.lua` and `tests/test-finder-gh-keys.lua` to confirm callers without `cond` are untouched.
- Bench: `scripts/bench-key-hint.lua` (hint reads `Key.managed`, which now may hold placeholders); no new bench, `safe_set` with no `cond` takes one `nil` check.
- Type check: the lua-language-server command from DEVELOPMENT.md (the `cond` type and the LSP rename).
- Phase 4 manual: start nvim in a repo with a GitHub remote (`<leader>ghp` and `<leader>ghi` listed under GitHub in the hint and working), in a repo with another host or no remote (keys absent), and outside any repo (keys absent, no error); `<leader>ghp` on first press loads the finder.
- Manual (PM spec scenarios): 1 and 2 with `cond = false/true` and a quick function on a throwaway `<leader>` key; 3 with a slow cond (`vim.system({"sleep","3"}, {}, function() done(true) end)`), open the hint during the wait; 4 press the placeholder; 5 and 6 with `done(false)`, a missing command, and `sleep 60` (10 s timeout toast); 7 with `buffer = true` and `:bwipeout` before the answer; 8 delete the key during the wait.

# Success Criteria
- [x] `cond = false` or a quick false: key absent from hint, cheatsheet and `Key.managed`.
- [x] `cond = true` or no `cond`: behaviour and conflict reporting unchanged.
- [x] Slow check: key exists immediately, startup time unchanged, editor responsive.
- [x] Pressing the placeholder toasts "still checking" and runs nothing else.
- [x] Slow yes: same keys run the real action, no new conflict record.
- [x] Slow no: key removed silently. Error or timeout: removed with exactly one toast.
- [x] Buffer-local keys checked per buffer; closed-buffer, replaced and deleted keys ignore a late answer.
- [x] `cond` never appears in the options passed to `vim.keymap.set`.
- [x] `packer.lazy` `keys` honour `cond`.
- [x] The GitHub pickers' keys exist exactly where the project has a GitHub remote at startup, with `sync_gh_keys` and its autocmd gone.
- [x] `test-key-cond.lua` passes, existing key/finder key tests pass, lua-language-server check is clean.

# Decisions for you
1. **LSP `cond` rename.** Recommended: rename the LSP field to `method` (Phase 3 step 2). Alternative: keep it and special-case `Beast.Lsp.KeySpec` with a type override; leaves two meanings of `cond` on one spec family.
2. **Packer lazy keys in this change.** Recommended: include Phase 3 step 1 so `packer.lazy` keys work. Alternative: ship only `Key.safe_set` support and let `packer.lazy` ignore `cond` until a follow-up.

---

## Completed

2026-11-17. Phase 1 quick conditions, Phase 2 slow conditions with placeholder, Phase 3 callers (packer lazy keys, LSP field rename), Phase 4 GitHub keys refactor.

- `1aff13d` feat(key): cond field gates keymap registration (boolean or quick function)
- `5344cc4` feat(key): slow cond registers a toast-only placeholder until done(ok) or timeout
- `243b925` feat(key): packer lazy keys honour cond; lsp key gate field cond renamed to method (the five language plugins in neovim_plugins were renamed in their own repos: python `71d6a5f`, typescript `ed0741e`, lua_ls `f49a0eb`, cpp `5fe9e0a`, json `c2469cd`)
- `710d508` refactor(init): GitHub picker keys use cond instead of sync_gh_keys and its autocmd

Verification: `tests/test-key-cond.lua` 48 passed; finder key tests 77 and 27, git remote 38, packer failures 21; stylua and lua-language-server check clean; `bench-key-hint` PASS (open p50 1.19 ms); startup 59.4 ms vs 59.8 ms before Phase 4 (hyperfine, 30 runs). E2E with the real config: GitHub keys present in a GitHub repo, absent for a gitlab remote, no remote and no repo; a file argument follows the file's project.
