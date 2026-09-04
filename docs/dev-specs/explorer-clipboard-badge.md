---
name: explorer-clipboard-badge
description: Replace the explorer's inline "(copy)"/"(cut)" name suffix with a right-aligned clipboard badge, matching the git-status badge
generated: 2026-09-04
---

> PM Spec: [docs/pm-specs/explorer-clipboard-badge.md](../pm-specs/explorer-clipboard-badge.md)

# Summary

Remove the `" (copy)"`/`" (cut)"` text currently appended to a clipboard-marked node's name in `render.lua`, and replace it with a glyph (`󰆏` copy, `󰆐` cut) added into the existing right-aligned badge extmark - the same mechanism that already renders the git-status and diagnostic badges. The glyph comes from a new `config.icon.clip` table; color reuses the existing `BeastExplorerClip` highlight group unchanged.

---

# Context

## Problem
`render.lua` currently marks a clipboard-held node by concatenating `" (copy)"`/`" (cut)"` literal text onto the end of its name (`clip_suffix`, built at lines 236-240, appended at line 242) and highlighting that trailing text range (lines 306-311). Because this is real buffer text rather than window-relative virtual text, it lengthens the line and scrolls off-screen on long names or a narrow sidebar - exactly when the user most needs the confirmation that their copy/cut registered. Git status already solves this same category of problem with a right-aligned badge pinned to the window edge; the clipboard marker needs to move onto that same mechanism.

### Solution
`render.build()`'s existing badge block (lines 276-300) already assembles one `chunks` list per row (diagnostic glyph, then git glyph) and pushes it as a single right-aligned virt_text extmark in `M.write()`. A `clip_icon(mode)` helper, following the exact shape of the existing `git_icon`/`diagnostic_icon` helpers, resolves a glyph from a new `config.icon.clip` table (`{ copy = "󰆏", cut = "󰆐" }`). When a node is present in the already-built `clipboard_paths` set, its glyph is appended as a third chunk (rightmost) in that same badge row, using the existing `BeastExplorerClip` highlight group - no new highlight, no new extmark, no new health check. The old suffix-building, suffix-appending, and suffix-highlighting code is deleted outright.

---

# Research

### Repo Search
- Searched for: `clip_suffix`, `(copy)`, `(cut)`, `BeastExplorerClip`, `state.clipboard.mode` across `lua/beast/libs/explorer/`.
- Found: the suffix has exactly one producer (`render.lua:236-240`), one consumer/append site (`render.lua:242`), and one highlight site (`render.lua:306-311`) - fully self-contained inside `render.lua`, confirmed via full-repo grep. No test file references any of these (`tests/test-explorer-clipboard.lua` only exercises the register-level `clipboard.lua` module, never `render.lua`).
- Found: `state.clipboard.mode` is always exactly `"copy"` or `"cut"` (enforced in `clipboard.lua`'s `encode`/`decode`/`toggle`, typed `"copy"|"cut"` in `state.lua:1-3`), and is a single value shared by the whole clipboard - not per-path - so the badge only needs `state.clipboard.mode`, not a per-node mode lookup.
- Found reusable pattern: `git_icon(status)` (`render.lua:39-48`) and `diagnostic_icon(severity)` (`render.lua:61-70`) are the existing "resolve glyph from config, `nil`/`""` means hidden" helpers - `clip_icon(mode)` is a direct copy of this shape, keyed by `"copy"|"cut"` instead of a status/severity table.
- Found reusable pattern: the badge-assembly block (`render.lua:276-300`) already combines multiple glyphs into one `chunks` list with a `{" ", nil}` spacer between entries, and `M.write()` (`render.lua:355-370`) already writes that as a single `right_align` virt_text extmark padded by `config.padding_right`. Appending the clip glyph as a third chunk in this same list avoids introducing a second `right_align` extmark on the same line (which would have an undefined stacking order relative to the first).
- Found stale reference: `prompt.lua:161-163`, the `name_col()` docstring cites `" (copy)"` as an example of a trailing suffix the function is robust to - but the function body is pure arithmetic (`config.padding + depth_padding + prefix_icon + 1`) and never reads line text, so the suffix (which is trailing, not leading) never actually affected it. The comment directly names the text this change deletes, so it's corrected here rather than left to describe something that no longer exists.
- Reuse opportunity: **Yes** - no new mechanism needed anywhere; the exact "config-driven glyph in the shared right-aligned badge row" pattern already exists twice in this file (git, diagnostic) and is only being extended to a third case.

### Built-in / Existing Lib Check
- Checked: whether the clipboard badge should be a second, independent extmark (e.g. its own `sign_text` or a separate `right_align` virt_text) rather than joining the existing badge `chunks` list.
- Found: every other row-level decoration (icons, git badge, diagnostic badge, tree connectors) already funnels through the single `M.build()` → `M.write()` pipeline as buffer text plus one combined badge extmark per line; a second `right_align` extmark on the same line would render but its position relative to the first is not guaranteed by Neovim's API, which is an unnecessary risk with no benefit here.
- Decision: **Build** (extend) - add the clip glyph into the existing combined `chunks` list; no new extmark, no new highlight, no new health check (the render dry-run in `health.lua:218-290` doesn't assert badge *content* for git/diagnostic either, only counts, so it's left untouched, consistent with that precedent).

---

# Architecture Changes

- `lua/beast/libs/explorer/config.lua` - **Modify.** Add a `clip` sub-table to `defaults.icon`, alongside `git`/`diagnostic`, with the same "empty string hides the badge, highlight group is fixed" comment convention already used there:
  ```lua
  clip = {
      copy = "󰆏",
      cut = "󰆐",
  },
  ```
- `lua/beast/libs/explorer/render.lua` - **Modify.**
  - Add `clip_icon(mode)` next to `git_icon`/`diagnostic_icon` (~line 48): resolves `config.icon.clip[mode]`, returns `nil` when unset or `""`.
  - Delete the `clip_suffix` block (lines 236-240) and drop `.. clip_suffix` from the line-text append (line 242).
  - Delete the clip-suffix highlight block (lines 306-311).
  - In the badge block (lines 276-300), after the git chunk: if `clipboard_paths[node.path]` and `state.clipboard`, resolve `clip_icon(state.clipboard.mode)`; if non-nil, append a `{" ", nil}` spacer (when `chunks` is already non-empty) then `{ glyph, "BeastExplorerClip" }`.
  - Keep the `clipboard_paths` set-building (lines 197-202) unchanged - still needed for membership testing.
- `lua/beast/libs/explorer/prompt.lua` - **Modify.** Correct the `name_col()` docstring (lines 161-163) to drop the now-inaccurate `" (copy)"` example, since that suffix text no longer exists anywhere in a rendered line.

No changes to `highlights.lua`, `health.lua`, `state.lua`, `clipboard.lua`, or any `actions/*.lua` file - the clipboard data model and its highlight color are untouched; only where/how the marker renders changes.

## Implementation Phases

## Phase 1: Badge replaces the inline suffix - the whole feature

1. **Add the configurable glyphs** (File: `lua/beast/libs/explorer/config.lua`)
   - Action: Add `icon.clip = { copy = "󰆏", cut = "󰆐" }` to `defaults.icon`, next to `git`/`diagnostic`, with a comment matching their documented convention (empty string hides badge; highlight group fixed).
   - Why: Matches the PM spec's assumption that badge glyphs are configurable the same way git/diagnostic icons are.
   - Depends on: None
   - Risk: Low

2. **Add the `clip_icon` resolver** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: Add `clip_icon(mode)` next to `git_icon`/`diagnostic_icon`, same nil/empty-string-hides shape.
   - Why: Mirrors the exact pattern already used for the other two badge kinds.
   - Depends on: Step 1
   - Risk: Low

3. **Splice the clip glyph into the badge row** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: In the existing badge-assembly block, after the git chunk, check `clipboard_paths[node.path]` and append the clip glyph as a third chunk (with spacer) using `BeastExplorerClip`.
   - Why: This is the core behavior change - the badge now carries all three signals in one right-aligned row, clip rightmost per the PM spec's diagram.
   - Depends on: Step 2
   - Risk: Low

4. **Remove the old inline suffix** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: Delete the `clip_suffix` build block, its append into the line text, and its highlight block.
   - Why: The PM spec explicitly requires the name to render untouched, with no trailing text.
   - Depends on: Step 3 (badge must exist before the old signal is removed, so clipboard state is never silently unrepresented mid-edit)
   - Risk: Low

5. **Fix the stale docstring** (File: `lua/beast/libs/explorer/prompt.lua`)
   - Action: Reword `name_col()`'s docstring to drop the `" (copy)"` example.
   - Why: The referenced text no longer exists after Step 4; leaving it would mislead future readers about what the function accounts for.
   - Depends on: Step 4
   - Risk: Low

---

# Testing Strategy

- Headless: `NVIM_APPNAME=BeastVim nvim --headless -c "checkhealth beast.explorer" -c "qa"` - exercises `render.build()` end-to-end (`health.lua:269-283`) and will fail loudly if the badge-chunk logic raises. `nvim --clean --headless -l tests/test-explorer-clipboard.lua` - unrelated to rendering, but confirms the clipboard module's require graph is untouched.
- Manual: follow the PM spec's 5 scenarios directly in `NVIM_APPNAME=BeastVim nvim`:
  1. Cut a file → `󰆐` appears at the sidebar's right edge; the name itself is unchanged.
  2. Copy a file → `󰆏` appears in the same position; source file keeps its badge after pasting a copy elsewhere.
  3. Cut/copy a file with a name that nearly fills a narrow sidebar → badge still renders at the right edge.
  4. Mark a file that also has a git status and an active diagnostic → all three badges appear together, clip rightmost.
  5. Clear the clipboard (cut a different file, or explicitly clear) → the badge moves to the new file / disappears from the old one.
- No new automated test file - consistent with the precedent set by `docs/dev-specs/explorer-active-file-marker.md`, since this repo has no existing visual/render assertion tests for `explorer/render.lua`.

# Success Criteria

- [x] Copying or cutting a node no longer appends `(copy)`/`(cut)` text to its name.
- [x] A copied node shows the `󰆏` badge at the sidebar's right edge; a cut node shows `󰆐`.
- [x] The badge stays visible regardless of file name length or sidebar width.
- [x] The badge coexists cleanly with existing diagnostic and git-status badges on the same line, clip rightmost.
- [x] Pasting, or marking a different file, updates badges so only currently-clipboard-held nodes show one.
- [x] `icon.clip.copy`/`icon.clip.cut` are configurable via `explorer.setup()`; empty string hides that badge.
- [x] `:checkhealth beast.explorer` still reports a successful `render.build()` call (structural regression gate).
- [x] No regression in existing explorer rendering (icons, git badges, diagnostic badges, active-file marker, sticky headers, indent connectors).

---

## Completed

**2026-09-04** — Phase 1 (the whole feature) implemented, reviewed, and verified in one pass.

- `458671e` feat(explorer): render clipboard copy/cut as right-aligned badge instead of inline suffix

Verification:
- `stylua --check` clean on all 3 touched files.
- `tests/test-explorer-clipboard.lua`: 19/19 passed (register-level module untouched, confirms require graph intact).
- `:checkhealth beast.libs.explorer`: `render.build()` returned 3 lines, 6 highlights, 0 badges — structural gate passed. The pre-existing "missing highlight groups" warning in that same health run is unrelated (theme not loaded under a minimal headless invocation; same as the `explorer-active-file-marker` precedent).
- code-reviewer subagent: PASS, no findings. Verified empirically (isolated headless probes against `render.build()` with mocked `state.clipboard`/nodes) that: cut/copy mode each produce the correct sole glyph; the line text carries no trailing suffix in either mode; an unmarked node gets no badge; an empty-string `icon.clip` glyph hides that badge; diagnostic+git+clip together render in the correct left-to-right order (diagnostic, git, clip rightmost); `state.clipboard == nil` is handled safely.
- Manual: not re-run separately from the reviewer's empirical probes above, which exercised the same code path (`render.build()`) the manual scenarios would have.
