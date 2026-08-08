---
name: finder-lsp-exclude-current-position
description: LSP source factory skips the occurrence under the cursor when producing definitions/references/declarations/implementations
generated: 2026-08-09
---

> PM Spec: [docs/pm-specs/finder-lsp-exclude-current-position.md](../pm-specs/finder-lsp-exclude-current-position.md)

# Summary

`lua/beast/libs/finder/source/lsp.lua` is the single factory behind all four LSP-backed finder sources. Its `source.get` already builds each result's `pos`/`end_pos` (0-indexed, byte-based) before calling `cb(item)`. We capture the trigger-time cursor position once, up front, and skip `cb()` for any result whose file + line + column range matches it. No other file needs to change — `preflight.lua`, `init.lua`, and the query/picker pipeline already make their single-result/zero-result/multi-result decisions purely from however many items the source actually emits.

---

# Context

## Problem

`source.get` in `lsp.lua` streams every location the language server returns, with no notion of "the cursor is already here." That's fine for the common case (jumping from a usage site to a definition elsewhere), but for "find references" it means the occurrence under the cursor comes back as a row like any other — padding the list, and in the two-occurrence case (self + one other) forcing the picker open when the pre-flight auto-select logic (`docs/dev-specs/finder-auto-select.md`) would otherwise jump straight there for a true single-result set.

### Solution

At the top of `source.get`, before the async LSP request fires, read the trigger-time cursor position (`nvim_win_get_cursor(win)`) and the current buffer's full path (`nvim_buf_get_name(buf)`) — both already available from `win`/`buf`, which are derived synchronously before any yield. In the results loop, after computing `rel`, `pos`, and `end_pos` for a candidate item, skip it (don't call `cb`, don't bump `idx`) when `it.filename` equals the captured path, `it.lnum` equals the captured line, and the captured column falls within `[pos[2], end_pos[2])`. Everything downstream — pre-flight counting, auto-jump, "not found" notification, picker rendering — already reacts correctly to however many items the source actually produces, so no other module changes.

---

# Research

### Repo Search
- Searched for: `pos\[2\]`, `end_pos\[2\]`, `in_range`, `within_range` across `lua/beast/libs/finder/` and `lua/beast/util/`
- Found: no existing "cursor inside this item's range" helper. `action.lua`, `preview.lua`, `match_hl.lua`, and `format.lua` all read `item.pos[2]`/`item.end_pos[2]` directly inline (no shared range-check utility) — the codebase's convention here is a plain inline comparison, not a wrapper function.
- Reuse opportunity: No existing helper to call; follow the same inline-comparison convention rather than introducing a new one-off utility for a single call site.

- Searched for: how `filter.cur_win` and the item dedup key are used, to confirm the trigger-time window/exclusion basis
- Found: `finder/init.lua:M.open` constructs `Filter({ cwd = opts.cwd })` synchronously in the same call that invokes pre-flight; `Filter:new` captures `cur_win = vim.api.nvim_get_current_win()` at that same moment. `preflight.lua:M.check` calls `source.get(filter, cb)` synchronously right after, with no yield in between. So reading the cursor position inside `source.get` (via `filter.cur_win`) already reflects the trigger-time cursor — no need to thread a separate captured position through `Filter`.
- Reuse opportunity: Yes — reuse `filter.cur_win` as-is; no `Filter` schema change needed.

### Built-in / Existing Lib Check
- Checked: `vim.api.nvim_win_get_cursor`, `vim.api.nvim_buf_get_name` (both already used elsewhere in the finder lib, e.g. `action.lua`, `preview.lua`)
- Found: both cover exactly what's needed (1-indexed line / 0-indexed byte col; full buffer path) with no extra dependency.
- Decision: **Use** — no new abstraction, two built-in calls plus a plain inline range comparison at the one call site that needs it.

---

# Architecture Changes

- `lua/beast/libs/finder/source/lsp.lua` — capture trigger-time cursor position/current file at the top of `source.get`; skip `cb()` for the result matching it in the results loop.
- `tests/test-finder-lsp-source.lua` (new) — headless test stubbing `vim.lsp.get_clients`/`buf_request_all`/`locations_to_items` to verify exclusion behavior, following the stub pattern already used in `tests/test-finder-preloaded-items.lua`.

## Implementation Phases

## Phase 1: Exclude the current position in the LSP source — the entire change

1. **Capture trigger-time position** (File: `lua/beast/libs/finder/source/lsp.lua`, inside `source.get`, right after `win`/`buf` are resolved)
   - Action: Add `local cur_pos = vim.api.nvim_win_get_cursor(win)` and `local cur_file = vim.api.nvim_buf_get_name(buf)`.
   - Why: `win`/`buf` are already resolved synchronously before the async LSP request is built (before `vim.lsp.buf_request_all`), so this is genuinely trigger-time, not read-after-response.
   - Depends on: None
   - Risk: Low

2. **Skip the matching result** (File: `lua/beast/libs/finder/source/lsp.lua`, inside the `buf_request_all` callback's `for _, it in ipairs(qf_items) do` loop, after `pos`/`end_pos` are computed and before `cb({...})`)
   - Action: Compute `local pos = { it.lnum, math.max(0, it.col - 1) }` and `local end_pos = { it.end_lnum or it.lnum, math.max(0, (it.end_col or it.col) - 1) }` as today, then guard: if `it.filename == cur_file and pos[1] == cur_pos[1] and cur_pos[2] >= pos[2] and cur_pos[2] < end_pos[2]`, skip this item (`goto continue` or restructure the loop body so nothing after the guard runs — no `cb`, no `idx` increment, no `seen[key] = true`).
   - Why: This is the one place all four LSP sources (definitions/references/declarations/implementations) funnel through, and it already has every value the exclusion check needs (`it.filename`, `pos`, `end_pos`) computed for other reasons (dedup key, item construction).
   - Depends on: Step 1
   - Risk: Low — purely additive filtering; if the guard never matches (e.g., unsaved buffer with empty `cur_file`, or the LSP server never echoes the current position), behavior is byte-for-byte identical to today.

No changes needed in `preflight.lua`, `init.lua`, or the picker/query pipeline — they already derive single/multi/zero-result behavior from the item count `source.get` produces, which this phase changes correctly at the source.

---

# Testing Strategy

- Headless tests: write `tests/test-finder-lsp-source.lua` (`nvim --clean --headless -l tests/test-finder-lsp-source.lua`), stubbing `vim.lsp.get_clients`, `vim.lsp.buf_request_all`, `vim.lsp.util.make_position_params`, and `vim.lsp.util.locations_to_items` (following the fake-source stub pattern in `tests/test-finder-preloaded-items.lua`) to verify:
  - a result whose file/line/col-range matches the stubbed cursor position is not emitted (`cb` never called for it)
  - the other results in the same response are still emitted, in order, with `idx` counting only emitted items
  - a mid-word cursor column (inside `[pos[2], end_pos[2])` but not equal to `pos[2]`) is still excluded
  - when every returned result is excluded, `cb(nil)` still fires (existing "no results" notification path is unaffected)
  - a response with no match for the cursor position is emitted unchanged (regression guard for the "unaffected case")
- Bench: none — `source.get` is not on a benched hot path (no `scripts/bench-*.lua` covers finder LSP sources).
- Manual: run through PM spec scenarios 1–5 against a real language server (e.g. `lua_ls` on this repo) — reference `docs/pm-specs/finder-lsp-exclude-current-position.md` scenarios rather than duplicating steps here:
  1. Cursor on `profile` in the example snippet, "find references" → picker shows only the other 2 occurrences.
  2. A symbol with exactly one other occurrence besides the cursor → instant jump, no picker.
  3. "Go to definition" while already standing on the definition → "no definition found" warning, no picker, cursor doesn't move.
  4. "Go to definition" from a usage site → unchanged from current behavior.
  5. Cursor mid-word on an occurrence → still excluded.

---

# Success Criteria

- [ ] The occurrence the cursor is currently on never appears as a row in the references/definitions/declarations/implementations list.
- [ ] A symbol with exactly one *other* occurrence besides the current position jumps straight there, with no picker flash.
- [ ] A symbol whose only reported location is the current position shows the existing "not found" warning, with no picker and no cursor movement.
- [ ] Jumps from a usage site to a definition elsewhere look exactly as they do today.
- [ ] New headless test `tests/test-finder-lsp-source.lua` passes, covering exact-column, mid-word, all-excluded, and unaffected cases.
- [ ] No changes required (or made) to `preflight.lua`, `init.lua`, `filter.lua`, or the query/picker pipeline.
