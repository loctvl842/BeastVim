---
name: finder-matcher-performance
description: "Finder Matcher Performance"
generated: 2026-05-17
---

# Dev Spec: Finder Matcher Performance

## Summary

Optimize the finder's matching pipeline for large projects (90k+ files). The current
matcher rescans every item, re-sorts all matches, and re-renders every line on each
keystroke. This spec introduces **subset elimination**, **top-K heap sorting**, and
**virtual list rendering** — the three techniques snacks.nvim uses to stay responsive
at scale. The async coroutine infrastructure (`beast/libs/async.lua`) already exists
and is adequate; the bottleneck is purely in the matcher→sort→render path.

## Requirements

- Typing in a 90k-item file picker must feel instant (< 50ms perceived latency)
- Subset elimination: appending characters to a query must only re-score items
  that matched the previous (shorter) query — items that already failed are skipped
- Top-K heap: never sort the entire matched list; maintain a bounded heap of the
  best N results (N = visible list height, capped at ~1000)
- Virtual rendering: only write visible rows + extmarks to the list buffer, not all
  matched items
- Match highlights (`match_hl.apply_list`) must also be virtual (only visible rows)
- Empty pattern fast-path: when input is cleared, skip matching entirely and show
  items in insertion order
- No regressions: scoring algorithm, pattern syntax, preview, live sources unchanged
- **Out of scope**: frecency scoring, GC pausing, concurrent finder+matcher coroutines,
  min-heap persistence across sessions

## Research

### Repo Search

- Searched for: `topk`, `heap`, `subset`, `virtual`, `visible`
  (`git grep -niE 'topk|heap|subset|virtual|visible' lua/beast/`)
- Found: No existing heap, top-k, or virtual rendering code in BeastVim
- `beast/libs/async.lua` — **Adopt**: already provides `spawn()` + `yielder()` with
  10ms budget `uv.new_check()` executor. The matcher already uses it. No changes needed.
- `beast/libs/finder/matcher.lua:503-525` — the hot path to optimize:
  walks all items, scores each, collects matches, `table.sort` on full list
- `beast/libs/finder/query.lua:214-220` (`rematch`) — calls `matcher.run` with
  `query.items` (all items) on every input change
- `beast/libs/finder/ui/list.lua:50-113` (`render`) — iterates all items, builds all
  lines, sets all extmarks
- `beast/libs/finder/match_hl.lua:66-123` (`apply_list`) — iterates all items for
  highlight positions
- Reuse opportunity: None — these are new data structures

### Package Search

- `vim.api.nvim_win_get_height(win)` — **Use native**: determines visible row count
- `vim.api.nvim_win_call` + `vim.fn.line("w0")` / `vim.fn.line("w$")` — visible range
- No external packages needed; this is pure algorithmic work

### snacks.nvim Reference

Key techniques adopted from `folke/snacks.nvim`:
- **Min-heap top-K** (`snacks/picker/util/minheap.lua`): capacity-bounded binary heap,
  O(log K) insert, keeps only best K items. Display reads from heap, not full list.
- **Subset optimization** (`snacks/picker/core/matcher.lua:183-189`): when new pattern
  is a superset of old (user appended chars, no deletions), items with score=0 from
  previous round are skipped entirely.
- **Virtual list** (`snacks/picker/core/list.lua`): only renders rows visible in the
  window viewport. Uses `topk:get(idx)` for O(1) access.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/topk.lua` | **Create** | Min-heap with bounded capacity for top-K results |
| `lua/beast/libs/finder/matcher.lua` | **Modify** | Subset elimination + top-K integration + empty fast-path |
| `lua/beast/libs/finder/query.lua` | **Modify** | Track previous pattern for subset detection; pass top-K to render |
| `lua/beast/libs/finder/ui/list.lua` | **Modify** | Virtual rendering: only draw visible rows |
| `lua/beast/libs/finder/match_hl.lua` | **Modify** | Only highlight visible rows |

## Implementation Phases

### Phase 1: Top-K Heap + Subset Matcher — [Eliminate full-list sort and redundant scoring]

This is the highest-impact phase. It replaces the two costliest operations:
`table.sort(matched)` → O(N log N) becomes top-K heap insert → O(N log K), and
full rescan → subset-only rescan.

1. **Create `topk.lua`** (File: `lua/beast/libs/finder/topk.lua`)
   - Action: Implement a binary min-heap with bounded capacity.
     API: `TopK.new(capacity, cmp)`, `topk:push(item)`, `topk:sorted()`,
     `topk:get(idx)`, `topk:count()`, `topk:clear()`.
     `push` inserts if heap is under capacity or item beats the current minimum;
     evicts the minimum when at capacity. `sorted()` returns items in descending
     score order (for display).
   - Why: Replaces `table.sort` on all matched items. For 90k items with K=1000,
     this is O(90k × log 1000) ≈ 90k × 10 vs O(N log N) ≈ 90k × 17 — plus we
     avoid building the full matched array at all.
   - Depends on: None
   - Risk: Low — pure data structure, no side effects

2. **Add subset elimination to `matcher.lua`** (File: `lua/beast/libs/finder/matcher.lua`)
   - Action: Change `M.run()` signature to accept `prev_pattern` and `prev_scores`
     (a table mapping item index → previous score). When the new pattern is a
     strict superset of `prev_pattern` (starts with prev_pattern, only appended
     chars, no deletions), skip items where `prev_scores[item.idx] == 0`.
     Also: when pattern is empty, skip matching entirely — call `on_done` with
     items in insertion order (score=1 for all).
   - Why: When user types `fo` → `foo`, items that failed `fo` cannot possibly
     match `foo`. On 90k items where `fo` matches 5k, this skips 85k items.
   - Depends on: Step 1 (uses TopK for collecting results)
   - Risk: Medium — must correctly detect superset (handle backspace, paste, etc.)

3. **Integrate into `query.lua`** (File: `lua/beast/libs/finder/query.lua`)
   - Action: Add `_prev_pattern` and `_prev_scores` fields to Query. In `rematch()`,
     pass these to `matcher.run()`. After matcher completes, store the new pattern
     and score map as `_prev_*` for the next keystroke. On `flush_batch()` for
     non-live sources, invalidate `_prev_scores` (new items arrived, must rescan).
   - Why: Connects the subset optimization to the query lifecycle
   - Depends on: Step 2
   - Risk: Low

### Phase 2: Virtual List Rendering — [Only draw what's visible]

1. **Virtualize `list.lua` render** (File: `lua/beast/libs/finder/ui/list.lua`)
   - Action: Change `M.render()` to only write lines visible in the window viewport.
     Use `vim.api.nvim_win_get_height(view.win)` for the viewport size.
     Store the full sorted items array on the view but only call
     `nvim_buf_set_lines` for the visible slice. Extmarks (highlights, prefix)
     are only set for visible rows. On scroll/cursor-move, re-render the visible
     window.
   - Why: Currently renders all 90k matched lines + 90k×2 extmarks. With virtual
     rendering, this drops to ~40 lines + ~80 extmarks (visible height).
   - Depends on: Phase 1 (matcher provides sorted top-K via `topk:sorted()`)
   - Risk: Medium — must handle cursor movement, scrolling, and window resize
     correctly. The cursor cycling logic (`M.move`) needs to trigger re-render
     when cursor moves outside the visible window.

2. **Virtualize `match_hl.lua`** (File: `lua/beast/libs/finder/match_hl.lua`)
   - Action: Change `M.apply_list()` to accept a visible range `(from, to)` and
     only iterate items within that range. The caller (`query.lua:render()`)
     passes the visible slice.
   - Why: Currently iterates all matched items for highlight extmarks. With 90k
     matches this is O(90k) string operations per keystroke.
   - Depends on: Step 1 (render passes visible range)
   - Risk: Low

## Testing Strategy

- **Bench script**: Create `scripts/bench-finder-matcher.lua` that:
  1. Generates 90k synthetic file paths
  2. Times `matcher.run()` for empty → 1-char → 2-char → 3-char progressive queries
  3. Reports: total time, items scanned, items skipped (subset), heap operations
  4. Target: < 30ms for a 3-char query on 90k items (subset path)
  5. Target: < 80ms for a 1-char query on 90k items (full scan, worst case)

- **Manual verification**:
  1. Open finder on `~/Documents/Work/BeyondSoft/Repo/microsoft-graph-docs` (~90k files)
  2. Type progressively: `a` → `ap` → `api` → backspace → `ap`
  3. Verify: results appear without perceptible lag on each keystroke
  4. Verify: backspace triggers full rescan (not subset), results are correct
  5. Verify: clearing input shows all items instantly
  6. Verify: cursor movement and scrolling render correctly (no blank rows)
  7. Verify: match highlights appear only on visible rows and are correct

## Risks & Mitigations

- **Risk**: Subset detection false-positive (treats a non-superset as superset, skips items
  that should match) → **Mitigation**: Superset check is simple string prefix comparison
  on the raw pattern. Any edit that isn't pure append (backspace, cursor move, paste over)
  invalidates `_prev_scores` and triggers full rescan. Conservative by default.

- **Risk**: Virtual rendering introduces visual glitches on fast scrolling →
  **Mitigation**: Re-render on every cursor move that crosses the visible boundary.
  Use `nvim_buf_set_lines` for the full visible slice (not incremental patches) to
  avoid stale line artifacts.

- **Risk**: Top-K heap capacity too small misses relevant results when user scrolls
  past K → **Mitigation**: Default capacity = `max(1000, 2 × window_height)`. For
  scrolling beyond top-K, fall back to the full matched list (which the heap also
  tracks as a count). In practice, users rarely scroll past 1000 results.

## Success Criteria

- [ ] `scripts/bench-finder-matcher.lua` reports < 50ms for subset query on 90k items
- [ ] `scripts/bench-finder-matcher.lua` reports < 80ms for full-scan query on 90k items
- [ ] No perceptible lag when typing in finder on 90k-file project
- [ ] Backspace / clear input produces correct results (no stale subset cache)
- [ ] Cursor movement and scrolling show correct content (no blank/stale rows)
- [ ] Match highlights appear only on visible rows and are positionally correct
- [ ] Existing pattern syntax (!, ^, $, ', |) works identically
- [ ] Live sources (grep) unaffected — they bypass the matcher
- [ ] Codemap regenerated and committed alongside
