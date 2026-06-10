# ADR-033: Toast Records as Mutable Handles (`update` / `dismiss_id` API)

**Status:** Accepted

**Date:** 2026-06-10

**Evidence:** Dev spec `docs/dev-specs/toast-lsp-progress.md` (Phase 1); commit `96c9d5e` (Phase 1 — generic update/dismiss_id API); files: `lua/beast/libs/toast/init.lua` (M.update, M.dismiss_id), `lua/beast/libs/toast/stack.lua` (M.update), `lua/beast/libs/toast/ui.lua` (width refresh in M.render); related: ADR-014 (parent-owned float lifecycle), ADR-026 (pure highlight contract).

## Context

`beast.libs.toast` was originally a fire-and-forget transient stack: `Toast(msg, level, opts)` queued a `Record`, the stack pushed it, `ui.render` painted it once, and a `vim.defer_fn` auto-dismissed it after `record.timeout` ms. The `Record` returned from `Toast()` was effectively a value object — callers had no reason to hold it, and the lib had no API to act on it again.

LSP progress (`$/progress`) is a stream of `begin → report* → end` events per token, arriving over seconds. A naïve "one toast per event" approach would flood the screen with dozens of redundant toasts for a single workspace index. The natural shape is **one toast per token, mutated in place** until `end`.

That requires the toast lib to support:
1. A sticky toast (`timeout = false`) — already supported.
2. A way to **rerender an existing toast** with new content without re-creating the float, replaying fade-in, or stacking a duplicate.
3. A way to **dismiss a single toast by id** (vs. the existing `toast.dismiss()` which clears all).

## Decision

`Record` is now a **handle**, not a value. The `Record` returned by `Toast()` (or `M.toast()`) is the durable identity of the toast for the rest of its lifetime. Two new public API functions act on it:

```lua
local rec = Toast("starting work...", "INFO", { timeout = false })
rec.message = "halfway done"
require("beast.libs.toast").update(rec)        -- repaint in place
-- ...later
require("beast.libs.toast").dismiss_id(rec.id) -- dismiss this one toast
```

Implementation:

- `stack.update(state, record)` — looks up the view via `state:find(record.id)`; reassigns `view.record = record` (so a fresh-record path also works, not just in-place mutation); calls `ui.render(view)` then `M.reflow(state)`. No-op if the view is already gone.
- `ui.render(view)` — recomputes `width` via `record:dimensions()` and resizes the float via `nvim_win_set_config` when it changed. Round-trips `row`/`col` from `nvim_win_get_config` (numbers in Neovim ≥ 0.10), then `reflow` snaps positions back to canonical anyway.
- `toast.update(record)` and `toast.dismiss_id(id)` — public wrappers with the same `vim.in_fast_event()` → `vim.schedule` guard as the existing `__call`.

`toast.dismiss()` (dismiss all) is retained unchanged.

## Alternatives Considered

1. **Add LSP progress directly to `notify` instead.** `notify` is the persistent log; progress is transient. Mixing the two would either pollute the log with 100 per-frame entries or require de-duplication logic that the toast model already provides.
2. **Keep toasts as fire-and-forget; let the progress adapter own its own float.** Rejected — the alignment, fade-in/out animation, palette highlights, and reflow logic are exactly what we'd reimplement. The toast lib *is* "single-line transient float at bottom-right"; that's the right primitive.
3. **Expose `state` / `stack` directly to callers.** Rejected — couples adapters to internals; violates the convention that libs publish only their `init.lua` surface (see `AGENTS.md` § *Library Layout*).
4. **Make `update` accept `(id, fields)` instead of a mutated `Record`.** Cleaner from a "value semantics" viewpoint, but every adapter would then re-implement the merge step. Mutating the cached `Record` directly is simpler and idiomatic for a 5-field struct.

## Rationale

1. **Two helpers, ~20 lines, no new state.** The change is minimal and additive — existing call sites are unaffected. No new module, no new config knob.
2. **Records were already mutable in spirit.** Fields like `record.message` were never immutable; nothing in the lib defended against mutation. We're just adding the **repaint** verb that was missing.
3. **Width-refresh in `ui.render` is the right home.** Progress messages change length frame to frame; without this, the cached float would clip or leave gaps. Doing it in `render` (vs. a separate `resize` method) means *every* update path (current and future) gets it for free.
4. **Symmetric fast-event guards** on `update`, `dismiss_id`, and the existing `__call` mean adapters can call them from any context without an outer `vim.schedule`.

## Consequences

**Positive:**
- The progress adapter (ADR-034) stays loosely coupled — never touches `stack`, `state`, or `ui` directly.
- Future stream-style toasts (build progress, long-running shell commands, etc.) can use the same handle pattern without further toast-core changes.
- `ui.render` is now resize-aware, which makes other dynamic-content scenarios trivial.

**Negative / Tradeoffs:**
- The `Record` returned by `Toast()` is now load-bearing. Callers who hold it must be aware that mutating fields without calling `update()` produces no visible change (consistent with how view layers usually work, but worth documenting).
- The `view.record = record` reassignment in `stack.update` means the view's `record` reference can swap mid-lifetime. Acceptable — the only field anyone reads off `view.record` after creation is `id` (in `state:find`), and `id` is the lookup key, so it's stable by construction.
