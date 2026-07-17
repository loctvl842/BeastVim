---
name: bench-explorer
description: "Explorer Render-Time Benchmark"
generated: 2026-05-13
---

# Summary

Add `scripts/bench-explorer.lua` — a headless benchmark that measures the
explorer's render hot path (`tree:flat()` → `render.build()` → `render.write()`
→ `sticky.refresh()`) under controlled tree sizes. Follows the same contract as
`bench-statusline.lua` (exit 0/1/2, `BENCH …` summary line).

# Requirements

- Measure the **full render cycle** (`ui.render()`) as the primary metric
- Break down into **sub-metrics** so regressions can be attributed:
  - `tree:flat()` — flatten the tree (cache-miss path)
  - `render.build()` — generate lines + highlight specs
  - `render.write()` — `nvim_buf_set_lines` + extmark application
  - `sticky.refresh()` — ancestor computation + float redraw
- Generate a **real temporary folder** on disk with varied shapes so the bench
  exercises realistic edge cases the explorer would actually encounter
- Test **multiple scenarios** (each is a tmp dir with a specific shape):
  - `wide` — flat directory with 100 files + 10 dirs (tests broad iteration)
  - `deep` — 8 levels of nesting, 3 entries per level (tests prefix/ancestor cost)
  - `hidden` — 50% hidden files (tests filtering path in `tree:flat`)
  - `mixed` — realistic project: ~200 nodes, mixed depth/breadth, some hidden
- The **primary metric** uses `mixed` (closest to a real project)
- Hard threshold: **2 ms** per full render (`mixed` scenario)
- Soft warn: **500 µs** per full render (`mixed` scenario)
- Conform to the `scripts/bench-*.lua` contract in `health-config.md`
- No external dependencies — runs with `nvim --clean --headless -l`

# Research

### Repo Search
- Searched: `render`, `flat`, `build_prefix`, `render.write`, `sticky.refresh`
- Found: The render pipeline in `explorer/ui.lua` line 90–103:
  1. `state.tree:flat(opts)` → flat node list (cached by version)
  2. `render.build(nodes)` → `lines[], hls[]`
  3. `render.write(lines, hls)` → buffer + extmarks
  4. `sticky.refresh()` → recompute pinned ancestors, redraw float
- The `tree:flat()` cache means repeated renders with no tree mutation are
  O(1). The bench must invalidate the cache (`tree:_touch()`) to measure the
  cache-miss path separately from the cache-hit path.
- Reuse opportunity: `bench-statusline.lua` has a `bench(fn)` helper and the
  same mean-of-N×M pattern. Copy the pattern (not a shared module — bench
  scripts are standalone).

### Package Search
- Searched: Neovim native APIs for timing
- Found: `vim.uv.hrtime()` (nanosecond monotonic clock) — same as statusline bench
- Decision: **Use native** — no packages needed

# Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `scripts/bench-explorer.lua` | Create | The benchmark script |

Single file. No library changes needed.

# Implementation Phases

### Phase 1: Create `scripts/bench-explorer.lua`

1. **Scaffold + setup** (File: `scripts/bench-explorer.lua`)
   - Prepend rtp and package.path (same as statusline bench)
   - Stub `Palette` global (highlights need it)
   - Risk: Low

2. **Tmp folder generator** (File: `scripts/bench-explorer.lua`)
   - Function `make_scenario(name, spec)` that creates a real tmp directory
     using `vim.fn.tempname()` + `vim.fn.mkdir()` + `vim.fn.writefile()`
   - Scenarios:
     - `wide`: 100 files + 10 subdirs (1 level)
     - `deep`: 8 levels, 3 entries per level (~24 nodes)
     - `hidden`: 100 entries, 50% start with `.`
     - `mixed`: 4 levels, variable breadth (5–15 per dir), ~200 total nodes
   - Cleanup: `vim.fn.delete(tmpdir, "rf")` at script end
   - Why: Real filesystem I/O exercises `uv.fs_scandir` in `tree:expand()`
   - Risk: Low (tmp dirs are fast on any OS)

3. **Explorer state wiring** (File: `scripts/bench-explorer.lua`)
   - For each scenario: create a buffer+window (vsplit), set `state.tree`,
     `state.view`, configure `config` for the bench
   - Expand the full tree before timing (pre-warm `tree:expand()` on all dirs)
   - Why: Separates expansion cost from render cost — both are interesting
     but the render loop is the CursorMoved hot path
   - Risk: Low

4. **Sub-benchmarks per scenario** (File: `scripts/bench-explorer.lua`)
   - For the `mixed` scenario (primary):
     - `bench_expand()` — time `tree:expand()` on all dirs (cold expansion)
     - `bench_flat_miss()` — time `tree:flat()` after `tree:_touch()`
     - `bench_flat_hit()` — time `tree:flat()` without touch (cache-hit)
     - `bench_build()` — time `render.build(nodes)`
     - `bench_write()` — time `render.write(lines, hls)`
     - `bench_full_render()` — time `ui.render()` end-to-end
   - For other scenarios: only `bench_full_render()` (regression coverage)
   - Each runs 3 × 200 iterations
   - Risk: Low

5. **BENCH summary + exit code** (File: `scripts/bench-explorer.lua`)
   - Print per-scenario and per-sub-metric lines for diagnostics
   - Print final `BENCH name=explorer full_render=Xus nodes=N scenario=mixed threshold=2000us`
   - Exit 0 if mixed full_render < 2000 µs, exit 1 if over, exit 2 on setup error
   - Risk: Low

# Testing Strategy

- **Bench itself is the test** — `nvim --clean --headless -l scripts/bench-explorer.lua`
- Manual verification: run and confirm exit 0, read the per-metric breakdown
- Health check integration: next `tec-health` run will pick it up via glob

# Metrics Summary

| Metric | Scenario | What it measures | Why it matters |
|--------|----------|-----------------|----------------|
| `full_render` | mixed | Complete `ui.render()` | **Primary** — fires on every CursorMoved/WinScrolled |
| `full_render` | wide | Render with 110 entries flat | Catches O(n) regressions in broad dirs |
| `full_render` | deep | Render with 8-level nesting | Catches `build_prefix` ancestor-walk cost |
| `full_render` | hidden | Render with 50% filtered nodes | Catches filtering overhead in `tree:flat()` |
| `expand` | mixed | `tree:expand()` all dirs cold | Filesystem I/O + node creation cost |
| `flat_miss` | mixed | `tree:flat()` cache-miss | Tree mutation cost (expand/collapse/refresh) |
| `flat_hit` | mixed | `tree:flat()` cache-hit | Steady-state cost (cursor moves without tree changes) |
| `build` | mixed | `render.build(nodes)` | String assembly + highlight spec generation |
| `write` | mixed | `render.write(lines, hls)` | Buffer API + extmark cost |

# Risks & Mitigations

- **Risk**: Tmp folder creation adds time to the bench itself → **Mitigation**: Creation is outside the timed loop. Only the render path is measured. Cleanup at the end.
- **Risk**: OS-level filesystem caching makes `tree:expand()` unrealistically fast → **Mitigation**: That's fine — we're benching the Lua tree-building cost, not raw I/O. Real usage also benefits from OS cache.
- **Risk**: `render.write()` depends on a valid window — headless might not have one → **Mitigation**: Open a vsplit (same as the real explorer). Statusline bench already proves this works.
- **Risk**: `sticky.refresh()` needs cursor position and scroll state → **Mitigation**: Set cursor to middle of buffer before benching. Measured as part of `full_render`, not isolated (too coupled to window state for a standalone sub-bench).
- **Risk**: Different machines produce different absolute numbers → **Mitigation**: The threshold (2 ms) is generous enough to pass on slow CI runners. The value of the bench is **regression detection** across runs on the same machine.

# Success Criteria

- [ ] `nvim --clean --headless -l scripts/bench-explorer.lua` exits 0
- [ ] Full render (200 nodes) < 2 ms (hard threshold)
- [ ] Full render (200 nodes) < 500 µs (soft target)
- [ ] `tec-health` picks up the bench and reports it in the next run
- [ ] Sub-metrics printed so regressions can be attributed to a specific stage
