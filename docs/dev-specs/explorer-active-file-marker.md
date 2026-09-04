---
name: explorer-active-file-marker
description: Replace the explorer's active-file background tint with a configurable left-gutter marker glyph
generated: 2026-09-04
---

> PM Spec: [docs/pm-specs/explorer-active-file-marker.md](../pm-specs/explorer-active-file-marker.md)

# Summary

Add a `┃`-by-default (configurable) left-gutter marker glyph, spliced into the leading padding column of the active file's row, on top of the existing `BeastExplorerActiveFile` background tint (which stays). The glyph gets its own color from a new `fg`-only `BeastExplorerActiveFile` highlight group; the background tint moves to a new `BeastExplorerActiveFileBg` group so both can be layered on the same row independently.

---

# Context

## Problem
`render.lua` marks the file that's open in the editor by applying a background tint as a `line_hl_group` extmark (`M.write()`, lines 349-354), fed by an `active_line` value threaded out of `M.build()`. This background color sits close enough to `BeastExplorerCursorLine`'s background that the two are hard to tell apart at a glance — a problem re-tuning colors can't fully solve, per the PM spec. The fix adds a shape (a fixed-position glyph) that reads the same regardless of what background is under it, layered on top of the existing background tint rather than replacing it.

### Solution
`render.build()` splices a configurable marker glyph (default `┃`) into the first column of the active file's row — inside the existing padding gutter that every row already reserves via `config.padding` — and attaches a small highlight for just that glyph, appended after the row's base indent highlight so it renders on top. `M.build()` also keeps tracking `active_line` (the row index) so `M.write()` can still apply the background tint via a `line_hl_group` extmark, now using a dedicated `BeastExplorerActiveFileBg` group instead of the glyph's `BeastExplorerActiveFile` group. The marker glyph becomes a new `config.icon.active_file` setting, following the same plain-string/empty-string-hides convention as `config.icon.file`.

---

# Research

### Repo Search
- Searched for: `active_path`, `active_line`, `ActiveFile` across `lua/beast/libs/explorer/`
- Found: `state.active_path` (`state.lua:44-51`) is a live-computed getter (current buffer of `source_win`), not manually tracked — no new state plumbing needed. Its only consumer is `render.lua` (`build()` reads it once, `write()` receives the derived `active_line`). Three callers of `render.build()`/`render.write()` exist: `ui.lua:91-92` (uses all 4 return values), `health.lua:269-271` (already destructures only `lines, hls, badges`, ignoring the 4th — safe to drop), and `scripts/bench-explorer.lua:284-319` (already destructures only 2 values and passes 2 args — also safe to drop, confirmed via a before/after bench run during code review).
- Found reusable pattern: the clipboard `(copy)`/`(cut)` suffix highlight (`render.lua:297-302`) already overlays a highlight on part of an already-highlighted line by appending a later extmark for the same line — the marker's highlight reuses this exact append-order-wins approach instead of inventing a priority scheme.
- Found reusable pattern: `config.icon.dir_open` / `dir_closed` / `file` (`config.lua:14-16`) are the existing plain-string, single-glyph icon settings (vs. the per-status table used for git/diagnostic badges) — the marker is a single on/off glyph, so it follows this pattern, not the table one.
- Reuse opportunity: **Yes** — no new mechanism needed for either the highlight-layering or the config shape; both have a direct existing precedent in this same file.

### Built-in / Existing Lib Check
- Checked: Neovim's sign column (`sign_define`) and the `sign_text` extmark field as an alternative way to render a gutter glyph.
- Found: Not used anywhere in the explorer today — every existing decoration (file/dir icons, git badges, clipboard suffix, tree connectors) is literal buffer text plus a text-highlight extmark, computed once in `render.build()` and written in `render.write()`. Signs would be a second, parallel decoration mechanism sitting outside the prefix builder that every other row-level piece of state (badges, sticky headers) already keys off of.
- Decision: **Build** — extend the existing text-based prefix/highlight pipeline in `render.lua`, consistent with how every other piece of row decoration already works.

---

# Architecture Changes

- `lua/beast/libs/explorer/config.lua` — **Modify.** Add `icon.active_file = "┃"` to `defaults.icon`, alongside `dir_open`/`dir_closed`/`file`. Empty string hides it, matching the git/diagnostic icon convention already documented in this table.
- `lua/beast/libs/explorer/highlights.lua` — **Modify.** Add a new `ActiveFileBg = { bg = Util.colors.lighten(p.dark1, 20) }` group (the original background-tint definition, kept). Redefine `ActiveFile` to an `fg`-only color (`p.accent4`, currently unused in this file, so it doesn't collide with any `Git*` or `Clip` color) for the marker glyph. Update the adjacent comment to describe both groups as layered cues for the same row.
- `lua/beast/libs/explorer/render.lua` — **Modify.**
  - In `M.build()`: for each file node where `node.path == active_path`, splice the configured marker glyph into the first display column of that row's `prefix` (leaving the rest of the `config.padding` gutter, if wider than 1 column, blank so connector alignment doesn't shift), and append a highlight for just the glyph's byte range using the `BeastExplorerActiveFile` group, added right after that row's existing indent highlight so it renders on top (same append-order pattern as the clipboard suffix). Also keep tracking `active_line` (the row index for the active file, independent of whether the marker itself is shown) and return it as a 4th value.
  - In `M.write()`: keep the `active_line` parameter and the `line_hl_group` background-extmark block (lines 349-354), now targeting `BeastExplorerActiveFileBg` instead of `BeastExplorerActiveFile`.
  - If `config.padding == 0`, there's no gutter column to put the marker in — skip the splice for that row (no crash, marker simply doesn't render; this mirrors the existing "depth-0 gets no connector" edge-case comment style already in this file). The background tint still applies regardless of `config.padding`.
- `lua/beast/libs/explorer/ui.lua` — **Modify.** Update the one call site (line 91-92): `local lines, hls, badges, active_line = render.build(nodes)` / `render.write(lines, hls, badges, active_line)`.

## Implementation Phases

## Phase 1: Marker glyph layered on top of the background tint — the whole feature
1. **Add the configurable glyph** (File: `lua/beast/libs/explorer/config.lua`)
   - Action: Add `icon.active_file = "┃"` to `defaults.icon`, next to `dir_open`/`dir_closed`/`file`, with a one-line comment noting empty string hides it (matching the git/diagnostic table's documented convention).
   - Why: Matches PM spec requirement that the glyph be user-configurable the same way other explorer icons are.
   - Depends on: None
   - Risk: Low

2. **Split the highlight group in two** (File: `lua/beast/libs/explorer/highlights.lua`)
   - Action: Add `ActiveFileBg = { bg = Util.colors.lighten(p.dark1, 20) }` (the original row-tint definition, kept as-is); change `ActiveFile` to `{ fg = p.accent4 }` for the marker glyph. Update the preceding comment to describe both as layered cues for the same row.
   - Why: The two cues need independent colors (glyph fg vs. row bg) so they can render together without one clobbering the other.
   - Depends on: None
   - Risk: Low

3. **Splice the marker into the render pipeline** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: In `M.build()`'s node loop, when a file node's path equals `active_path`, override that row's leading gutter cell with `config.icon.active_file` (skip if empty string or `config.padding == 0`), and append a `BeastExplorerActiveFile` highlight for the glyph's column range immediately after the row's indent highlight. Keep tracking `active_line` (independent of whether the marker itself renders) and keep it in the return tuple.
   - Why: This is the core behavior change — the PM spec's `┃` marker.
   - Depends on: Steps 1-2
   - Risk: Medium (byte-vs-column splicing into an already-built prefix string; must preserve connector alignment for `config.padding > 1`)

4. **Retarget the background-extmark write path** (File: `lua/beast/libs/explorer/render.lua`)
   - Action: In `M.write()`, keep the `active_line` parameter and the `if active_line then ... line_hl_group = ... end` block, now pointing at `BeastExplorerActiveFileBg`.
   - Why: The background-tint approach stays, per the PM spec's behavior rules — the marker is additive, not a replacement.
   - Depends on: Step 3
   - Risk: Low

5. **Update the call site** (File: `lua/beast/libs/explorer/ui.lua`)
   - Action: Keep `local lines, hls, badges, active_line = render.build(nodes)` / `render.write(lines, hls, badges, active_line)` (the 4-value form).
   - Why: Keep the only production caller in sync with `build()`/`write()`'s signatures.
   - Depends on: Steps 3-4
   - Risk: Low

(`health.lua`'s call to `render.build()` already destructures only `lines, hls, badges`, ignoring the 4th value — no change needed there, but it's the regression gate for this phase; see Testing Strategy.)

---

# Testing Strategy

- Headless: `nvim --clean --headless -l tests/test-explorer-clipboard.lua` (unrelated, but confirms nothing in the lib's require graph broke) and `NVIM_APPNAME=BeastVim nvim --headless -c "checkhealth beast.explorer" -c "qa"` — this exercises `render.build()` end-to-end (`health.lua:269-283`) and will fail loudly if the new signature or the splice logic raises.
- Manual: Follow the PM spec's 5 scenarios directly in `NVIM_APPNAME=BeastVim nvim`:
  1. Open a file from the explorer → its row shows `┃` at the far left.
  2. Switch to a different open buffer → marker relocates.
  3. Move the cursor around without switching buffers → marker stays put; only `BeastExplorerCursorLine` moves.
  4. Collapse the active file's parent directory → marker disappears; expand it again → marker reappears.
  5. Point the explorer at a non-file buffer → no row shows the marker.
  6. Additionally: set `explorer.setup({ icon = { active_file = "" } })` and confirm the marker fully disables; set it to a different glyph and confirm the swap.
- No new automated test file — consistent with the precedent set by `docs/dev-specs/explorer-highlights-palette.md`, which also relied on manual verification only, since this repo has no existing visual/render assertion tests for `explorer/render.lua`.

# Success Criteria

- [x] The currently open file's row shows `┃` (or the configured glyph) at the far left of the explorer.
- [x] No other row shows the marker.
- [x] The marker relocates correctly when the user switches to a different open file.
- [x] The marker is visually distinguishable from the cursor-line background, including when both land on the same row.
- [x] The active-file background highlight still appears alongside the marker, on the same row.
- [x] `icon.active_file` is configurable via `explorer.setup()`; empty string hides the marker entirely.
- [x] `:checkhealth beast.explorer` still reports a successful `render.build()` call (structural regression gate).
- [x] No regression in existing explorer rendering (icons, git badges, clipboard suffix, sticky headers, indent connectors).

---

## Completed

**2026-09-04** — Phase 1 (the whole feature) implemented, reviewed, and verified in one pass.

- `e8b4407` feat(explorer): mark active file with left-gutter glyph instead of bg tint

Verification:
- `stylua --check` clean on all 4 touched files.
- `tests/test-explorer-clipboard.lua`: 19/19 passed (unrelated lib, confirms require graph intact).
- `:checkhealth beast.libs.explorer`: `render.build()` returned 3 lines, 6 highlights, 0 badges — structural gate passed. The pre-existing "missing highlight groups" warning in that same health run is unrelated (theme not loaded under a minimal headless invocation; it lists every `BeastExplorer*` group, not just this one).
- `scripts/bench-explorer.lua`: ~530µs/render on the "mixed" scenario, matching the pre-existing (unrelated) soft-target breach on both sides of the diff — no perf regression.
- code-reviewer subagent: PASS WITH WARNINGS. Verified the gutter-splice math empirically (padding=1, padding=3, padding=0, empty-glyph) via a standalone harness against a real tree/buffer; caught that `scripts/bench-explorer.lua` was a third caller of `render.build()`/`render.write()` not mentioned in this file's Research section (harmless — already used a 2-value destructure — corrected the Research section text above) and a minor duplicated-guard nit (hoisted into a `show_marker` local in `render.lua`).
- Manual: re-verified directly (not just via the reviewer) with a headless harness driving a real `Tree`/buffer — confirmed the marker glyph is genuinely `┃` (U+2503) byte-for-byte, appears only on the active file's row, preserves connector alignment at `padding=1` and `padding=3`, disappears with `icon.active_file = ""`, and no-ops safely at `padding=0`.

## Revision — 2026-09-05

Reversed course on the "replace, don't layer" decision above: the background tint is restored alongside the marker glyph (Phase 1 steps 2-5 above, and the PM spec's Behavior Rules / Success Criteria, updated to reflect this). `ActiveFile` (fg-only, marker glyph) and `ActiveFileBg` (bg tint, full row) are now two separate highlight groups instead of one being redefined to replace the other.

While re-verifying with a headless harness, also caught and fixed a real bug left over from the original 2026-09-04 implementation: `config.icon.active_file`'s default value was `▎` (U+258E, "left one eighth block") instead of the spec'd `┃` (U+2503, "box drawings heavy vertical") — present in the working tree *and* already committed in `e8b4407`. The prior session's investigation into this exact discrepancy was inconclusive (see git history); this pass confirmed the wrong glyph via direct codepoint inspection and fixed it.

Verification:
- `stylua --check` clean on all touched files.
- `tests/test-explorer-clipboard.lua`: 19/19 passed.
- `:checkhealth beast.libs.explorer`: `render.build()` returned 3 lines, 6 highlights, 0 badges — structural gate passed; no new warnings.
- Manual: headless harness driving a real `Tree`/buffer through both `render.build()` and `render.write()` confirmed the marker glyph (`┃`, U+2503 verified by codepoint) and a `BeastExplorerActiveFileBg` `line_hl_group` extmark both land on the active file's row simultaneously.
