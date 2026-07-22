---
name: session-instant-fold-restore
description: Add deterministic fold snapshot restore so closed folds appear immediately on session load without LSP timing waits
generated: 2026-07-21
---

> PM Spec: [docs/pm-specs/session-instant-fold-restore.md](../pm-specs/session-instant-fold-restore.md)

# Summary

Implement instant fold restore by persisting a session-local fold snapshot and restoring from that snapshot synchronously during `session.load()`. This removes dependency on async LSP fold-range readiness for first paint. The implementation replaces timing-based waits/retries with deterministic data restore, then cleanly hands control back to the normal fold provider flow.

---

# Context

## Problem

`session.load()` currently sources Neovim session scripts that include `zc` commands, but for `foldmethod=expr` (especially `vim.lsp.foldexpr()`), fold structures may not exist yet when those commands run. The result is a visible mismatch: folds saved as closed can render open immediately after load, then change later. The technical gap is lack of a synchronous, persisted fold-shape source independent of async providers.

### Solution

After this change, session save writes an additional fold snapshot sidecar per session identity. Session load restores closed folds from that sidecar immediately, so first rendered state matches the saved state. Existing LSP/treesitter fold providers remain the long-term source of fold computation, but they no longer gate initial closed-fold presentation.

---

# Research

### Repo Search
- Searched for: `session`, `mksession`, `fold`, `foldclosed`, `foldexpr`, `LspAttach`, `SessionLoadPre`, `SessionLoadPost`, `vim.wait`, `defer_fn`
- Found:
  - `lua/beast/libs/session/init.lua` already parses saved session files for `sil! normal! zc`, then retries fold re-application via `BufWinEnter`/`LspAttach`/`vim.defer_fn`/`vim.wait`.
  - `lua/beast/libs/lsp/attach.lua` sets `foldmethod=expr` and `foldexpr=v:lua.vim.lsp.foldexpr()` on `LspAttach`.
  - `lua/beast/libs/treesitter/init.lua` sets treesitter `foldexpr` on `FileType` before LSP may override.
  - `tests/test-session.lua` covers save/load/exists/fallback behavior but has no assertions for delayed fold-provider timing.
- Reuse opportunity: **Yes** — keep current session identity/path/save guard logic and extend session persistence with fold snapshot data; reuse existing session test harness pattern.

### Built-in / Existing Lib Check
- Checked:
  - Neovim internals in cloned source:
    - `src/nvim/ex_session.c` (`:mksession`/`put_view`)
    - `src/nvim/fold.c` (`put_folds`)
    - `runtime/lua/vim/lsp/_folding_range.lua` (`foldexpr`, async refresh state)
    - `runtime/lua/vim/lsp/client.lua` (`LspAttach` + scheduled capability init)
  - Neovim APIs: `vim.fn.foldclosed`, `vim.fn.foldclosedend`, `vim.api.nvim_win_call`, `vim.fn.winsaveview`, `vim.fn.winrestview`, `vim.fn.readfile`/`writefile`, `vim.json.decode`/`encode`
- Found:
  - `:mksession` stores fold commands/options but not persisted LSP fold-range state.
  - `vim.lsp.foldexpr()` returns `'0'` when folding-range state is not active/populated yet.
  - LSP folding data is requested asynchronously after attach; no strict synchronous “ready” signal for first session-load paint.
- Decision: **Build** — add BeastVim-owned fold snapshot persistence and synchronous restore path; keep built-in session/LSP APIs as base plumbing.

---

# Architecture Changes

- New file: `lua/beast/libs/session/fold_snapshot.lua` — collect/serialize/deserialize per-file closed-fold ranges and apply them to loaded windows deterministically.
- Modified file: `lua/beast/libs/session/init.lua` — replace timing-based replay (`vim.wait` + deferred retries) with sidecar snapshot save/load hooks; keep existing session identity/fallback behavior.
- Modified file: `lua/beast/libs/session/config.lua` — add snapshot behavior knobs (enabled, max files/ranges, sidecar naming) with safe defaults.
- Modified file: `tests/test-session.lua` — add deterministic closed-fold restore assertions, including delayed-provider simulation that no longer relies on waiting.
- New file: `tests/test-session-fold-snapshot.lua` (or extend `tests/test-session.lua` if preferred by maintainer) — focused coverage for snapshot parse/write/apply edge cases.

## Implementation Phases

## Phase 1: Snapshot Data Model — persist closed folds independently of LSP
1. **Define snapshot schema + config defaults** (File: `lua/beast/libs/session/config.lua`)
   - Action: Add config fields for fold snapshot persistence (enabled, limits, sidecar suffix/path policy).
   - Why: Prevent unbounded sidecar growth and keep behavior explicit/tunable.
   - Depends on: None
   - Risk: Low

2. **Implement fold snapshot module** (File: `lua/beast/libs/session/fold_snapshot.lua`)
   - Action: Build pure helpers to collect closed folds from normal windows and encode/decode sidecar payload keyed by absolute file path.
   - Why: Isolates fold persistence concerns from session identity/load orchestration.
   - Depends on: Step 1
   - Risk: Medium

3. **Write sidecar during save** (File: `lua/beast/libs/session/init.lua`)
   - Action: On successful session save, write snapshot sidecar adjacent to the chosen session file.
   - Why: Guarantees snapshot and session layout stay paired by the same identity and fallback rules.
   - Depends on: Step 2
   - Risk: Medium

## Phase 2: Immediate Restore Path — no timing waits
1. **Load sidecar and apply synchronously in `session.load()`** (File: `lua/beast/libs/session/init.lua`)
   - Action: After sourcing session file, immediately apply closed folds from snapshot to current normal windows while preserving cursor/scroll view.
   - Why: Makes first visible state match saved state without waiting for async fold providers.
   - Depends on: Phase 1
   - Risk: High

2. **Remove timing-based replay mechanism** (File: `lua/beast/libs/session/init.lua`)
   - Action: Delete/reduce `vim.wait`, deferred retry loops, and `BufWinEnter`/`LspAttach` replay state introduced as timing workaround.
   - Why: PM requirement is immediate deterministic restore, not delayed eventual convergence.
   - Depends on: Step 1
   - Risk: Medium

3. **Provider handoff safety** (File: `lua/beast/libs/session/init.lua` + `lua/beast/libs/session/fold_snapshot.lua`)
   - Action: Ensure subsequent LSP/treesitter foldexpr activation does not produce disruptive cursor jumps or obvious flicker from restored closed state.
   - Why: Preserves stable UX after initial immediate restore.
   - Depends on: Step 1
   - Risk: High

## Phase 3: Validation Hardening
1. **Extend session tests for closed-fold determinism** (File: `tests/test-session.lua`)
   - Action: Add assertions that closed folds are already closed right after `session.load()`, including a delayed fold-provider simulation.
   - Why: Locks the regression that triggered this feature.
   - Depends on: Phase 2
   - Risk: Medium

2. **Add snapshot edge-case coverage** (File: `tests/test-session-fold-snapshot.lua` or `tests/test-session.lua`)
   - Action: Cover malformed sidecar, missing file mappings, out-of-range line numbers, and non-file buffers.
   - Why: Keep load path resilient without silent corruption.
   - Depends on: Phase 1, Phase 2
   - Risk: Low

---

# Testing Strategy

- Headless tests:
  - `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-session.lua`
  - `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-session-fold-snapshot.lua` (if split out)
- Bench:
  - No dedicated perf bench required (session load/save path, not per-keystroke hot path).
  - Run existing `scripts/bench-lsp.lua` only as a guard that LSP infra behavior remains unchanged.
- Manual:
  - Re-run PM scenarios from `docs/pm-specs/session-instant-fold-restore.md`:
    - close fold at line 14 in `init.lua`, quit, reopen, run `:lua require("beast.libs.session").load()`, verify fold closed immediately;
    - verify multiple closed folds restore immediately;
    - verify no noisy errors when snapshot data is absent.

# Success Criteria

- [x] After loading a session, previously closed folds are visibly closed immediately.
- [x] The fold state seen right after load does not change when language tooling finishes attaching.
- [x] Reopening a project no longer requires manually re-closing folds that were already closed when saved.
- [x] `tests/test-session.lua` passes with added immediate-fold assertions.
- [x] Snapshot sidecar read/write failures do not break normal session load behavior.

## Completed

2026-07-21 / 2026-07-22

Implemented as specced, with one deliberate deviation from the "hands control
back to the normal fold provider flow" wording in the Summary: `:{start},
{end}fold` only works when `'foldmethod'` is `manual`/`marker` (confirmed
empirically — it silently no-ops under `expr`, hidden by `silent!`), and
changing `'foldmethod'` discards whatever fold structure existed. Since there
is no synchronous "the async LSP folding-range data is ready" signal (as this
spec's own Research section already found — confirmed again by reading
Neovim's `_folding_range.lua`: its own refresh, `foldupdate()`, explicitly
skips any window that isn't `foldmethod=expr`, so once a window is taken over
it can never resync with live LSP fold data again either), `fold_snapshot`
forces the window to `foldmethod=manual` and **leaves it there for the rest
of the session** rather than handing back to `expr` — handing back
immediately would re-discard the just-restored folds before LSP data
arrives, reintroducing the exact flicker this feature exists to remove.
This was discussed explicitly with the maintainer (Vim's fold model has no
way to have some lines manually controlled while the rest is still computed
by treesitter/LSP within the same window — it's whole-window or nothing) and
confirmed as the intended trade-off: live treesitter/LSP fold recomputation
on edits is traded away, for windows that had a restored snapshot, in
exchange for a guaranteed flicker-free, fully-structured restore. Documented
in `fold_snapshot.lua`'s `apply_buf` docstring.

The snapshot itself was extended beyond the original "closed ranges only"
design to capture the **full top-level fold structure** — each range now
also records whether it was open or closed at save time
(`{start, end, was_closed}`). Restoring only closed ranges left every
*open*-but-foldable region with no fold structure at all once
`foldmethod=manual` took over, making those regions permanently unfoldable
for the rest of the session — a regression the maintainer caught by hand
while testing mid-implementation. `collect_win()` now temporarily forces
`zM` (close all) to reveal the complete top-level structure, tags each range
against the pre-disruption closed set, then restores the window's original
open/closed state and view before returning.

Three real bugs were found and fixed during implementation via adversarial
review (not just the happy path):
1. `:fold` silently failing under `foldmethod=expr` (the primary mechanism
   didn't work at all for the common case until `foldmethod=manual` was
   forced first).
2. A stale sidecar bug: reopening a fold and saving again left the old
   sidecar on disk, so a later `load()` re-closed folds the user had
   deliberately reopened (`M.write` now deletes the sidecar when the new
   snapshot is empty).
3. A cross-branch state leak: `pending_fold_snapshot` was only reset when
   `load()` found a session file, so switching to a branch/directory with no
   saved session at all could leave a previous branch's closed-fold data
   live for a later `LspAttach` to replay onto an unrelated buffer sharing
   the same absolute path (`pending_fold_snapshot = {}` now resets
   unconditionally at the top of `load()`).

Both bugs 2 and 3 have dedicated regression tests in `tests/test-session.lua`
and `tests/test-session-fold-snapshot.lua`.
