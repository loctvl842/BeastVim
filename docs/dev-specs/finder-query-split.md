---
name: finder-query-split
description: "Finder Query Split"
generated: 2026-05-23
---

# Dev Spec: Finder Query Split

## Summary

Split `lua/beast/libs/finder/query.lua` (570 lines, 10 functions, 5 responsibilities) into
focused modules. The file currently mixes UI orchestration, two completely independent data
pipelines (match vs stream), layout computation, and rendering. The refactoring extracts each
concern into its own file while keeping `query.lua` as a thin orchestrator that delegates.

The two pipelines — **match** ("load items once, re-score locally on each keystroke") and
**stream** ("re-run external command on each keystroke, results are pre-filtered") — share zero
logic in their data paths. They only converge at `render()`. Separating them eliminates scattered
`if _live` checks and lets each pipeline own its own state (timers, tasks, batch buffers).

## Requirements

- Split `query.lua` into ≤4 focused files, each under 150 lines
- Match pipeline and stream pipeline are separate modules with no cross-dependencies
- Each pipeline owns its own private state (no pipeline-specific fields on `Query`)
- `Query` keeps only shared state: UI views, filter, items, matched, callbacks
- No behavioral changes — identical UX before and after
- All existing sources (files, buffers, live_grep, help_tags, colorschemes) work unchanged

### Out of scope

- Changing the layout system (responsive/fractional layout is a separate feature)
- Changing the matcher/scorer internals
- Adding new sources
- Modifying keymaps or autocmds

## Research

### Repo Search

- Searched for: `_live`, `_batch_pending`, `_render_check`, `_match_state`, `_matcher_task`, `_finder_task`
  (`grep -n "_live\|_batch_pending\|_render_check\|_match_state\|_matcher_task\|_finder_task" lua/beast/libs/finder/`)
- Found: All 6 fields exist only in `query.lua`. No other file reads or writes them.
- `_batch_pending`, `_render_check`, `_last_render_ns` — used exclusively by `reload_live()` + `flush_batch()` (stream pipeline)
- `_match_state`, `_finder_task`, `_matcher_task` — used exclusively by `rematch()` + `load()` async path (match pipeline)
- `_live` — used as a branch flag in 5 places to select between the two pipelines
- Reuse opportunity: None — this is a pure refactoring of existing code

### Pattern Search — Explorer Precedent

- Explorer already separates concerns into `state.lua`, `ui.lua`, `render.lua`, `autocmds.lua`, `keymaps.lua`
- The finder should follow a similar pattern: domain logic in pipeline modules, UI in the existing `ui/` directory
- Decision: **Follow explorer pattern** — separate state-owning modules with a thin orchestrator

### Adjacent File Check

- `lua/beast/libs/finder/keymaps.lua` — already separate (follows explorer pattern) ✓
- `lua/beast/libs/finder/autocmds.lua` — already separate ✓
- `lua/beast/libs/finder/format.lua` — already separate (render concern) ✓
- `lua/beast/libs/finder/match_hl.lua` — already separate (render concern) ✓
- Decision: **Build** — extract `render.lua`, `pipeline/match.lua`, `pipeline/stream.lua` from `query.lua`

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/query.lua` | **Rewrite** | Thin orchestrator: `new()`, `close()`, `relayout()` + delegates to pipeline |
| `lua/beast/libs/finder/render.lua` | **Create** | `render(query)`, `schedule_preview(query)` — shared rendering logic |
| `lua/beast/libs/finder/pipeline/match.lua` | **Create** | `load(query)` (sync+async), `rescore(query)` — match pipeline with own state |
| `lua/beast/libs/finder/pipeline/stream.lua` | **Create** | `reload(query)`, `flush(query)` — stream pipeline with own state |
| `lua/beast/libs/finder/layout.lua` | **Create** | `calc_layout(has_preview)` — pure function, no state |

### Resulting file tree

```
finder/
├── query.lua          ← orchestrator: new(), close(), relayout(), on_change dispatch
├── render.lua         ← render(), schedule_preview()
├── layout.lua         ← calc_layout(has_preview) — pure geometry
├── pipeline/
│   ├── match.lua      ← load(query), rescore(query), abort(query)
│   └── stream.lua     ← reload(query), flush(query), abort(query)
├── matcher.lua        (unchanged)
├── score.lua          (unchanged)
├── filter.lua         (unchanged)
├── format.lua         (unchanged)
├── match_hl.lua       (unchanged)
├── action.lua         (unchanged)
├── keymaps.lua        (unchanged)
├── autocmds.lua       (unchanged)
├── highlights.lua     (unchanged)
├── topk.lua           (unchanged)
├── queue.lua          (unchanged)
├── source/            (unchanged)
└── ui/                (unchanged)
```

### State ownership after split

**Query (shared):**
```
items, matched, filter, source,
input_view, list_view, preview_view, _backdrop_win,
main_win, _preview, _augroup, _on_preview, _on_close
```

**pipeline/match.lua (module-local):**
```
_match_state     — subset elimination cache
_finder_task     — async source coroutine handle
_matcher_task    — scorer coroutine handle
```

**pipeline/stream.lua (module-local):**
```
_batch_pending   — items awaiting flush
_render_check    — uv_check handle for adaptive polling
_last_render_ns  — throttle timestamp
```

**render.lua (module-local):**
```
_preview_timer   — debounce timer for preview updates
```

## Implementation Phases

### Phase 1: Extract layout and render — no behavioral change

1. **Create `layout.lua`** (File: `lua/beast/libs/finder/layout.lua`)
   - Action: Move `calc_layout(has_preview)` and the `Beast.Finder.Layout.*` type definitions
     out of `query.lua`
   - Why: Pure function with no dependencies on Query state — trivial extraction
   - Depends on: None
   - Risk: Low

2. **Create `render.lua`** (File: `lua/beast/libs/finder/render.lua`)
   - Action: Move `render(query)` and `schedule_preview()` into a new module.
     Export `M.render(query)` and `M.schedule_preview(query)`.
     Move `_preview_timer` from Query field to module-local state keyed by query instance.
   - Why: Render is shared by both pipelines — extracting it first means the pipelines
     can require it without circular deps
   - Depends on: Step 1 (render uses list width, but doesn't need layout directly)
   - Risk: Low — `render()` is already a free function `render(query)`, not a method

3. **Update `query.lua`** (File: `lua/beast/libs/finder/query.lua`)
   - Action: Replace inline `calc_layout()` call with `require("beast.libs.finder.layout")`.
     Replace inline `render()` calls with `require("beast.libs.finder.render").render(query)`.
     Remove `schedule_preview()` method, `_preview_timer` field.
   - Depends on: Steps 1–2
   - Risk: Low

### Phase 2: Extract pipelines

4. **Create `pipeline/match.lua`** (File: `lua/beast/libs/finder/pipeline/match.lua`)
   - Action: Move the match pipeline logic:
     - `load(query)`: the sync path (3 lines) + async path (coroutine, GC pause, progressive render)
     - `rescore(query)`: current `rematch()` — abort previous `_matcher_task`, spawn new one
     - `abort(query)`: abort both `_finder_task` and `_matcher_task`
     - Module-local state: `_match_state`, `_finder_task`, `_matcher_task` (keyed per query instance)
   - Why: This is the data pipeline for files/buffers/help/colorschemes — completely independent
     from the stream pipeline
   - Depends on: Phase 1 (needs `render.lua` for the render callback)
   - Risk: Medium — the async load coroutine has subtle interactions with Task suspend/resume

5. **Create `pipeline/stream.lua`** (File: `lua/beast/libs/finder/pipeline/stream.lua`)
   - Action: Move the stream pipeline logic:
     - `reload(query)`: current `reload_live()` — cancel subprocess, reset state, start poll loop, spawn source
     - `flush(query)`: current `flush_batch()` — move `_batch_pending` → `items`, render
     - `abort(query)`: stop `_render_check`, cancel source, restart GC
     - Module-local state: `_batch_pending`, `_render_check`, `_last_render_ns` (keyed per query instance)
   - Why: This is the data pipeline for live_grep — no dependency on matcher at all
   - Depends on: Phase 1 (needs `render.lua`)
   - Risk: Low — simpler pipeline, fewer moving parts

6. **Slim down `query.lua`** (File: `lua/beast/libs/finder/query.lua`)
   - Action: Remove all pipeline functions and state fields. `M:new()` dispatches to the
     correct pipeline based on `source.live`. The `on_change` callback becomes:
     ```lua
     if is_live then
         stream.reload(query)
     else
         match_pipeline.rescore(query)
     end
     ```
     `M:close()` calls `match_pipeline.abort(query)` or `stream.abort(query)`.
     `M:load()` calls `match_pipeline.load(query)` (live sources skip load — empty until keystroke).
   - Remove fields: `_live`, `_batch_pending`, `_match_state`, `_render_check`,
     `_last_render_ns`, `_finder_task`, `_matcher_task`, `_preview_timer`
   - Add field: `pipeline` — reference to the active pipeline module (`match` or `stream`)
   - Depends on: Steps 4–5
   - Risk: Medium — must ensure close() cleanup covers both pipeline paths

## Testing Strategy

- **Bench**: Run `nvim --clean --headless -l scripts/bench-finder-matcher.lua` — must still pass
  (< 80ms full scan, < 50ms subset)
- **Syntax check**: `nvim --clean --headless -l` on each new file to catch require errors
- **Stylua**: `stylua --check lua/beast/libs/finder/`
- **Manual verification**:
  1. Open files finder (`<leader>f`) — type `init`, confirm results appear progressively
  2. Open live grep (`<leader>g`) — type `function`, confirm results stream in
  3. Open buffers (`<leader>b`) — confirm immediate list
  4. Open help tags (`<leader>h`) — confirm immediate list
  5. Resize terminal while picker is open — confirm relayout works
  6. Close picker with `<Esc>` during active search — confirm no errors, GC restarts

## Risks & Mitigations

- **Risk**: Module-local state keyed per query instance could leak if `close()` doesn't clean up
  → **Mitigation**: Each pipeline's `abort()` function clears all module-local state for that query
- **Risk**: Circular dependency between `render.lua` and pipeline modules
  → **Mitigation**: Dependency flows one way: `pipeline/* → render.lua → ui/*`. Render never requires pipeline.
- **Risk**: The `_live` flag removal could miss an edge case
  → **Mitigation**: `query.pipeline` field holds the active module — all dispatch goes through it, no flag checks needed

## Success Criteria

- [ ] `query.lua` is under 150 lines
- [ ] No `_live` checks remain in `query.lua`
- [ ] Each pipeline file is under 120 lines
- [ ] `render.lua` is under 80 lines
- [ ] `layout.lua` is under 80 lines
- [ ] Zero pipeline-specific state fields on the `Beast.Finder.Query` class
- [ ] `bench-finder-matcher.lua` passes (< 80ms full, < 50ms subset)
- [ ] All 5 sources work: files, buffers, live_grep, help_tags, colorschemes
- [ ] Codemap regenerated and committed alongside
