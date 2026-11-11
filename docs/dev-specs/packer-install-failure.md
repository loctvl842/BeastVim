---
name: packer-install-failure
description: Persist plugin install failures, skip known-broken plugins on later starts, and keep packer.setup running when vim.pack.add throws
generated: 2026-11-11
---

> PM Spec: [docs/pm-specs/packer-install-failure.md](../pm-specs/packer-install-failure.md)

# Summary

Wrap the `vim.pack.add` call in `packer.setup` so a failed clone no longer aborts setup, record failures in a small JSON file under `stdpath("state")`, filter recorded-and-still-missing plugins out of later `vim.pack.add` calls until a retry window expires, and surface failures in the Packer UI with a retry key.

---

# Context

## Problem

`lua/beast/libs/packer/init.lua` passes every spec to `vim.pack.add` on each start. `vim.pack.add` clones any plugin whose directory is missing, synchronously, and **throws** after installing the others. The current `not packadd_ok` branch (`init.lua:383-396`) notifies and `return`s, so Step 5 (eager `config` calls) and the rest of `setup` never run. Nothing remembers the failure, so the next start repeats the clone (~300ms each, measured 824ms for one bogus repo). The error goes through `vim.notify`, not Toast. The Packer UI lists only installed plugins, so a failed one is invisible there.

### Solution

A new `lua/beast/libs/packer/failures.lua` owns the persisted record (`name -> {src, reason, at}`) and the retry-window rule. `setup` consults it before `vim.pack.add` to drop blocked specs, records any spec still missing on disk after a throw, shows one combined Toast, and continues. `state.load` skips plugins marked failed so lazy triggers do not raise `packadd` errors. The UI gains a "Failed" section and an `r` retry action.

---

# Research

### Repo Search
- Searched for: `vim.pack.add`, `vim.pack.get`, `installed_plugins`, `stdpath("state")`, `stdpath("cache")`, `Toast(`, `operation.`, `PackChanged` across `lua/beast/libs/packer/`, `lua/beast/libs/session/config.lua`, `lua/beast/libs/finder/source/live_grep/engine/index.lua`.
- Found: `vim.pack.add` is called once (`init.lua:369`) with a `load` callback that loads eager plugins; failure branch at `init.lua:383-396` returns early. `state.installed_plugins` is only primed lazily by the UI (`ui.lua:62`). Persisted data convention: `stdpath("state")` for session data (`session/config.lua:4`), `stdpath("cache")/beast/...` for caches. The UI "pending" list only includes `state.installed_plugins` (`ui.lua:435`). The `update_plugin` handler already probes remotes with `git ls-remote` (`ui.lua:1489`). No existing failure persistence. No packer test file exists in `tests/`.
- Reuse opportunity: Yes - `Toast` global, the `operation` module for in-session status, `_actions_handler` / `config.ui.actions` pattern for the retry key, `vim.json` encode/decode.

### Built-in / Existing Lib Check
- Checked: `vim.pack.add` behavior with one bogus and one good source (measured in this session, Neovim 0.12.6): good plugin is installed, call then throws `Repository not found`, ~824ms, and the second start repeats the clone.
- Found: `vim.pack.add` offers no "skip failures" option, so filtering specs beforehand is required. `vim.uv.fs_stat` on `stdpath("data")/site/pack/core/opt/<name>` is a cheap installed check and avoids `vim.pack.get()` (git per plugin, see note at `init.lua:213`).
- Decision: **Reuse** Toast/operation/UI action patterns, **Build** one small module (`failures.lua`).

### Open question to verify first (Phase 1, step 1)
When `vim.pack.add` throws, does it still invoke the `load` callback for the plugins that installed fine? If not, `setup` must `state.load` the installed eager plugins itself. A headless probe settles this before any code is written.

**Resolved:** it does. With one bogus and one good spec, the `load` callback fired for the good plugin before the call threw (Neovim 0.12.6). `setup` needs no manual eager loading.

---

# PM Spec Gaps

- The PM spec says "install/sync action in the Packer window". The UI has no install or sync action today (only Load, Sort, Delete, Update, Filter, Group, Profile, Help, Close). `update` on a never-installed plugin does not install it. This spec adds a dedicated **Retry** action (`r`). The PM spec wording should read "retry action". Recommended: edit that phrase in the PM spec.
- The PM spec's retry window and repeat-toast decisions were approved at the suggested defaults: 24 hours, toast once per window.

---

# Architecture Changes

- `lua/beast/libs/packer/failures.lua` (new) - load/save the JSON record, `record`, `clear`, `is_blocked`, `list`, age formatting.
- `lua/beast/libs/packer/config.lua` (modified) - `install_retry_hours = 24` option.
- `lua/beast/libs/packer/init.lua` (modified) - filter blocked specs, pcall `vim.pack.add`, record failures, one combined Toast, continue setup, replace the early `return`.
- `lua/beast/libs/packer/state.lua` (modified) - `state.failed_plugins` set; `state.load` returns early for failed plugins.
- `lua/beast/libs/packer/ui.lua` (modified) - "Failed" section, `retry_install` handler, help and action-bar entry.
- `lua/beast/libs/packer/health.lua` (modified) - report recorded failures.
- `tests/test-packer-failures.lua` (new) - unit tests for the record and window logic.

## Implementation Phases

## Phase 1: Setup survives a failure - keep going and report once
1. **Probe `vim.pack.add` failure behavior** (File: scratch only)
   - Action: headless script with one bogus and one good spec plus a `load` callback; record whether the callback fires for the good one and what is on disk.
   - Why: decides whether `setup` must load eager plugins itself.
   - Depends on: None
   - Risk: Low
2. **Add `failures.lua` with in-memory API** (File: `lua/beast/libs/packer/failures.lua`)
   - Action: `record(name, src, reason)`, `clear(name)`, `list()`; persistence added in Phase 2.
   - Depends on: None
   - Risk: Low
3. **Stop aborting on throw** (File: `lua/beast/libs/packer/init.lua`)
   - Action: after `xpcall` failure, compute specs still missing on disk (`fs_stat`), record them, mark `state.failed_plugins`, load installed eager plugins if step 1 showed the callback did not run, emit one combined `Toast`, and fall through to Step 5 instead of `return`. Skip config for failed eager plugins.
   - Why: PM rule "a failed download never stops the remaining plugins".
   - Depends on: Steps 1, 2
   - Risk: Medium (ordering of load vs config)
4. **Skip failed plugins in lazy loads** (File: `lua/beast/libs/packer/state.lua`)
   - Action: `state.load` returns silently if `failed_plugins[name]`.
   - Why: a filetype/key trigger must not raise `packadd` errors for a missing plugin.
   - Depends on: Step 3
   - Risk: Low

## Phase 2: Remember failures across starts
1. **Persist the record** (File: `lua/beast/libs/packer/failures.lua`)
   - Action: JSON at `stdpath("state") .. "/beast/packer-failures.json"`, loaded lazily, saved on `record`/`clear`, tolerant of a missing or corrupt file (treated as empty).
   - Depends on: Phase 1
   - Risk: Low
2. **Filter blocked specs before `vim.pack.add`** (File: `lua/beast/libs/packer/init.lua`)
   - Action: drop a spec when it is missing on disk, has a record with the same `src`, and age < window. Mark it in `state.failed_plugins`. Prune records for plugins no longer in config or with a changed `src`, and records whose plugin is now on disk.
   - Depends on: Step 1
   - Risk: Medium (must not skip a spec that is on disk)
3. **Retry window option** (File: `lua/beast/libs/packer/config.lua`)
   - Action: `install_retry_hours = 24`.
   - Depends on: None
   - Risk: Low
4. **Toast on a retry that fails again** (File: `lua/beast/libs/packer/init.lua`)
   - Action: when the window expired and the retry fails, record again and Toast once.
   - Depends on: Steps 1, 2
   - Risk: Low

## Phase 3: Show and retry failures in the Packer window
1. **"Failed" section** (File: `lua/beast/libs/packer/ui.lua`)
   - Action: list `failures.list()` entries with icon, name, reason, and age, separate from Loaded / Not Loaded.
   - Depends on: Phase 2
   - Risk: Low
2. **Retry action** (File: `lua/beast/libs/packer/ui.lua`, `lua/beast/libs/packer/config.lua`)
   - Action: `r` on a failed row calls `failures.clear`, then `vim.pack.add({spec}, {confirm=false, load=false})` in a pcall; success marks it installed and Toasts; failure re-records and Toasts. Add to `config.ui.actions`, help view, action bar.
   - Why: no install action exists today (PM spec gap above).
   - Depends on: Step 1
   - Risk: Medium
3. **Health check** (File: `lua/beast/libs/packer/health.lua`)
   - Action: `health.warn` for each recorded failure with reason and age.
   - Depends on: Phase 2
   - Risk: Low
4. **Convert download-failure notices to Toast** (File: `lua/beast/libs/packer/init.lua`)
   - Action: only the new failure path; leave other existing `vim.notify` calls untouched.
   - Depends on: Phase 1
   - Risk: Low

# Testing Strategy

- Headless tests: new `tests/test-packer-failures.lua` - record/clear round trip, corrupt-file tolerance, window expiry, changed `src` clears record, installed plugin is never blocked, combined-name formatting. Run `nvim --clean --headless -l tests/test-packer-failures.lua`.
- Bench: run `./scripts/bench-startup.sh` with and without a recorded failure (a bogus spec in a scratch config) and confirm the failing case is no slower than baseline. Packer is on the startup path, so the component benches in DEVELOPMENT.md apply.
- Manual: PM spec scenarios 1-6, using a scratch `NVIM_APPNAME` with one bogus GitHub spec. Include scenario 1 with an eager plugin's keymaps still present, and scenario 3 via the `r` key.
- E2E (per project rule): reproduce the original bug first with a private or nonexistent repo and confirm setup aborts, then confirm the fix.

# Success Criteria

- [x] With one unreachable plugin, every other plugin still loads and its settings and keymaps are present.
- [x] A single toast names the failed plugin on the first start; none on later starts inside the window.
- [x] Startup with a known-broken plugin is as fast as without it (no clone attempt).
- [x] The Packer window lists the failed plugin with reason and age.
- [x] The `r` retry action retries, and on success clears the failure.
- [x] Several failures in one start produce one combined toast.
- [x] No raw error message for a download failure.
- [x] A corrupt or missing failures file never breaks startup.
- [x] `tests/test-packer-failures.lua` passes and startup bench shows no regression.

---

# Completed

2026-11-11 - all three phases: setup survives a failed install, failures persist across starts with a 24h retry window, and the Packer window lists and retries them.

- `698959a` fix(packer): keep setup running when a plugin fails to install
- `663dfc0` feat(packer): remember failed installs and skip them until the retry window ends
- `b95ebd1` style(packer): apply stylua formatting (pre-existing lint in `init.lua` and `highlights.lua`, found while verifying)
- `6248b04` feat(packer): list failed installs in the packer window with a retry key

Verification: `tests/test-packer-failures.lua` 21 passed, 0 failed. End to end with a throwaway config containing an unreachable plugin: old code left `lua_ls` never loading after a failed clone (Step 6 triggers skipped), new code loads it; start 1 attempts the clone (1.29s), starts 2 and 3 do not (0.43s), an expired window retries once; UI retry verified for both failure (toast, stays listed) and success (row removed, record cleared, toast); `:checkhealth` warns per record. Startup bench (20 runs, warm, no failures recorded): 33.8ms with the changes vs 34.2ms before; wall-clock 49.2ms vs 52.6ms.

Deviations: the Packer window has no install action, so the PM spec's "install/sync" is delivered as the dedicated Retry key `r`. A stuck "install" operation row after a failed retry was fixed by clearing that operation (vim.pack never fires PackChanged on a failed clone).
