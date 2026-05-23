# Finder Pipeline Overhaul — Technical Document

**Date**: 2026-05-21
**Scope**: `lua/beast/libs/finder/` — scoring, matching, stdout processing, async execution
**Reference**: Improvements derived from analyzing `snacks.nvim` picker architecture

---

## Table of Contents

1. [Summary of Changes](#summary-of-changes)
2. [New Module: score.lua](#new-module-scorelua)
3. [New Module: queue.lua](#new-module-queuelua)
4. [Rewritten: matcher.lua](#rewritten-matcherlua)
5. [Modified: topk.lua](#modified-topklua)
6. [Rewritten: source/files.lua](#rewritten-sourcefileslua)
7. [Extended: async.lua](#extended-asynclua)
8. [Modified: query.lua](#modified-querylua)
9. [Performance Results](#performance-results)
10. [Before vs After Comparison](#before-vs-after-comparison)

---

## Summary of Changes

| File | Change Type | Purpose |
|------|-------------|---------|
| `score.lua` | **New** | Stateful fzf-compatible scoring engine with bonus matrix |
| `queue.lua` | **New** | O(1) ring buffer for stdout chunk accumulation |
| `matcher.lua` | **Rewritten** | Multi-start fuzzy, entropy ordering, progressive rendering |
| `topk.lua` | **Modified** | Text-length tiebreaker for equal-score items |
| `source/files.lua` | **Rewritten** | Queue-based stdout with polling loop |
| `async.lua` | **Extended** | Task handles with suspend/resume/abort |
| `query.lua` | **Modified** | Abort-on-rematch, concurrent coroutines |

---

## New Module: score.lua

**Path**: `lua/beast/libs/finder/score.lua`
**Purpose**: Stateful scorer that produces fzf-compatible scores for fuzzy matches.

### Why

The previous matcher had inline scoring logic with basic heuristics. This was:
- Hard to tune (scoring constants scattered across the matching function)
- Missing important bonuses (camelCase, path separators, consecutive runs)
- Not competitive with fzf/snacks quality

### Architecture

The scorer is a **stateful object** that tracks the previous character class and
consecutive match count. You call `init(str, first)` to start scoring a new
haystack, then `update(pos)` for each subsequent matched position. The scorer
handles gap penalties, boundary bonuses, and consecutive bonuses internally.

### Character Classes (7 total)

```
CHAR_WHITE     = 0   (space, tab, newline)
CHAR_NONWORD   = 1   (symbols: @#$%^&* etc.)
CHAR_DELIMITER = 2   (path/word separators: / \ - _ . :)
CHAR_LOWER     = 3   (a-z)
CHAR_UPPER     = 4   (A-Z)
CHAR_LETTER    = 5   (unicode letters beyond ASCII)
CHAR_NUMBER    = 6   (0-9)
```

### Bonus Matrix (7×7 pre-computed)

The bonus for matching a character depends on the **previous** character's class
and the **current** character's class. This is pre-computed into a 7×7 Lua table
at module load time, eliminating branch chains in the hot scoring path.

Key bonus values:
- `SCORE_MATCH = 16` — base score per matched character
- `BONUS_BOUNDARY = 8` — transition from non-letter to letter
- `BONUS_BOUNDARY_WHITE = 10` — transition from whitespace (strongest boundary)
- `BONUS_BOUNDARY_DELIMITER = 9` — transition from delimiter (/ - _ .)
- `BONUS_CAMEL_123 = 7` — camelCase transition (lower→upper) or letter→number
- `BONUS_CONSECUTIVE = 4` — continuing a consecutive run
- `BONUS_NO_PATH_SEP = 6` — match starts in filename portion (no `/` after)
- `BONUS_FIRST_CHAR_MULTIPLIER = 2` — first matched char bonus doubled

Gap penalties:
- `SCORE_GAP_START = -3` — opening a gap
- `SCORE_GAP_EXTENSION = -1` — each additional gap character

### Filename Bonus Logic

```lua
if self.is_file and not str:find("/", first + 1, true) then
    self.score = self.score + BONUS_NO_PATH_SEP
end
```

When `is_file = true` (always true for file sources), the scorer checks if
there's a path separator **after** the match start position. If not, the match
is in the filename portion and gets +6. This means:

- Query `get` matching in `src/utils/get-data.lua` → match starts at `get-data`,
  no `/` after → gets filename bonus
- Query `src` matching in `src/utils/get-data.lua` → match starts at `src`,
  there IS a `/` after → no filename bonus

### Consecutive Chunk Tracking

When characters match consecutively (no gap), the scorer tracks the "chunk":
- First char of chunk: stores boundary bonus as `first_bonus`
- Subsequent chars: takes `max(current_bonus, first_bonus, BONUS_CONSECUTIVE)`
- If a stronger boundary appears mid-chunk, upgrades `first_bonus`

This means matching `get` in `get-data` scores higher than matching `g...e...t`
spread across the string.

### API

```lua
local Score = require("beast.libs.finder.score")
local scorer = Score:new()

-- Score a single match window
scorer:init(haystack_original_case, first_matched_pos)
scorer:update(second_matched_pos)
scorer:update(third_matched_pos)
local score = scorer.score

-- Score a contiguous range (used for exact/prefix/suffix matches)
local score = scorer:get(str, from_pos, to_pos)
```

---

## New Module: queue.lua

**Path**: `lua/beast/libs/finder/queue.lua`
**Purpose**: O(1) ring buffer queue for accumulating stdout chunks.

### Why

The previous `files.lua` called `vim.schedule()` on every stdout chunk from
the subprocess. Each `vim.schedule` has overhead (~0.1ms) and creates many
tiny scheduled callbacks. With large repos (90k+ files), this meant thousands
of scheduled callbacks competing for event loop time.

### Implementation

Simple first/last pointer queue with O(1) push and pop:

```lua
function M:push(val)
    self._last = self._last + 1
    self._data[self._last] = val
end

function M:pop()
    if self._first > self._last then return nil end
    local val = self._data[self._first]
    self._data[self._first] = nil  -- allow GC
    self._first = self._first + 1
    return val
end
```

The stdout callback pushes raw string chunks into the queue (runs in libuv
thread context). A single polling loop drains the queue periodically.

---

## Rewritten: matcher.lua

**Path**: `lua/beast/libs/finder/matcher.lua`
**Changes**: Multi-start fuzzy scan, entropy ordering, progressive rendering, returns Task

### 1. Multi-Start Fuzzy Scan

**Before**: Single forward scan from the first occurrence of the first character.
**After**: Try up to 10 different start positions, keep the highest score.

```lua
local from, to = fuzzy_find(hay, needle, 1)
local best_score = scorer.score
local attempts = 1
local next_from, next_to = fuzzy_find(hay, needle, from + 1)
while next_from and attempts < 10 do
    -- score this window, keep if better
    next_from, next_to = fuzzy_find(hay, needle, next_from + 1)
end
```

**Why**: A single forward scan can produce suboptimal matches. Example:
- Haystack: `abcXabc`
- Needle: `abc`
- Forward scan matches positions 1,2,3 (in `abcX...`) — score includes gap to nothing
- Multi-start also tries positions 5,6,7 (in `...Xabc`) — may score higher due to
  boundary bonus after `X`

The cap at 10 prevents O(n²) blowup for pathological cases (e.g., matching `aaa`
in a haystack with 1000 `a` characters).

### 2. Entropy-Based AND-Group Ordering

**Before**: AND-groups processed in user input order.
**After**: Sorted by entropy (highest first — most selective terms processed first).

```lua
table.sort(and_groups, function(a, b)
    return a[1].entropy > b[1].entropy
end)
```

Entropy formula:
```lua
entropy = min(#pattern, 20) + rare_chars * 2
-- Doubled if case-sensitive
-- +10 for non-fuzzy, +20 for prefix/suffix
```

**Why**: If the user types `foo bar`, and `bar` is rarer than `foo`, checking
`bar` first lets us skip items faster (early termination when any AND-group
fails). This reduces total scoring work.

### 3. Progressive Rendering

**Before**: Results only delivered after the full scan completes.
**After**: Partial results emitted every ~16ms during scanning.

```lua
local PROGRESS_NS = 16e6 -- 16ms
for i = 1, #items do
    -- ... score item, push to topk ...
    if uv.hrtime() - last_progress > PROGRESS_NS then
        local partial = topk:sorted()
        vim.schedule(function() on_done(partial, nil) end)
    end
    yield()
end
```

**Why**: On a 90k-file repo, full scan takes ~20-40ms. Without progressive
rendering, the user sees nothing for 20-40ms after typing. With it, partial
results appear within 16ms, making the UI feel instant. The `nil` second
argument to `on_done` signals "partial result" — the caller only updates
`_match_state` on the final call (where `state ~= nil`).

### 4. Returns Task Handle

**Before**: `M.run()` returned nothing (fire-and-forget).
**After**: `M.run()` returns a `Beast.Async.Task` that can be aborted.

This is critical for the abort-on-rematch fix in `query.lua`.

---

## Modified: topk.lua

**Path**: `lua/beast/libs/finder/topk.lua`
**Changes**: Text-length tiebreaker in heap comparison and sort output.

### Why

When two items have the same fuzzy score (common for substring matches), the
previous code returned them in arbitrary heap-insertion order. Snacks.nvim
uses sort fields `{ "score:desc", "#text", "idx" }` — meaning equal-score
items are ranked by shorter text first, then by insertion index.

**Example**: Query `calendar-get` against:
- `api-reference/beta/api/calendar-get.md` (len=38, score=315)
- `api-reference/v1.0/includes/snippets/csharp/calendar-getschedule-csharp-snippets.md` (len=83, score=315)

Both score identically (the substring `calendar-get` matches perfectly in the
filename portion of both). But the user obviously wants `calendar-get.md` first.
The text-length tiebreaker ensures shorter paths (more relevant files) rank higher.

### Implementation

New `_less(a, b)` function used in heap sift operations:

```lua
function M:_less(a, b)
    if a.score ~= b.score then
        return a.score < b.score         -- lower score = worse
    end
    local a_len = #(a.text or "")
    local b_len = #(b.text or "")
    if a_len ~= b_len then
        return a_len > b_len             -- longer text = worse
    end
    return (a.idx or 0) > (b.idx or 0)  -- higher idx = worse (later in file list)
end
```

The `push()` method has an inlined fast path:
```lua
if root.score > item.score then return false end  -- common case: score alone decides
if root.score < item.score or self:_less(root, item) then ...
```

This avoids the method call overhead of `_less()` in the 99% case where scores differ.

---

## Rewritten: source/files.lua

**Path**: `lua/beast/libs/finder/source/files.lua`
**Changes**: Queue-based stdout, polling loop, improved command flags.

### Before (per-chunk vim.schedule)

```lua
on_stdout = function(_, data)
    vim.schedule(function()
        -- process lines, call cb() for each
    end)
end
```

Problem: 90k files ÷ ~8KB chunks ≈ hundreds of `vim.schedule` calls, each with
overhead and event loop contention.

### After (queue + polling loop)

```lua
on_stdout = function(_, data)
    -- Runs in libuv context — just push raw data
    queue:push(data)
end

-- Single polling loop drains the queue
local function process()
    local chunk = queue:pop()
    while chunk do
        -- split into lines, emit items
        chunk = queue:pop()
    end
    if not done then
        vim.defer_fn(process, 1)  -- poll again in 1ms
    end
end
vim.schedule(process)  -- kick off first poll
```

**Why**: Only ONE scheduled callback (`process`) is ever active. It drains
all accumulated chunks in a batch, then reschedules itself with `vim.defer_fn`.
This reduces event loop pressure and processes data more efficiently.

### Command Flag Improvements

| Tool | Before | After |
|------|--------|-------|
| `fd` | `fd --type f --hidden --exclude .git` | `fd --type f --type l --hidden --exclude .git --color never` |
| `rg` | `rg --files --hidden --glob '!.git'` | `rg --files --hidden --glob '!.git' --color never --no-messages` |

- `--type l` (fd): Include symlinks — matches what `rg --files` does
- `--color never`: Prevents ANSI escape codes in output (avoids parsing issues)
- `--no-messages` (rg): Suppresses permission-denied warnings that would pollute stdout

---

## Extended: async.lua

**Path**: `lua/beast/libs/async.lua`
**Changes**: Task class with suspend/resume/abort/on_done; spawn returns Task.

### Before

```lua
function M.spawn(fn)
    local co = coroutine.create(fn)
    table.insert(_active, co)
    -- ... start executor ...
end
-- No way to reference or control the spawned coroutine
```

### After

```lua
function M.spawn(fn)
    local co = coroutine.create(fn)
    table.insert(_active, co)
    -- ... start executor ...
    return setmetatable({ _co = co }, Task)
end
```

### Task API

| Method | Description |
|--------|-------------|
| `task:suspend()` | Move coroutine to `_suspended` set — skipped during `step()` |
| `task:resume()` | Remove from `_suspended`, re-add to `_active` |
| `task:running()` | `coroutine.status(self._co) ~= "dead"` |
| `task:on_done(cb)` | Register callback fired when coroutine completes |
| `task:abort()` | Remove from `_active` and `_suspended`, clear callbacks |

### Executor Details

The executor uses `uv.new_check()` — a libuv check handle that fires on every
event loop iteration (after I/O polling). Inside `step()`:

```lua
local function step()
    local start = uv.hrtime()
    while i >= 1 do
        if (uv.hrtime() - start) / 1e6 > BUDGET_MS then break end
        -- resume one coroutine, handle dead/suspended states
    end
    if #_active == 0 then _executor:stop() end
end
```

- `BUDGET_MS = 10` — maximum ms per event loop tick for coroutine work
- `YIELD_EVERY = 100` — inside `yielder()`, only check time every 100 calls

The `_suspended` table allows the concurrent matcher coroutine (in `query.lua`)
to pause without being removed from the system.

---

## Modified: query.lua

**Path**: `lua/beast/libs/finder/query.lua`
**Changes**: Abort-on-rematch, concurrent finder+matcher, GC pausing.

### 1. Abort-on-Rematch (Critical Responsiveness Fix)

**Before**:
```lua
local function rematch(query)
    matcher.run(query.items, query.filter, ...)  -- fire-and-forget
end
```

Each keystroke spawned a new matcher coroutine. Fast typing (e.g., `calendar-get`
= 12 keystrokes in <1s) created 12 concurrent matchers all competing for the
10ms/tick budget. Only the last one's results mattered.

**After**:
```lua
local function rematch(query)
    if query._matcher_task then
        query._matcher_task:abort()  -- kill stale work immediately
    end
    query._matcher_task = matcher.run(...)
end
```

Now each keystroke aborts the previous matcher before starting the new one.
At any moment, only ONE matcher coroutine is active, getting the full 10ms
budget per tick.

### 2. Concurrent Finder + Matcher Coroutines

For async sources (file search with `fd`/`rg`), the finder coroutine streams
items into `query.items` while a separate matcher coroutine can score them
concurrently:

```
Finder coroutine: stdout → queue → items[]
Matcher coroutine: items[] → score → topk → render
```

The matcher coroutine uses `task:suspend()` when waiting for more items and
`task:resume()` when the finder signals new data is available.

### 3. GC Pausing During Stream

```lua
collectgarbage("stop")   -- before streaming starts
-- ... streaming ...
collectgarbage("restart") -- after stream completes or on close
```

**Why**: During the initial file loading phase, thousands of small strings
(file paths) are allocated rapidly. Lua's incremental GC would fire frequently,
causing micro-pauses. Stopping GC during the burst and restarting after reduces
total pause time.

### 4. Task Lifecycle in close()

```lua
function M:close()
    if self._finder_task then self._finder_task:abort() end
    if self._matcher_task then self._matcher_task:abort() end
    collectgarbage("restart")
    -- ... cleanup windows, autocmds ...
end
```

Ensures no orphaned coroutines continue running after the picker is closed.

---

## Performance Results

Benchmark: `scripts/bench-finder-matcher.lua` (90,000 synthetic items)

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Full scan (`f`) | ~60ms | ~18ms | **3.3×** |
| Subset (`fi` after `f`) | ~45ms | ~17ms | **2.6×** |
| Subset (`fil` after `fi`) | ~50ms | ~18ms | **2.8×** |
| Empty pattern | ~2ms | ~3ms | (same) |
| Perceived latency (typing) | ~60ms+ stacking | ~16ms progressive | **Immediate feedback** |

The "perceived latency" improvement is the most impactful: previously, fast
typing caused multiple matchers to stack up (each taking 60ms), effectively
freezing the UI. Now, abort-on-rematch + progressive rendering means the user
sees results within 16ms of the last keystroke.

---

## Before vs After Comparison

### Scoring Quality

Query: `calendar-get` in a repo with 90k files

**Before** (no text-length tiebreaker):
```
1. calendar-getschedule-csharp-snippets.md  (arbitrary order)
2. calendargroup-get-calendars-go-snippets.md
3. calendar-get.md  ← buried!
```

**After** (with tiebreaker):
```
1. calendar-get.md  ← exact filename match, shortest path
2. calendar-getschedule.md
3. calendargroup-get.md
4. calendar-getschedule-csharp-snippets.md  ← long path, ranked lower
```

### Data Flow

**Before**:
```
fd stdout → vim.schedule (per chunk) → split lines → items[] → matcher.run (fire-and-forget)
                                                                    ↓
keystroke → new matcher.run (previous still running!) → render on complete
```

**After**:
```
fd stdout → queue.push (libuv context, zero overhead)
              ↓
poll loop (1ms interval) → drain queue → items[]
                                           ↓
keystroke → abort previous task → matcher.run → progressive render (16ms) → final render
```

### Coroutine Lifecycle

**Before**: No way to cancel spawned coroutines. Dead matchers ran to completion.
**After**: `Task:abort()` immediately removes coroutine from executor. GC collects it.

---

## Files Changed Summary

```
lua/beast/libs/finder/
├── score.lua          NEW   201 lines  Scoring engine
├── queue.lua          NEW    52 lines  Ring buffer
├── matcher.lua        MOD   395 lines  Core matching (was 413)
├── topk.lua           MOD   128 lines  Heap with tiebreaker (was 86)
├── query.lua          MOD   ~480 lines Lifecycle management
├── source/files.lua   MOD   ~140 lines Stdout processing
└── docs/
    └── pipeline-overhaul.md  ← this file

lua/beast/libs/
└── async.lua          MOD   140 lines  Task handles (was 59)
```
