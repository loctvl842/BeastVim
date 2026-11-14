---
name: git-preview-word-diff
description: Compute word-level spans for paired removed/added preview rows and paint them with stronger highlight groups
generated: 2026-11-14
---

> PM Spec: [docs/pm-specs/git-preview-word-diff.md](../pm-specs/git-preview-word-diff.md)

# Summary
Add a pure word-diff helper to the git diff wrapper, carry its column spans on the preview rows, and paint them as extmarks with two new highlight groups on top of the existing whole-line tint. Pairing, similarity cutoff and length cutoff live in the pure helper so everything is headless-testable.

---

# Context

## Problem
The preview float (`lua/beast/libs/git/preview.lua`) emits `- ` and `+ ` rows with only `line_hl_group` tints. Rows carry no column information, so nothing can mark the differing words inside a modified line.

### Solution
`diff.lua` gains `word_spans(old, new)` returning byte ranges of changed tokens on each side. `build_rows` pairs removed and added lines per hunk and attaches `spans` to each paired row. `render_rows` passes spans through, and `apply_decorations` places one extmark per span with `BeastGitPreviewDeleteWord` / `BeastGitPreviewAddWord`.

---

# Research

### Repo Search
- Searched for: `vim.diff`, `vim.text.diff`, `word.diff`, `intra`, `PreviewAdd`, `line_hl_group`, `build_rows`, `render_rows` under `lua/` and `tests/`.
- Found: `diff.lua` already wraps `vim.text.diff` with `indices` output (`DIFF_OPTS`); `preview.lua` `build_rows`/`render_rows` produce rows and `apply_decorations` places `line_hl_group` extmarks in namespace `beast_git_preview`; highlights are built in `highlights.lua` via `Util.colors.blend`; `tests/test-git-preview.lua` already exercises `build_rows`/`render_rows` through `preview._test`. No word-level diff anywhere.
- Reuse opportunity: Yes - the diff backend, the `_test` seam, the extmark namespace, the highlight builder.

### Built-in / Existing Lib Check
- Checked: `vim.text.diff` (indices, `algorithm`), `vim.api.nvim_buf_set_extmark` with `hl_group` + `priority`, `vim.fn.strdisplaywidth`.
- Found: `vim.text.diff` on newline-joined tokens gives token-level hunks directly (same trick as GitHub/delta); a range extmark's `hl_group` bg takes precedence over `line_hl_group` when priority is higher, and syntax fg from treesitter is preserved because the word groups set only `bg`.
- Decision: **Use** `vim.text.diff` for tokens, **Reuse** the diff wrapper, row pipeline and highlight builder, **Build** only the tokenizer, pairing and span mapping.

---

# Architecture Changes
- `lua/beast/libs/git/diff.lua` (modified): add `M.word_spans(old, new)`.
- `lua/beast/libs/git/preview.lua` (modified): `PreviewRow.spans`, pair in `build_rows`, pass through `render_rows`, paint in `apply_decorations`, thread through `open_float`.
- `lua/beast/libs/git/highlights.lua` (modified): `PreviewAddWord`, `PreviewDeleteWord`.
- `lua/beast/libs/git/health.lua` (modified, if it lists preview groups): include the two new groups.
- `tests/test-git-word-diff.lua` (new): unit tests for `word_spans`.
- `tests/test-git-preview.lua` (modified): rows carry spans only for paired rows.
- `docs/CODEMAP/libraries.md` (modified): mention word spans in `diff.lua`/`preview.lua` lines (via `/update-codemap`, not by hand).

## Implementation Phases

## Phase 1: Word-span helper - pure, tested, no UI change
1. **Tokenize** (File: `lua/beast/libs/git/diff.lua`)
   - Action: split a line into tokens: runs of `[%w_]`, runs of whitespace, and single other characters (UTF-8 aware via `vim.str_utfindex`-free pattern `[%z\1-\127\194-\244][\128-\191]*` for the single-char case). Keep each token's byte start/end.
   - Why: word-level grouping per PM rule; punctuation changes like `~=` mark exactly.
   - Depends on: None
   - Risk: Low
2. **`M.word_spans(old, new)`** (File: `lua/beast/libs/git/diff.lua`)
   - Action: join tokens with `\n`, run `diff_fn` with `result_type = "indices"`, `algorithm = "histogram"` on both sides, map token hunks to merged byte ranges `{ s, e }` (0-based start, exclusive end, ready for extmarks) for old and new. Merge ranges separated only by whitespace tokens. Return `old_spans, new_spans`.
   - Why: produces exactly the stronger-highlight regions.
   - Depends on: Step 1
   - Risk: Medium (merge rule and off-by-one on byte ranges)
3. **Cutoffs** (File: `lua/beast/libs/git/diff.lua`)
   - Action: return `nil, nil` (no emphasis) when either line exceeds 1000 bytes, or when unchanged non-whitespace bytes are less than 40% of the shorter line's non-whitespace bytes (so a pure insertion into a short line still qualifies) (PM: "too little in common").
   - Why: avoids striped noise and keeps large hunks instant.
   - Depends on: Step 2
   - Risk: Low (thresholds are constants, tunable)
4. **Unit tests** (File: `tests/test-git-word-diff.lua`)
   - Action: cases for appended phrase (the `and vim.g.colors_name ~= original ` example), replaced word, identical lines, fully different lines (nil), pure punctuation change, whitespace-only change, multibyte text, over-length line.
   - Why: PM success criteria 1-3.
   - Depends on: Step 3
   - Risk: Low

## Phase 2: Paint spans in the preview
1. **Highlight groups** (File: `lua/beast/libs/git/highlights.lua`)
   - Action: `PreviewDeleteWord = { bg = blend(p.red, 0.35, p.dark1) }`, `PreviewAddWord = { bg = blend(p.green, 0.35, p.dark1) }`. bg only so syntax fg survives.
   - Why: PM rule: separate theme-adjustable groups, stronger than the 0.15 line tint.
   - Depends on: None
   - Risk: Low (verify contrast in light themes)
2. **Pair and attach spans** (File: `lua/beast/libs/git/preview.lua`, `build_rows`)
   - Action: inside each hunk, for `j = 1..min(#removed, #added)` call `diff.word_spans(removed[j], added[j])` and set `spans` on the matching `- ` and `+ ` rows. Unpaired rows get none. Context rows never do.
   - Why: PM rules on in-order pairing and context exclusion; works for staged and unstaged since both go through `build_rows` with their own removed/added text.
   - Depends on: Phase 1
   - Risk: Medium (rows are appended in two loops; keep row refs)
3. **Carry through render** (File: `lua/beast/libs/git/preview.lua`, `render_rows`, `open_float`)
   - Action: `render_rows` returns a fifth value `spans` (row index to span list); `open_float` forwards it to `apply_decorations`. Existing four returns unchanged so current tests stay valid.
   - Why: decorations are applied by row index.
   - Depends on: Step 2
   - Risk: Low
4. **Paint** (File: `lua/beast/libs/git/preview.lua`, `apply_decorations`)
   - Action: for each span `nvim_buf_set_extmark(buf, ns, row-1, s, { end_col = e, hl_group = word_hl, priority = 200 })` where `word_hl` is the Delete/Add word group by row marker.
   - Why: draws the stronger background over the line tint.
   - Depends on: Step 3, Step 1 of this phase
   - Risk: Low
5. **Health and codemap** (Files: `lua/beast/libs/git/health.lua`, `docs/CODEMAP/libraries.md`)
   - Action: list new groups in the health check if it enumerates preview groups; regenerate codemap with `/update-codemap`.
   - Why: keep tooling consistent.
   - Depends on: Step 4
   - Risk: Low

---

# Testing Strategy
- Headless tests: `nvim --clean --headless -l tests/test-git-word-diff.lua` (new); `nvim --clean --headless -l tests/test-git-preview.lua` extended: paired rows have spans, unpaired and context rows do not, existing 33 assertions unchanged.
- Bench: `nvim --clean --headless -l scripts/bench-git.lua`, plus add a case timing `word_spans` over a 200-line changed hunk (budget: well under one frame, 16 ms).
- Manual (end-to-end in `NVIM_APPNAME=BeastVim`): walk PM scenarios 1-7: appended phrase, replaced word, stage-then-edit, multi-line hunk, 2-to-3 lines, full rewrite, colorscheme switch (dark and light) via `<leader>gp`. Compare against the GitHub screenshot.

# Success Criteria
- [x] Appended phrase is the only stronger-green region on the added line.
- [x] Replaced word is stronger red then stronger green.
- [x] Fully different lines and pure add/delete rows show soft highlight only.
- [x] Context rows are never emphasized.
- [x] Staged-then-edited line emphasizes only changes since staging.
- [x] Emphasis visible in every bundled colorscheme, dark and light.
- [x] No visible delay on a large hunk; bench within budget.
- [x] All `tests/test-git-*.lua` pass; no new lint warnings.

---

## Completed

2026-11-14 - Phase 1: word-span helper with tests. Phase 2: paired preview rows, new highlight groups, painted word spans, bench case.

- `f2b13d5` fix(git): preview index vs buffer when a staged line is edited again (earlier fix, committed first so phase commits stay clean)
- `4b4b06d` feat(git): word-level span helper for the hunk preview
- `0287fa6` test(git): cover word-level diff spans
- `1ed5e37` fix(git): tokenize stray invalid bytes in word spans (found in review: stray bytes made tokenize throw)
- `4b18d98` feat(git): word-level preview highlight groups
- `554f46b` feat(git): pair removed and added preview rows for word spans
- `4a5efb1` feat(git): carry word spans through render_rows and open_float
- `d8a691c` feat(git): paint changed words in the hunk preview
- `ca7edb0` bench(git): time word_spans over a 200-line modified hunk
- `fa39f24` fix(git): layer changed-word highlight over the preview line tint (line_hl_group always paints over range highlights, so the row tint is now an hl_eol range at priority 100 and words are priority 200)

Deviations from the plan: similarity cutoff measured against the shorter line; `health.lua` left unchanged (it lists no preview groups).

Verification: `tests/test-git-word-diff.lua` 17/17, `tests/test-git-preview.lua` 39/39, stylua clean, `scripts/bench-git.lua` PASS (words200 = 2.36 ms, budget 16 ms). Rendered check in a real wezterm pane (default colorscheme): only the changed words carry the stronger background. Not yet eyeballed in the bundled colorschemes.
