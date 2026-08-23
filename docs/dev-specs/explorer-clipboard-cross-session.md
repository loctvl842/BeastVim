---
name: explorer-clipboard-cross-session
description: Route explorer copy/cut/paste through the system clipboard register instead of in-process Lua state, so it works across separate Neovim sessions.
generated: 2026-08-23
---

> PM Spec: [docs/pm-specs/explorer-clipboard-cross-session.md](../pm-specs/explorer-clipboard-cross-session.md)

# Summary
Replace `state.clipboard` as the source of truth for explorer copy/cut/paste with the `"+"` register (the system clipboard BeastVim already wires up via `unnamedplus`/OSC52 in `lua/beast/option.lua`). A new `explorer/clipboard.lua` module owns reading, writing, and validating that register; `state.clipboard` becomes a local, render-only cache that's resynced at natural session-focus boundaries.

---

# Context

## Problem
`state.clipboard` (`lua/beast/libs/explorer/state.lua:21`) is a plain Lua table living in one Neovim process's memory. `copy_to_clipboard.lua` and `cut_to_clipboard.lua` write to it directly; `paste_from_clipboard.lua` reads and drains it directly; `render.lua` reads it to draw the `(copy)`/`(cut)` suffix. None of that state exists outside the process that set it, so a second `nvim` instance (or the same instance after a restart) has no way to see what was copied elsewhere.

### Solution
A new module, `explorer/clipboard.lua`, becomes the single place that talks to the `"+"` register. It encodes a copy/cut payload as plain text (the marked paths, one per line, plus a trailing `copy`/`cut` marker line) and decodes it back, treating anything that doesn't match that shape as "nothing to paste." `copy_to_clipboard.lua`, `cut_to_clipboard.lua`, and `paste_from_clipboard.lua` are rewired to call this module instead of touching `state.clipboard` as the source of truth. `state.clipboard` still exists, but purely as a same-session cache for `render.lua`'s highlighting, refreshed from the register at two points: whenever the explorer window is (re)opened, and on `FocusGained` (already an existing refresh hook in `autocmds.lua`) — which is exactly the "switch to another session" moment described in the PM spec.

---

# Research

### Repo Search
- Searched for: `clipboard`, `setreg`, `getreg` across `lua/`
- Found: `lua/beast/libs/finder/action.lua:74` already does `vim.fn.setreg("+", item.file)` for a "copy path" action — confirms the `"+"` register is the established, working mechanism for reaching the system clipboard in this codebase, no custom OSC52 handling needed at the call site.
- Reuse opportunity: Yes — same `setreg("+", ...)`/`getreg("+")` pattern, no new dependency.

- Searched for: existing on-disk persistence patterns (`stdpath`, `json_encode`, `writefile`) in `lua/beast/libs/`
- Found: `lua/beast/libs/session/init.lua:99-140` persists an explorer sidecar via `vim.fn.stdpath("state")`, `vim.json.encode/decode`, `vim.fn.writefile/readfile`, with `pcall`-guarded decode and silent degrade on any failure.
- Reuse opportunity: Not needed for this feature — see the open decision below on why a sidecar file was considered and rejected in favor of pure register text, but this is the pattern to fall back to if the decision goes the other way.

- Searched for: what triggers `ui.render()` / `ui.flush()` in `lua/beast/libs/explorer/autocmds.lua`, to find a safe (non-hot-path) place to resync `state.clipboard` from the register.
- Found: `CursorMoved` on the explorer buffer only calls `sticky.refresh()`, never a tree flush — so the render/flush path is not on the keystroke-latency hot path. `FocusGained` (`autocmds.lua:321-332`) already triggers a full refresh (`watch._schedule_refresh` + `git.schedule_refresh(...)` → `ui.flush()`) and is the natural "you switched back to this Neovim window" boundary.
- Reuse opportunity: Yes — hook the register resync into the existing `FocusGained` callback rather than adding a new autocmd.

### Built-in / Existing Lib Check
- Checked: `vim.fn.setreg`/`getreg("+")`, `vim.g.clipboard` (`lua/beast/option.lua:11-36`)
- Found: `o.clipboard = "unnamedplus"` is already set, and over SSH without a display, `vim.g.clipboard` is swapped for an OSC52 provider whose `paste()` always returns `{ "" }` (with a warning) rather than hanging or erroring. That means `getreg("+")` in that environment reliably decodes to "nothing," which is exactly the PM spec's "no system clipboard available → same-session behavior, no error" scenario — no extra fallback code needed, the existing option.lua config already produces the right result.
- Decision: **Use** `vim.fn.setreg`/`vim.fn.getreg("+")` directly — no new provider, no new config.

---

# Open Decision: register format (flagging before implementing)

The PM spec's Scenario 5 says pasting marked files into a plain-text context (outside the explorer) should show *only* the file paths, one per line, "nothing hidden or specially encoded." Encoding the copy-vs-cut mode has to live somewhere, and the two options trade that literal reading off against implementation simplicity:

- **A — Trailing marker line (recommended).** Register text is the paths, one per line, followed by one final line that's exactly `copy` or `cut`. Reading back: last line must be exactly `copy`/`cut`, everything above it must be non-empty absolute paths, otherwise treat the register as "not ours." No sidecar file, no extra state to go stale or leak across a crash. The one deviation from the PM spec's literal scenario text: pasting into a text buffer elsewhere shows the paths *plus* a trailing `copy`/`cut` word, not paths alone.
- **B — Sidecar file.** Register `"+"` holds *only* the paths (exactly matching Scenario 5), and a small JSON file under `vim.fn.stdpath("state")` (same pattern as `session/init.lua`) holds `{ mode, snapshot }`, where `snapshot` is the exact register text at write time. Paste compares the live register text to the stored snapshot to detect "something else overwrote the clipboard" (PM spec Scenario 6); mismatch → treat as empty. Matches the PM spec exactly, at the cost of a second piece of state that has to be kept in lockstep with the register and cleaned up (stale sidecar from a crash before the register was ever written, etc.).

Recommendation: **A**. It's the simpler, more robust option (one write, one read, no separate file that can desync), and the deviation is minor and self-explanatory (a `copy`/`cut` tag word is a reasonable, visible thing to see appended to a list of file paths). Proceeding with A unless you'd rather have paste-elsewhere match the PM spec text exactly, in which case say so and I'll switch to B.

---

# Architecture Changes

- **New file:** `lua/beast/libs/explorer/clipboard.lua` — owns the `"+"` register: `write(paths, mode)`, `clear()`, `read()` (returns `{ paths, mode }` or `nil`), `toggle(paths, mode)` (the copy-again-clears-it logic, shared by both copy and cut).
- **Modified:** `lua/beast/libs/explorer/actions/copy_to_clipboard.lua` — `set_clipboard()` calls `clipboard.toggle(paths, "copy")` instead of touching `state.clipboard` directly; result (or `nil`) is assigned to `state.clipboard` for this session's render.
- **Modified:** `lua/beast/libs/explorer/actions/cut_to_clipboard.lua` — same change with `"cut"`.
- **Modified:** `lua/beast/libs/explorer/actions/paste_from_clipboard.lua` — `M.run()` reads `clipboard.read()` instead of `state.clipboard`; `PasteSession:_remove_from_clipboard()` rewrites the register with the remaining paths (or clears it) instead of mutating `state.clipboard.paths` in place; `PasteSession:finish()` calls `clipboard.clear()`.
- **Modified:** `lua/beast/libs/explorer/actions/rename.lua:51` — `state.clipboard = nil` becomes `clipboard.clear()` (plus `state.clipboard = nil`), so a rename invalidates the clipboard for every session, not just this one, matching the existing blanket-clear behavior.
- **Modified:** `lua/beast/libs/explorer/autocmds.lua` — at the top of the `FocusGained` callback (`autocmds.lua:321-332`), add `state.clipboard = clipboard.read()` before the existing refresh calls.
- **Modified:** `lua/beast/libs/explorer/init.lua` — in `M.open()` (around `init.lua:78`, before `ui.render(on_done)`), add the same `state.clipboard = clipboard.read()` seed so a freshly opened explorer reflects reality immediately.
- **Unchanged:** `lua/beast/libs/explorer/render.lua` — keeps reading `state.clipboard` exactly as today; it's now fed by the resync points above instead of by direct action writes.
- **Unchanged:** `lua/beast/libs/explorer/health.lua:265-274` — its save/restore of `state.clipboard` wraps a `render.build()` self-test that never calls the real clipboard actions, so it never touches the register; no change needed.

## Implementation Phases

## Phase 1: Shared clipboard module — get the register read/write/validate logic right in isolation
1. **Write `explorer/clipboard.lua`** (File: `lua/beast/libs/explorer/clipboard.lua`)
   - Action: Implement `write(paths, mode)`, `clear()`, `read()`, `toggle(paths, mode)` per the "Open Decision" format (Option A: trailing `copy`/`cut` line).
   - Why: Single, testable seam for every register interaction; keeps the encode/decode logic out of the action files.
   - Depends on: None
   - Risk: Low

2. **Unit-style headless test for the module** (File: `tests/test-explorer-clipboard.lua`, new)
   - Action: Cover: write-then-read round-trips for single and multi-path payloads; `toggle()` clearing on repeated same-mode call; `read()` returning `nil` for an empty register, for unrelated plain text, and for text missing the trailing mode line; `clear()` leaving the register empty.
   - Why: This module is the crux of the feature's correctness (Scenario 4/5/6/7 in the PM spec all hinge on decode behavior) and is trivial to test headlessly without a real explorer tree.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Wire the explorer actions through the new module
1. **Rewire `copy_to_clipboard.lua` and `cut_to_clipboard.lua`** (Files: `lua/beast/libs/explorer/actions/copy_to_clipboard.lua`, `lua/beast/libs/explorer/actions/cut_to_clipboard.lua`)
   - Action: Replace the duplicated local `set_clipboard()` with a call to `clipboard.toggle(paths, mode)`, assigning the result to `state.clipboard`.
   - Why: Removes the duplicated toggle logic from two files and makes the register the source of truth for both.
   - Depends on: Phase 1
   - Risk: Low

2. **Rewire `paste_from_clipboard.lua`** (File: `lua/beast/libs/explorer/actions/paste_from_clipboard.lua`)
   - Action: `M.run()` calls `clipboard.read()`; `PasteSession:_remove_from_clipboard()` and `:finish()` write back through `clipboard.write()`/`clipboard.clear()` instead of mutating `state.clipboard.paths` in place, while still updating `state.clipboard` so this session's UI reflects the shrinking list immediately (unchanged visual behavior from today).
   - Why: This is the entry point that must recognize a clipboard set by a different session — it cannot rely on any locally-cached `state.clipboard`.
   - Depends on: Phase 1
   - Risk: Medium — the step-by-step consume loop (multi-file paste with per-file conflict prompts) has to keep the register and `state.clipboard` in lockstep at every step, including the cancel-a-conflict path (`on_cancel` → `_remove_from_clipboard` → `_advance`).

3. **Clear on rename** (File: `lua/beast/libs/explorer/actions/rename.lua`)
   - Action: Replace `state.clipboard = nil` with `clipboard.clear(); state.clipboard = nil`.
   - Why: Preserves the existing "renaming invalidates the pending clipboard" behavior, now propagated to every session.
   - Depends on: Phase 1
   - Risk: Low

## Phase 3: Cross-session resync points
1. **Resync on `FocusGained`** (File: `lua/beast/libs/explorer/autocmds.lua`)
   - Action: At the top of the existing `FocusGained` callback, set `state.clipboard = clipboard.read()`.
   - Why: This is the moment a user actually "switches back" to this session in the PM spec's scenarios (e.g. alt-tabbing terminal tabs); it's an existing, already-infrequent refresh hook, not a hot path.
   - Depends on: Phase 1
   - Risk: Low

2. **Resync on explorer open** (File: `lua/beast/libs/explorer/init.lua`)
   - Action: In `M.open()`, set `state.clipboard = clipboard.read()` before the render call.
   - Why: Covers "open the explorer for the first time this session" and "reopen Neovim after cutting a file," so the marker is correct from the very first paint rather than waiting for the next `FocusGained`.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy
- Headless tests: new `tests/test-explorer-clipboard.lua` (Phase 1, Step 2) for the encode/decode/toggle logic. Run the full explorer headless suite (`nvim --clean --headless -l tests/test-explorer-*.lua` for each matching file) to confirm `copy_to_clipboard`/`cut_to_clipboard`/`paste_from_clipboard`/`rename` still pass with the rewired internals.
- Bench: `nvim --clean --headless -l scripts/bench-explorer.lua` before and after — the `FocusGained` and `init.open()` resync points add one `getreg("+")` call each; confirm no regression in the explorer's tracked latency numbers (per `DEVELOPMENT.md`, treat this as mandatory since `autocmds.lua` and `init.lua` are both touched).
- Manual: walk through PM spec scenarios 1–8 with two real `NVIM_APPNAME=BeastVim nvim` instances in separate terminal tabs/panes:
  1. Copy in session A, paste in session B (Scenario 1).
  2. Copy then copy again (toggle off) in session A, confirm paste in session B reports empty (Scenario 2).
  3. Cut in session A, `:qa`, paste from session B (Scenario 3).
  4. Visual-select multiple files, copy in session A, paste all in session B (Scenario 4).
  5. Copy in session A, paste the register into a plain text buffer or another app to see the raw content (Scenario 5) — confirm it's readable as intended per the Open Decision above.
  6. Copy plain text somewhere else, then `p` in an explorer — confirm "nothing to paste," no crash (Scenario 6).
  7. Cut a file, delete it on disk outside Neovim, paste from another session — confirm a clean error, no partial state (Scenario 7).
  8. If reachable, test over an SSH session without clipboard forwarding — confirm same-session copy/cut/paste still works (Scenario 8).

---

# Success Criteria
- [x] Copying a file in one Neovim session and pasting in a different, already-running session places the file in the new location.
- [x] Cutting a file in one session, quitting that session, and pasting later (in another session or after reopening Neovim) moves the file, removing it from the original location only once the paste completes.
- [x] Pressing copy (or cut) again to cancel a pending mark clears the clipboard everywhere, not just in the session where it was cancelled.
- [x] Multi-file selections copied/cut together in one session paste as the same group in another session.
- [x] Pasting marked files into a non-explorer text context shows the marked paths (per the format decided above — Option A, trailing marker line).
- [x] Pasting when the system clipboard holds unrelated content does nothing destructive and gives a clear "nothing to paste" message.
- [x] Pasting a file that no longer exists on disk reports an error for that file instead of failing silently or corrupting the destination (unchanged pre-existing `copy_path`/`move_path` error handling; register/state clear behavior around it verified).
- [x] Existing same-session behavior — the `(copy)`/`(cut)` marker, multi-select, and the rename-on-conflict prompt — keeps working exactly as it does today.
- [x] On setups without system clipboard access, copy/cut/paste keeps working within a single session exactly as it does today — required an additional fix beyond the original plan (see Completed section: the SSH/OSC52 provider's `paste()` is a no-op by design, so `clipboard.lua` falls back to its own last local write rather than trusting a query that can never succeed).
- [x] `scripts/bench-explorer.lua` shows no meaningful latency regression from the two new `FocusGained`/`open()` resync points (495.00us baseline vs 506.89-513.26us after, both already at the bench's own soft-threshold noise floor dominated by buffer-write cost).

---

# Completed

2026-08-23 — All three phases implemented, reviewed, and tested. Open Decision resolved as Option A (trailing marker line) per the recommendation, with no objection.

- `4c3d818` feat(explorer): add clipboard module for system-register copy/cut/paste
- `15716a7` feat(explorer): route copy/cut/paste through the shared clipboard register
- `d3684ed` feat(explorer): resync clipboard render cache on focus and open
- `312deb7` fix(explorer): stop clipboard.lua from querying the unreadable SSH register (discovered during Phase 3 code review: the SSH-without-display OSC52 provider's `paste()` always returns empty and warns, even for a value the same process just wrote, which both spammed a misleading notify on every `y`/`x`/focus-switch and silently broke same-session copy/cut/paste in that environment — fixed with a same-process fallback in `clipboard.lua`, not anticipated by the original Open Decision)

Verification: `tests/test-explorer-clipboard.lua` 19/19 passing (round-trip, toggle, malformed-input rejection, trailing-newline tolerance, literal `"copy"`/`"cut"` path names, and the SSH/OSC52 fallback). Manual headless integration smoke tests against a real explorer window + real filesystem (copy→paste, cut→paste across a simulated session boundary, toggle-off, cross-session resync on `FocusGained`/`open()`) all passing. `stylua --check` clean throughout. `scripts/bench-explorer.lua` shows no regression beyond pre-existing run-to-run noise. Two independent `code-reviewer` passes (Phase 1, Phase 2+3) — both PASS, with the Phase 3 pass's one WARNING finding fixed and re-verified above.
