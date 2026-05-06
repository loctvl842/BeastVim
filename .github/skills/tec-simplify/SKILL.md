---
name: tec-simplify
description: "Reduce code complexity while preserving exact behavior. Finds over-engineering, deep nesting, long functions, dead code, and unclear naming. Respects design decisions. Use when asked to 'simplify', 'clean up', 'reduce complexity', 'refactor', 'code health', 'too complex'."
---

# Code Simplification

Reduce complexity while preserving exact behavior. The goal: "Would a new team member understand this faster than the original?"

## Step 1: Understand Before Touching (Chesterton's Fence)

Before simplifying anything:
1. Read `docs/CODEMAPS/` — understand the architecture
2. Read `docs/ADRs/INDEX.md` — decisions that explain WHY code is structured a certain way (especially supersession chains like ADR-010 → ADR-013)
3. Read `AGENTS.md` § *BeastVim Library Conventions* — the file structure, type naming, View pattern, Config pattern, animation pattern, and code style rules. Many shapes that *look* simplifiable are intentional (e.g. a class vs a table-of-functions choice).
4. Check `git log` on the file — understand the history

**If you don't understand why code exists, don't simplify it.** Ask first.

## Step 2: Scan for Complexity

| Pattern | Signal | Fix |
|---|---|---|
| Deep nesting (3+ levels) | Hard to follow control flow | Guard clauses, early returns |
| Long functions (50+ lines) | Multiple responsibilities | Split into focused functions |
| Nested ternaries | Mental stack required | if/else or lookup object |
| Generic names (`data`, `result`, `temp`) | Unclear intent | Rename to describe content |
| Duplicated logic (same 5+ lines in multiple non-test files) | Copy-paste | Extract shared function |
| Dead code (unreachable, commented-out) | Noise | Delete — git remembers |
| Over-engineered patterns | Factory-for-a-factory, strategy-with-one-strategy | Replace with direct approach |
| Boolean parameter flags | `doThing(true, false, true)` | Options object or separate functions |

**Skip test files if an ADR documents standalone test patterns as intentional.**

## Step 2.5: Cross-Lib DRY Audit (BeastVim-specific)

The single highest-leverage simplification in this repo is **finding patterns that recur across libs and consolidating them**. Read `AGENTS.md` § *Shared Modules Registry* and § *Known DRY Opportunities* before scanning — those tables are the authoritative list of what is shared and what is *waiting* to be shared.

For each candidate pattern, follow the AGENTS extraction trigger rule:

| Instances | Action |
|---|---|
| 1 | Leave it — too early to abstract |
| 2 | Note it; add a row to *Known DRY Opportunities* if not already there |
| 3 | Extract — the threshold is met |
| 4+ | **Overdue** — extraction is the highest-priority simplification |

When extracting:

1. Pick a name that matches the registry's naming convention (e.g. `Util.scratch_buf`, `Util.config_proxy`).
2. The shared module goes under `lua/beast/util/` (or `lua/beast/libs/<shared-name>.lua` if it's stateful enough to need its own file — see `lua/beast/libs/view.lua`).
3. Migrate **every** caller in the same dev spec. Half-migrations are worse than no extraction.
4. Update `AGENTS.md`:
   - Add a row to *Shared Modules Registry*
   - Remove the corresponding row from *Known DRY Opportunities*
   - If the extraction revealed *new* duplication that's now visible, add a row for that

**Trigger to run this audit:** before any non-trivial simplification, scan the lib being touched against `AGENTS.md` § *Known DRY Opportunities*. If the lib contains an instance of a listed pattern, the simplification is "extract first, refactor second" — not local edits.

## Step 3: Apply Incrementally

For each simplification:
1. Make **one change** at a time
2. Verify tests still pass
3. If tests break → revert (you likely changed behavior)
4. Commit separately from feature work

**Rule of 500**: If a refactoring touches 500+ lines, use automation (codemods, scripts) instead of manual edits.

## Step 4: Verify

After all simplifications:
- [ ] All existing tests pass **without modification** (if tests needed changes, you changed behavior)
- [ ] Build succeeds
- [ ] Simplified code follows project conventions
- [ ] No error handling was removed
- [ ] Diff is clean — no unrelated changes
- [ ] A teammate would approve this as a net improvement

## Anti-Rationalizations

| Excuse | Reality |
|---|---|
| "It's working, don't touch it" | Working code that's hard to read will be hard to fix when it breaks |
| "Fewer lines is always simpler" | A 1-line nested ternary is not simpler than a 5-line if/else. Comprehension speed matters, not line count. |
| "I'll just quickly simplify this unrelated code too" | Stay scoped. Unrelated simplifications create noisy diffs and risk regressions. |
| "The original author must have had a reason" | Check git blame + ADRs. If there's a reason, respect it. If not, it's accumulated complexity. |
| "I'll refactor while adding this feature" | Separate refactoring from features. Mixed changes are harder to review and revert. |

## Red Flags

- Simplification that requires modifying tests to pass (you changed behavior)
- "Simplified" code that is longer or harder to follow than the original
- Removing error handling because "it's cleaner"
- Simplifying code you don't fully understand
- Refactoring code outside the scope of the current task
