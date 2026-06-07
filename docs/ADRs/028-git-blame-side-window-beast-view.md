# ADR-028: Full-File Blame as `Beast.View` Subclass with Native `scrollbind`

**Status:** Accepted

**Date:** 2026-06-07

**Evidence:** `lua/beast/libs/git/blame_view.lua`; `lua/beast/libs/view/init.lua` (Beast.View base); `lua/beast/libs/git/preview.lua` (sibling subclass); dev spec `docs/dev-specs/git-blame.md` § *Architecture Changes*, § *Risks & Mitigations*; related: ADR-022 (native git lib), ADR-027 (blame data layer).

## Context

The full-file blame UI needs a left-side window aligned line-for-line with the source buffer. It is *long-lived* (open until the user closes it or the source window goes away) and *interactive* (keymaps for show-commit, reblame-parent, reset, close). This is the second `Beast.View`-derived UI in `beast.libs.git` after `preview.lua`'s short-lived diff float, and the first long-lived one.

Two axes had to be resolved:

1. **UI class shape.** Reuse `Beast.View` (extend it as `BlameView`), or build a one-off file that calls `nvim_open_win` directly without inheriting the base lifecycle.
2. **Scroll sync.** Hand-roll per-line cursor mirroring on every source `WinScrolled` / `CursorMoved`, or use Neovim's native `scrollbind` window option.

The hand-rolled scroll mirror is what gitsigns' blame UI does (`actions.lua` blame buffer maintains its own line synchronization). It works but accumulates edge cases: fold expansion, signcolumn width changes mid-scroll, `'wrap'` mismatches, large jumps via `gg`/`G` racing the mirror callback.

## Decision

1. **Subclass `Beast.View`** via `BlameView = View:extend()`. Override `BlameView:close()` to delete the per-instance augroup, restore the source window's prior `scrollbind` value, then chain `View.close(self)` for buf/win teardown. Singleton via a module-local `current` pointer cleared in `close`.

2. **Use native `scrollbind`** on both windows. Capture `vim.wo[source_win].scrollbind` *before* setting it true (`source_scrollbind_prev`); restore on close. Trigger `:syncbind` once from the source window at open to align the initial position.

3. **Per-instance autocmd group** `BeastGitBlameView_<bufnr>` cleans up the view on either window's `WinClosed` or the source buffer's `BufWipeout` / `BufUnload`. All callbacks `vim.schedule`-wrap their `self:close()` to avoid the "can't delete window from autocmd" trap.

## Alternatives Considered

1. **Standalone module without Beast.View.** Skip the base class; manage buf/win + lifecycle directly. Rejected — the view base already encodes `:is_valid` + `:close` semantics every BeastVim UI needs, and `preview.lua` set the precedent. Diverging here would create a second "what's the lifecycle contract?" pattern in the same lib.
2. **Hand-rolled scroll mirroring (gitsigns shape).** Subscribe to source `WinScrolled`/`CursorMoved` and call `nvim_win_set_cursor(blame_win, ...)`. Rejected — accumulates edge cases (folds, large jumps, wrap mismatches). `scrollbind` is exactly the primitive Vim ships for this, debugged for decades, and gets fold-aware sync for free.
3. **Render blame as virt_text on the source buffer (a "ghost gutter").** No second window at all. Rejected — virt_text doesn't scroll-bind (it's part of the line, which is what we want for the cursor-blame layer), but a full-file overlay would compete with treesitter, signs, and diagnostic virt_text. The side-window approach is the standard idiom for a reason.
4. **Reuse `preview.lua`'s float.** Repurpose the existing diff-float subclass to render blame. Rejected — `preview.lua` is a transient float that auto-closes on `CursorMoved`; blame is a persistent split with its own keymaps. The two lifecycles are fundamentally different even if both extend `Beast.View`.
5. **`vim.api.nvim_set_decoration_provider` instead of an extmark batch.** A per-redraw decoration callback would push blame text only for visible lines (cheaper for huge files). Rejected as premature optimization — the bench shows a full-file blame paint is well under a frame on the largest file in this repo, and the extmark-batch approach makes scroll-sync trivial (the lines are real buffer lines, scrollbind just works).

## Rationale

1. **`Beast.View` already encodes the contract.** Subclassing means `BlameView:is_valid()`, the `:new(buf, win)` constructor, and the `:close()` chain come for free. The override hooks (delete augroup, restore scrollbind) are explicit and minimal.
2. **`scrollbind` is exactly the right primitive.** Vim's documentation: "When the binding is set, the windows are bound together for vertical scrolling." It handles fold-aware sync, line-count mismatches, and large jumps. We rely on it for the dominant 99% of cases and skip the entire mirror-the-cursor codepath.
3. **`source_scrollbind_prev` restores prior state.** A user might have had `scrollbind` set for some other reason (e.g. comparing two buffers manually). Captured-then-restored means closing the blame view leaves their session as it was.
4. **Per-instance augroup, never the same one twice.** Group name keyed by `<bufnr>` (the blame buf) and `pcall`-wrapped delete on close means re-entry is safe. WinClosed dispatch checks the matched window id against `self.source_win` and `self.win`, so the augroup fires for the right tear-down.
5. **Singleton matches user expectation.** Like `preview.lua`, only one blame view at a time. Opening a second one closes the first — no surprise tile-storming of split layouts.

## Consequences

- **Positive:** Scroll sync works on day one without bug-fixing fold/wrap edge cases. If Vim's `scrollbind` semantics improve in a future release, we inherit the improvement.
- **Positive:** Lifecycle is observable via `:augroup` and `nvim_get_autocmds({ group = "BeastGitBlameView_<bufnr>" })`. After a close, the group is gone — a one-line manual test.
- **Positive:** The pattern is now a precedent: any future BeastVim long-lived side window (e.g. a "diagnostics column" or "git log split") can extend `Beast.View` + use `scrollbind` the same way.
- **Negative:** `scrollbind` synchronizes *topline*, not cursor line. If the user has cursor on line 200 of the source and scrolls so line 200 is at the top, the blame window scrolls accordingly but the blame cursor stays where it was. Acceptable — the user interacts with the source window normally; the blame window is read-only context.
- **Negative:** `scrollbind` is global Vim state on each window, not a contained subscription. If `:set scrollopt-=ver` is in the user's vimrc, sync breaks. Documented as a known limitation; reset of `scrollopt` would need to be opt-in (we don't set it ourselves to respect user config).
- **Risk:** If the source window is closed *and* re-opened on the same buffer between the WinClosed autocmd firing and the scheduled `self:close()` running, we could briefly leak a blame window pointing at a dead source. Mitigated by the WinClosed dispatch checking the matched winid (the new window has a different id), and by the singleton ensuring at most one blame view exists.
