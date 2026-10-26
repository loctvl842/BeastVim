---
name: toast-repeat-count
description: Merge identical visible toasts into one line with an "xN" count, restarting the display timer on each repeat
generated: 2026-10-26
---

> PM Spec: [docs/pm-specs/toast-repeat-count.md](../pm-specs/toast-repeat-count.md)

# Summary
`Toast` currently stacks one line per call, even for identical messages. We add a merge step in the toast stack: a new record whose text, level and title match a visible (or still queued) auto-dismissing toast bumps that toast's `count` instead of opening a window. The render path appends an accent-colored `xN` (`x99+` from 100) after the message, the float is widened, and the dismiss timer is restarted.

---

# Context

## Problem
`lua/beast/libs/toast/` has no notion of identity: `init.lua` creates a `Record` per call and `stack.push` always queues it for display, so a repeating message (the new error/warning toasts from `beast.libs.messages`, formatter errors, "Pattern not found") fills the corner with identical lines. Dismissal is one fire-and-forget `vim.defer_fn` per record, which cannot be restarted, and the render path has no place for a count.

### Solution
Records carry a `count` and an identity `key`. `stack.push` first looks for a match among open views (not closing, not sticky, no custom segments) and queued records; on a hit it increments `count`, restarts that view's timer and re-renders in place (reusing the `update` + `reflow` path used by progress toasts). Dismissal timers become per-view handles so they can be reset. The renderer draws the count after the message with a new `BeastToastCount` highlight, and `Record:dimensions()` includes it so the float widens.

---

# Research

## Research

### Repo Search
- Searched for: `count`, `repeat`, `dedup`, `timeout`, `defer_fn` in `lua/beast/libs/toast/`; users of `Toast(`; `lua/beast/libs/toast/progress.lua`; `lua/beast/libs/toast/test.lua`; `tests/` toast files; `lua/beast/libs/notify/`.
- Found:
  - `toast/init.lua:M.toast` builds a `Record` and calls `stack.push`; `stack.show` opens the window and arms one `vim.defer_fn(... M.remove ..., record.timeout)` with no handle (`stack.lua`).
  - `stack.update(state, record)` re-renders an existing view and calls `reflow`: the in-place path already exists (used by progress via `Toast.update`).
  - `ui.render` already widens the float when `record:dimensions()` changes, and `record.segments` exists for custom per-fragment highlights (progress). Progress uses `timeout = false` (`progress.lua:154`), so it is sticky and has segments.
  - `progress.lua` has its own `(N)` counting (`BeastToastProgressCount`), separate from this feature.
  - `toast/test.lua` is a manual visual harness (series of toasts), not an automated test. No `tests/test-toast*.lua` exists.
  - `beast.libs.notify` has its own stack (`vim.notify`); out of scope.
  - New callers that repeat: `lua/beast/libs/messages/init.lua` (error/warning routing), `libs/packer/*` ("Loading ..."), `libs/view/buf.lua` ("saved").
- Reuse opportunity: **Yes** - `stack.update`/`reflow`, widening in `ui.render`, `Record:dimensions`, the highlight module (`toast/highlights.lua`) and its `BeastToastProgressCount` style.

### Built-in / Existing Lib Check
- Checked: `vim.defer_fn` (returns a libuv timer), `vim.uv.new_timer`, `vim.fn.strdisplaywidth`, existing toast stack/state/record/ui modules.
- Found: `vim.defer_fn` returns the underlying `uv_timer_t`, which supports `stop()`/`start()`/`close()`; so no new timer library is needed. Floating-window creation works headless, so the stack can be tested without a UI.
- Decision: **Reuse** the existing update/reflow path and **Build** only: record identity + count, a match step in `stack.push`, a restartable timer on the view, and the count segment in `ui.render`. No new module.

---

# Open Decisions (defaults used; change if you disagree)

1. **Queued duplicates.** The stack staggers new toasts (`config.stagger`, 70 ms) through a queue. A repeat that arrives while an identical record is still queued bumps the queued record's count, so a burst of N identical calls shows `xN` immediately instead of an animated `x1..xN`.
2. **Toasts being closed.** A toast mid fade-out is not merged into; the repeat opens a new toast (so a repeat is never silently swallowed).
3. **Opt-out.** `opts.merge = false` on a call disables merging for that toast (cheap escape hatch, default on). Sticky (`timeout = false`) and `segments` toasts never merge.

---

# Architecture Changes
- Modify `lua/beast/libs/toast/record.lua` - add `count` (starts at 1), `key` (message + level + title), `mergeable` (timeout not false, no segments, `opts.merge ~= false`); `dimensions()` adds the count width; export the label formatter (`x2` ... `x99+`).
- Modify `lua/beast/libs/toast/stack.lua` - add `find_match(state, record)`; in `push`, merge into a matching view or queued record; replace the bare `defer_fn` in `show` with a per-view timer; `remove` marks the view `closing` and cancels its timer.
- Modify `lua/beast/libs/toast/ui.lua` - render the count after the body (trim the message first so the count is never cut), paint it with `BeastToastCount`.
- Modify `lua/beast/libs/toast/highlights.lua` - add `BeastToastCount` (accent2, bold, same as `ProgressCount`).
- New `tests/test-toast-repeat.lua` - headless tests for key/label/merge/timer.
- Update `docs/CODEMAP/libraries.md` via `/update-codemap`.

## Implementation Phases

## Phase 1: Merge and count - repeats collapse into `xN`
1. **Record identity and label** (File: `lua/beast/libs/toast/record.lua`)
   - Action: Add `count = 1`, `key`, `mergeable` to `Record:new`; add `M.count_label(n)` returning `"x" .. n` or `"x99+"`; make `dimensions()` add `1 + #label` when `count > 1`.
   - Why: single place that defines identity and the visible width.
   - Depends on: None
   - Risk: Low
2. **Merge in the stack** (File: `lua/beast/libs/toast/stack.lua`)
   - Action: `find_match(state, record)` scans `state.views` (skipping `closing`) then `state.queue` for the same `key` and `mergeable`. `push`: on a view hit, `count = count + 1`, restart the view timer, `ui.render` + `reflow`; on a queue hit, `count = count + 1` on the queued record; otherwise enqueue as today. In `show`, create the dismiss timer per view (`view.timer`) with `vim.defer_fn`, and in `remove` set `view.closing = true` and stop/close the timer. A restart uses `timer:stop(); timer:start(timeout, 0, cb)` (callback re-wrapped with `vim.schedule_wrap`).
   - Why: the actual feature; keeps "repeat keeps it alive" semantics from the PM spec.
   - Depends on: Step 1
   - Risk: Medium (timer lifecycle: a stale timer must never remove a merged toast; guard in the callback by checking the view is still open and not closing).
3. **Render the count** (File: `lua/beast/libs/toast/ui.lua`, `lua/beast/libs/toast/highlights.lua`)
   - Action: In the non-segment branch, build `body_text = trim(message, inner_w - count_w) .. " " .. label` when `count > 1`; add an extmark over the label with `BeastToastCount`. Add the highlight (accent2 + bold).
   - Why: shows `x2` in the accent color after the message, before the title (PM Target Behavior).
   - Depends on: Step 1
   - Risk: Low (byte vs display width: label is ASCII).

## Phase 2: Tests and docs
1. **Headless tests** (File: `tests/test-toast-repeat.lua`)
   - Action: Cover `count_label` (`x2`, `x99`, `x99+`); identical calls produce one view with `count == N`; different text, level or title produce separate views; a merge into a non-adjacent earlier toast; a repeat restarts the timer (short timeout: repeat at 60% of it, still alive at 100%, gone after the restarted window); sticky and `segments` toasts are not merged; repeat during fade-out opens a new toast; a repeat after dismissal starts at count 1; burst of N calls within the stagger window yields one toast with `xN`.
   - Why: PM scenarios 1-5 as automated checks.
   - Depends on: Phase 1
   - Risk: Low (needs `vim.wait` for the stagger and timers).
2. **Manual harness + codemap** (File: `lua/beast/libs/toast/test.lua`, `docs/CODEMAP/`)
   - Action: Add a "repeat" series to the manual harness (same message at an interval) for visual checking; run `/update-codemap`.
   - Why: visual verification of width growth and the highlight; repo convention.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy
- Headless tests: new `tests/test-toast-repeat.lua` (`nvim --clean --headless -l tests/test-toast-repeat.lua`); also re-run `tests/test-messages-router.lua` (uses `Toast` through a stub) and `tests/test-searchcount.lua`.
- Bench: no hot path touched (toasts are event-driven); optionally `./scripts/bench-startup.sh` to confirm no startup change.
- Manual (PM scenarios in `docs/pm-specs/toast-repeat-count.md`):
  1. `/zzz` Enter, twice quickly: one "Pattern not found: zzz x2" line.
  2. Keep repeating: count climbs and the toast stays; stop and it fades ~2.2 s after the last repeat.
  3. Trigger A, B, A: two lines, A shows `x2`.
  4. Same text with different title/level: separate lines.
  5. LSP progress toast: unchanged `(N)` style, not merged.
  6. 100+ repeats (`:lua for i=1,150 do Toast("x") end`): `x99+`.
  7. Compare the look with `docs/pm-specs/mockups/toast-repeat-count.html`.

# Success Criteria
- [x] Firing the same toast twice shows one line ending in `x2`.
- [x] Each further repeat increases the count; 100 or more shows `x99+`.
- [x] A repeat merges into the matching toast even when other toasts are visible.
- [x] A repeat restarts the display time.
- [x] Different text, level or title remain separate lines.
- [x] After a toast disappears the same message starts again with no count.
- [x] Sticky and progress toasts behave as before.
- [x] A repeat during fade-out is not lost.
- [x] The float widens to fit the count; the message is trimmed before the count when too long.
- [x] `tests/test-toast-repeat.lua` passes; lint and format clean.

---

## Completed

2026-10-27. Phase 1 (merge + count) and Phase 2 (tests, manual harness series, codemap).

- `39db8e3` feat(toast): merge identical toasts into one line with an xN count

Deviations from this spec:
- Merging also covers a toast already taken off the queue but not yet shown (`state.inflight`); without it the first call of a burst was missed.
- Found and fixed a pre-existing bug in `record.lua`: `timeout = false` was turned into the default timeout by an `and/or` expression, so "sticky" toasts (LSP progress) actually auto-dismissed. Sticky now really means sticky; this changes progress toasts to behave as `progress.lua` intended (dismissed by `dismiss_id`).
- The manual harness gained `M.repeats()` in `lua/beast/libs/toast/test.lua`.

Verification: `tests/test-toast-repeat.lua` 22/22; `tests/test-messages-router.lua` 19/19; `tests/test-searchcount.lua` 12/12; real-config embedded run: three identical toasts show `Pattern not found: foo x3`, a fourth makes `x4`, a different toast stays separate, and everything clears after the timeout.
Not verified: the look of the badge in a real terminal (colors, spacing); LSP progress toasts staying visible for long tasks and dismissing when done (behavior changed by the sticky fix).
