# Dev Spec: Finder Files Pipeline — Stdout Processing & Scoring Overhaul

## Summary

Overhaul the `files` source stdout processing and the fuzzy scoring engine to match
snacks.nvim's performance characteristics. The current pipeline has three bottlenecks:
(1) `vim.schedule` per stdout chunk creates hundreds of closures during streaming,
(2) the finder and matcher run sequentially (items batch → flush → full rematch),
(3) the scoring engine uses a single-window scan that can miss better match positions.

This spec adopts snacks.nvim's three core innovations: **queue-based coroutine stdout
processing** (zero `vim.schedule`), **concurrent finder+matcher coroutines** (results
appear while items stream), and a **multi-start fuzzy scan with bonus matrix scoring**
(better match quality). These changes target the `files` source only; `live_grep` is
out of scope.

## Requirements

- File source (`source/files.lua`) must not call `vim.schedule` per stdout chunk
- Finder and matcher must run as concurrent coroutines — matcher processes items
  as they arrive, not after batch-flush
- Users see top results within ~10ms of first stdout data (incremental display)
- Scoring must try multiple match start positions and keep the best score
- Scoring must use a pre-computed bonus matrix (7 char classes) instead of branch chains
- Scoring must add a filename bonus when match is in the filename portion (no `/` after match)
- First matched character gets 2× its boundary bonus (BONUS_FIRST_CHAR_MULTIPLIER)
- Consecutive chunk tracking: if a mid-run char has a higher boundary bonus than what
  started the chunk, upgrade the entire chunk's bonus
- GC paused during finder+matcher cycle for the `files` source
- Entropy-based AND-group ordering: most-selective term evaluated first for multi-term queries
- `--color never` added to fd/rg commands; `--type l` added to fd for symlinks
- No regressions: existing pattern syntax, preview, live sources, keymaps unchanged
- **Out of scope**: frecency/cwd bonus (separate spec), live_grep changes, UI/layout changes

## Research

### Repo Search

- Searched for: `vim.schedule`, `queue`, `coroutine`, `bonus_matrix`, `entropy`
  (`git grep -niE 'vim\.schedule|queue|bonus_matrix|entropy' lua/beast/libs/finder/`)
- Found:
  - `source/files.lua:110,152-157` — `vim.schedule(function() cb(item) end)` per batch
  - `query.lua:309-321` — load path: items batch in `_batch_pending`, flush at 100 items
  - `query.lua:274-291` — `flush_batch()` nulls `_match_state` and calls `rematch()`
  - `matcher.lua:360-427` — scoring uses inline branch chain, no matrix
  - `matcher.lua:278-345` — single forward+backward scan (one window)
  - `async.lua` — existing coroutine executor with 10ms budget `uv.new_check()`
  - `topk.lua` — existing min-heap (from finder-matcher-performance spec)
- Reuse opportunity:
  - **Adopt** `async.lua` — coroutine executor already exists, perfect for concurrent tasks
  - **Adopt** `topk.lua` — already integrated in matcher, will be used by incremental pipeline
  - **Build** queue module, bonus matrix, multi-start scan, entropy sorting

### Package Search

- `vim.uv.new_pipe()` — **Use native**: already used for stdout, no change needed
- `string.byte()` pre-computed char class table — **Use native**: pure Lua, no deps
- No external packages needed

### snacks.nvim Reference (detailed comparison)

#### Stdout Processing

| Aspect | BeastVim (current) | snacks.nvim | Why snacks is faster |
|--------|-------------------|-------------|---------------------|
| Read callback | Parse lines + `vim.schedule(cb)` | `queue:push(raw_data)` + `resume()` | Zero closures, zero event-queue pressure |
| Queue structure | None (raw `_batch_pending` table) | Ring buffer with first/last pointers | O(1) push/pop, no `table.remove(1)` |
| Line parsing | In libuv callback thread | In coroutine (main thread) | Coroutine can yield; callback can't |
| Item delivery | `cb(item)` inside scheduled closure | `cb({text=line})` in async coroutine | No vim.schedule overhead |
| When matcher starts | After 100 items flush | After first item arrives | User sees results immediately |
| GC during streaming | Running (files source) | `collectgarbage("stop")` | No GC pauses in hot loop |

For a 50k-file repo producing ~500 stdout chunks:
- BeastVim: 500 `vim.schedule` calls, ~5 `flush_batch` → full `rematch` cycles
- snacks: 0 `vim.schedule`, finder coroutine + matcher coroutine interleave in same check tick

#### Scoring Engine

| Aspect | BeastVim (current) | snacks.nvim | Why snacks is better |
|--------|-------------------|-------------|---------------------|
| Fuzzy scan | Forward + backward (1 window) | Multi-start: every start position tried | Finds globally-best window |
| Char classification | `BOUNDARY_CHARS` table + if/elseif chain | 7-class `CHAR_CLASS[byte]` + 7×7 `bonus_matrix` | 1 table lookup vs 3-4 branches per char |
| First-char bonus | Flat `BONUS_FIRST_CHAR = 16` | `bonus × BONUS_FIRST_CHAR_MULTIPLIER (2)` | Boundary-aware: `^` on a word start gets 20, on mid-word gets 0 |
| Consecutive tracking | Flat `BONUS_CONSECUTIVE = 4` | `max(bonus, first_bonus, CONSECUTIVE)` | Rewards continuing a strong boundary |
| Filename bonus | None | `+6` when no path separator after match | Filename matches rank above directory matches |
| AND-group ordering | Left-to-right (input order) | Sorted by entropy (most selective first) | Faster rejection of non-matching items |

**Multi-start scan example**: Query `ml` in `my_module_list.lua`:
- Current (single window): `m`@1, `l`@11 → gap=9, score ≈ 32 - 3 - 8 = 21
- Multi-start: also tries `m`@4 (`module`), `l`@11 (boundary `_l`) → gap=6, boundary bonus, score ≈ 32 + 8 - 3 - 4 = 33
- Best window wins → better ranking

**Entropy ordering example**: Query `init config` on 50k items:
- `config` (length=6, less common) has higher entropy than `init` (length=4, very common)
- Checking `config` first rejects ~90% of items before `init` is ever evaluated

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/queue.lua` | **Create** | O(1) ring buffer queue for stdout chunks |
| `lua/beast/libs/finder/score.lua` | **Create** | Stateful scorer with bonus matrix (port of fzf algo.go via snacks) |
| `lua/beast/libs/finder/source/files.lua` | **Modify** | Queue-based stdout, add `--color never`, `--type l` |
| `lua/beast/libs/finder/matcher.lua` | **Modify** | Multi-start scan, entropy ordering, use new score module |
| `lua/beast/libs/finder/query.lua` | **Modify** | Concurrent finder+matcher coroutines, GC pausing |
| `lua/beast/libs/async.lua` | **Modify** | Add `suspend()`/`resume()` support for inter-coroutine signaling |

## Implementation Phases

### Phase 1: Score Module + Multi-Start Fuzzy — [Better match quality]

Isolated scoring improvement. No pipeline changes. Drop-in replacement for the inline
scoring in `matcher.lua`. Can be merged independently.

1. **Create `score.lua`** (File: `lua/beast/libs/finder/score.lua`)
   - Action: Port snacks.nvim's `score.lua` approach — pre-computed 7×7 bonus matrix,
     `CHAR_CLASS[byte]` lookup table for all 256 bytes, stateful `init(str, first)` +
     `update(pos)` + `get(str, from, to)` API. Include:
     - `BONUS_FIRST_CHAR_MULTIPLIER = 2` (doubles first-char bonus)
     - `BONUS_NO_PATH_SEP = 6` (no `/` after match start → filename match)
     - Consecutive chunk tracking with `first_bonus` upgrade logic
   - Why: Replaces 3-4 branches per character with 1 table lookup. Handles more
     transition cases (delimiter vs whitespace, number boundaries). Filename bonus
     improves practical ranking.
   - Depends on: None
   - Risk: Low — pure function, no side effects, easy to test in isolation

2. **Add multi-start fuzzy scan to `matcher.lua`** (File: `lua/beast/libs/finder/matcher.lua`)
   - Action: Replace the single forward+backward scan in `score_term()` fuzzy path with
     a loop that tries every valid start position and keeps the best score. Use the new
     `score.lua` module for scoring each window. Keep the forward scan as a quick
     existence check; only run multi-start if forward scan succeeds.
   - Why: Current single-window approach misses better match positions (see example above).
     The O(n²) worst case is bounded by short queries (typically 1-5 chars) on short
     strings (paths ~50 chars), making it negligible in practice.
   - Depends on: Step 1
   - Risk: Low — behavioral change is strictly better ranking, not different filtering

3. **Add entropy-based AND-group ordering** (File: `lua/beast/libs/finder/matcher.lua`)
   - Action: In `parse_pattern()`, compute an entropy score for each term:
     `entropy = min(#pattern, 20) + rare_chars*2 + case_bonus + mode_bonus`
     (exact_prefix/suffix: +20, exact: +10, non-fuzzy: +10, case-sensitive: ×2).
     Sort AND-groups by highest-entropy-first before returning.
   - Why: Most-selective term evaluated first → non-matching items rejected faster.
     For 2-3 term queries on 50k+ items, this can skip 30-50% of scoring work.
   - Depends on: None (independent of steps 1-2)
   - Risk: Low — only changes evaluation order, not results

### Phase 2: Queue + Concurrent Pipeline — [Faster time-to-first-result]

Replaces the batch-flush sequential model with concurrent coroutines. This is the
high-impact pipeline change.

1. **Create `queue.lua`** (File: `lua/beast/libs/finder/queue.lua`)
   - Action: Implement a ring buffer queue with `push(data)`, `pop()`, `empty()`,
     `clear()`, `size()`. Use first/last index pointers (no `table.remove`).
     Identical to snacks' `util/queue.lua` pattern.
   - Why: The stdout read callback needs to enqueue raw data without allocation.
     A ring buffer is O(1) for both push and pop with no table shifting.
   - Depends on: None
   - Risk: Low — trivial data structure

2. **Add suspend/resume to `async.lua`** (File: `lua/beast/libs/async.lua`)
   - Action: Extend the existing coroutine executor to support `suspend(co)` and
     `resume(co)`. A suspended coroutine is removed from the active set and only
     re-added when `resume()` is called. This enables the matcher to sleep until
     the finder produces new items.
     Also add an `on_done` callback registration (`.on("done", fn)`) so the finder
     can signal completion.
   - Why: Currently `async.spawn()` round-robins all coroutines every check tick.
     The matcher has nothing to do while the finder is parsing — it should suspend
     and wake only when items arrive.
   - Depends on: None
   - Risk: Medium — touches shared module used by existing matcher. Must not break
     the existing `spawn()` + `yielder()` contract.

3. **Rewrite `source/files.lua` stdout processing** (File: `lua/beast/libs/finder/source/files.lua`)
   - Action:
     - Add `--color never` to fd and rg args; add `--type l` to fd args
     - Replace `vim.schedule` batching with queue-based approach:
       - `read_start` callback: `queue:push(data)` + `resume(finder_co)`
       - Source returns an async function (not calling `cb` from libuv callback)
       - The async function runs as a coroutine: loop `queue:pop()` → parse lines
         → `cb(item)` → `yield()` until queue empty + handle closed → suspend
     - The source no longer calls `vim.schedule` at all
   - Why: Eliminates 500+ `vim.schedule` closures per file-find. Items are produced
     in a coroutine context where yielding is safe, enabling the matcher to interleave.
   - Depends on: Steps 1, 2
   - Risk: Medium — changes the source contract from "cb in vim.schedule" to "cb in
     coroutine context". Must verify all downstream consumers handle this.

4. **Wire concurrent finder+matcher in `query.lua`** (File: `lua/beast/libs/finder/query.lua`)
   - Action:
     - For async (non-live) sources, replace the `_batch_pending` / `flush_batch` model:
       - Spawn a **finder coroutine**: runs the source's async function, produces items
         into `query.items[]`, calls `resume(matcher_co)` after each item
       - Spawn a **matcher coroutine**: loops over `query.items`, scores each item,
         inserts into TopK, yields periodically. When all current items processed and
         finder still running → `suspend()`. Wakes when finder adds items.
       - On finder completion: matcher finishes remaining items → final render
     - Add `collectgarbage("stop")` at finder start, `collectgarbage("restart")` on
       completion (in `.on("done")` callback)
     - Incremental rendering: after matcher processes a batch of items (e.g. every 1ms
       yield), if TopK changed the visible set, trigger `render()`
   - Why: User sees results appearing while items stream in. No waiting for 100-item
     batch flush. GC pause eliminates ~10-20ms of GC stalls during hot loop.
   - Depends on: Steps 2, 3 (needs suspend/resume and coroutine-based source)
   - Risk: High — largest behavioral change. Must handle:
     - Abort (user types while streaming → kill finder, restart both)
     - Query change while streaming → abort current finder+matcher, restart
     - Source completion signaling
     - Thread safety (all in main thread via check, but ordering matters)

### Phase 3: Command Improvements — [Better file discovery]

Minimal changes to the fd/rg command arguments. Can land independently of Phase 1-2.

1. **Add `--color never` and `--type l`** (File: `lua/beast/libs/finder/source/files.lua`)
   - Action: In `ensure_cmd()`:
     - fd: add `"--type", "l"` (symlinks) and `"--color", "never"`
     - rg: add `"--no-messages"` and `"--color", "never"`
   - Why: Prevents ANSI escape codes from polluting item text if user's shell config
     forces color. `--type l` ensures symlinked files are discoverable. `--no-messages`
     suppresses rg permission errors that would appear as garbage items.
   - Depends on: None
   - Risk: Low — additive flags, no behavioral change to filtering

## Testing Strategy

- **Bench script**: Update `scripts/bench-finder-matcher.lua` to add:
  1. Scoring comparison: old `score_term()` vs new `score.lua` on 10k paths × 5 queries
  2. Pipeline timing: time from `source.get()` call to first item scored by matcher
  3. Target: first-result latency < 15ms (current: ~100ms due to batch flush delay)
  4. Target: multi-start scoring < 2× single-scan time for 3-char queries

- **Manual verification**:
  1. Open finder on large repo (~50k+ files)
  2. Observe: results appear within ~100ms of opening (streaming), not after full scan
  3. Type progressively: verify ranking quality (filename matches above dir matches)
  4. Type `init config` → verify `config` checked first doesn't change result set
  5. Verify: no ANSI escape codes in file names
  6. Verify: symlinked files appear in results
  7. Verify: no rg permission-error noise in results
  8. Compare ranking of `ml` in `my_module_list.lua` (should prefer consecutive match)

## Risks & Mitigations

- **Risk**: Multi-start scan degrades performance for long queries on long paths
  → **Mitigation**: Cap at 10 start positions max. For queries > 5 chars, the first
  valid start position is usually good enough — add early-exit when score can't beat
  current best (branch-and-bound).

- **Risk**: `async.lua` suspend/resume changes break existing matcher coroutine
  → **Mitigation**: Suspend/resume is additive — existing `spawn()` + `yielder()`
  contract is unchanged. Suspended coroutines simply don't get stepped. Add a
  `_suspended` flag check in `step()`.

- **Risk**: Queue-based source changes the `cb` calling context (coroutine vs scheduled)
  → **Mitigation**: The `cb` in `query.lua:load()` only does `items[#items+1] = item`.
  This is safe in any context. The concern is only if downstream code assumes
  `vim.api.*` is callable (it is in coroutines running via `uv.new_check`).

- **Risk**: `collectgarbage("stop")` during streaming causes memory pressure on very
  large repos (100k+ files)
  → **Mitigation**: Restart GC on completion (or abort). The streaming phase is
  typically < 2 seconds. Memory growth during that window is bounded by item count
  × ~200 bytes/item ≈ 20MB for 100k files — acceptable.

- **Risk**: Concurrent coroutines make debugging harder (interleaved execution)
  → **Mitigation**: Both coroutines yield via the same `uv.new_check` executor with
  a 10ms budget. Execution is deterministic within a tick. Add debug logging behind
  a `config.debug` flag.

## Success Criteria

- [ ] `scripts/bench-finder-matcher.lua` shows < 15ms first-result latency (files source)
- [ ] Multi-start scoring ranks filename matches above directory-prefix matches
- [ ] No `vim.schedule` calls in `source/files.lua` stdout path
- [ ] Finder and matcher run as concurrent coroutines (verified via debug log)
- [ ] GC paused during files source streaming
- [ ] `fd` includes `--type l --color never`; `rg` includes `--color never --no-messages`
- [ ] No ANSI escape codes in item text (test with `CLICOLOR_FORCE=1`)
- [ ] Symlinked files appear in results
- [ ] Existing pattern syntax (!, ^, $, ', |) works identically
- [ ] Subset elimination still works (from previous spec)
- [ ] Live sources (grep) unaffected
- [ ] No perceptible lag when typing in finder on 50k+ file project
- [ ] Codemap regenerated and committed alongside

## ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs once committed:

- **Concurrent coroutine pipeline for async sources**: Changes the source contract from
  "call cb inside vim.schedule" to "call cb inside a coroutine managed by async.lua".
  This affects how future sources are written.
- **Shared `async.lua` gains suspend/resume**: The shared async module grows a new
  capability that other libs could use. This is a shared-module change per AGENTS.md
  § *Shared Modules Registry*.
