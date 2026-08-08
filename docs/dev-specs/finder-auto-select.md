---
name: finder-auto-select
description: Pre-flight LSP check before opening the finder picker, plus a statusline checking indicator
generated: 2026-08-08
---

> PM Spec: [docs/pm-specs/finder-auto-select.md](../pm-specs/finder-auto-select.md)

# Summary

Move the single-result short-circuit for LSP jumps (`lsp_definitions`, `lsp_references`,
`lsp_declarations`, `lsp_implementations`) from *after* the picker UI is created to *before* it —
a pre-flight request runs first, and the picker only opens if it resolves to more than one
location. A new shared status module plus a statusline component give the user a "checking…"
cue during the pre-flight wait, replacing the feedback role the picker's own spinner used to play.

---

# Context

## Problem

`finder.open()` (`lua/beast/libs/finder/init.lua:22`) unconditionally builds the full picker
(`State:new()` — input/list/preview/backdrop floating windows) before any results exist, then
`pipeline/match.lua`'s async loader streams LSP results into it. Only after the *entire* result
set has arrived does `match.lua:135` check `source.auto_select and #matched == 1`, and if so,
call `state:reset()` to tear the picker down and jump. For the common single-result case (most
go-to-definition calls), this means the picker's floating windows are created and destroyed
within the same request — a visible flash — and `reset()` closes the input window while it may
still be in insert mode, which is the documented root cause (`match.lua:117-134`, `KNOWN BUG`
comment) of the cursor landing one column left of the target.

There is currently no mechanism to run a source query without first constructing a `State`
(picker UI), and no shared, cross-lib way to broadcast "finder is doing background work" the way
`beast.visibility` already broadcasts hidden/gitignored state to multiple libs.

### Solution

`finder.open()` gains a branch: sources with `auto_select = true` run a lightweight pre-flight
collection of the source's full result set (no picker, no windows) before deciding what to do.
Exactly one result jumps directly in the already-current window. Zero results falls through to
the source's existing not-found notification. More than one result proceeds to build the picker
exactly as today. A new top-level shared module (`lua/beast/finder_status.lua`, mirroring
`lua/beast/visibility.lua`'s pattern) tracks "is a pre-flight check in flight, and for which
action" and fires a `User BeastFinderStatusChanged` autocmd on change; a new statusline component
reads it and renders an action-labelled spinner using the same event → invalidate → redrawstatus
plumbing `statusline/init.lua` already runs for `git_branch.lua`'s `BeastStatusPolineGitChanged`.

---

# Research

### Repo Search

- Searched for: `auto_select` (`grep -rn "auto_select" lua/beast/`)
- Found: set only by `source/lsp.lua:28` (shared factory for all 4 LSP sources); consumed only by
  `pipeline/match.lua:135`. No other source sets it, and no other code branches on it.
  Reuse opportunity: none needed — this confirms the change is fully scoped to the LSP path;
  files/buffers/live_grep/colorschemes/help_tags are untouched.
- Searched for: existing "run a source query without a picker" helper
  (`grep -rn "source.get(" lua/beast/libs/finder/`)
- Found: `source.get(filter, cb)` is only ever invoked from `pipeline/match.lua` (streaming into
  the picker) and `pipeline/stream.lua` (live re-query on keystroke). No standalone
  "collect all, no UI" caller exists — this is genuinely new, not a duplicate of anything.
- Searched for: existing cross-lib shared-state modules with a change event
  (`grep -rln "nvim_exec_autocmds(\"User\"" lua/beast/`)
- Found: `lua/beast/visibility.lua` (`BeastVisibilityChanged`, consumed by explorer/finder/
  tabline/statusline) and `lua/beast/libs/statusline/components/git_branch.lua`
  (`BeastStatuslineGitChanged`, fired from an fs_event watcher outside the statusline lib).
  Reuse opportunity: **yes** — `visibility.lua` is the exact shape needed (readonly-proxy config
  table, `methods.*` mutators, `emit_changed` helper) for the new `finder_status.lua` module, and
  `git_branch.lua` is the exact shape needed for a statusline component driven by an external
  module's change event.
- Searched for: existing headless test for a shared-state module
  (`tests/test-visibility.lua`) — found and used as the direct template for the new
  `tests/test-finder-status.lua` (see Testing Strategy).

### Built-in / Existing Lib Check

- Checked: `vim.lsp.status()` / `$/progress` (`LspProgress` autocmd) as a source of "check in
  progress" feedback.
  Found: not usable here — servers only report `$/progress` on requests where they choose to
  attach a `workDoneToken`; a routine `textDocument/definition` request essentially never gets
  one in practice. This was already established with the user before scoping the PM spec, and is
  why the new indicator is a plain request-pending flag, not real LSP progress data.
- Checked: `toast/progress.lua`'s spinner (`lua/beast/libs/toast/progress.lua:41-47`) — a
  *time-derived* frame index (`hrtime() / interval % #frames`, no per-instance counter) plus a
  throttled `vim.uv.timer` that repaints while any token is active, stopping itself once the
  token set is empty.
  Found: directly reusable *pattern* (not code — different subsystem, different repaint
  mechanism: toast repaints itself via `toast.update`, statusline must repaint via the
  `User BeastFinderStatusChanged` → `invalidate_component` → `redrawstatus` path already wired in
  `statusline/init.lua:182-208`). Decision: **reuse the pattern**, tick interval matches the
  existing `SPINNER_INTERVAL_MS = 80` already used by the picker's own spinner
  (`lua/beast/libs/finder/ui/input.lua:11`), for visual/cadence consistency between the two
  spinners the user will see (this one, and the picker's own once it opens for a multi-result
  jump).
- Checked: `View.win.find_normal()` (used by `state.lua:52` to find the window a jump should land
  in) and `action.open_file(state, item)` (`lua/beast/libs/finder/action.lua:36`).
  Found: `open_file` only ever reads `state.main_win` — it doesn't touch any other field.
  Decision: **reuse `action.open_file` directly** from the pre-flight path with a minimal
  `{ main_win = win }` table, instead of adding a new jump function. No changes to `action.lua`
  needed.
- Checked: `Filter:new(opts)` (`lua/beast/libs/finder/filter.lua:16`) — already callable standalone
  (`Filter({ cwd = ... })`) without a `Query`/`State` instance.
  Decision: **reuse as-is** to build the pre-flight filter.

**Decision: Build** the pre-flight collector and the shared status module — nothing existing
covers "run a source to completion with no UI," but every supporting piece (filter construction,
jump execution, change-event plumbing, spinner cadence) is reused from existing code rather than
reinvented.

---

# Architecture Changes

- `lua/beast/libs/finder/preflight.lua` — **new**. Runs `source.get(filter, cb)` to completion,
  collects items into a plain array, and hands the final list to a callback. Generation-counter
  guard so a superseded (rapid re-trigger) check's late callback is a no-op.
- `lua/beast/libs/finder/init.lua` — **modified**. `M.open()` branches on `source.auto_select`:
  pre-flight first via `preflight.check`, decide jump vs. picker vs. nothing from the result count.
- `lua/beast/libs/finder/pipeline/match.lua` — **modified**. Remove the now-unreachable
  single-result branch (lines ~111-144, including the `KNOWN BUG` comment) — pre-flight fully
  replaces this code path for every source that sets `auto_select`, which is the only thing that
  branch ever fired for.
- `lua/beast/libs/finder/source/lsp.lua` — **modified**. `M.create(method, label)` gains a
  `label` parameter, stored on the source table as `source.label` (e.g. `"Definition"`) for the
  statusline indicator to display.
- `lua/beast/libs/finder/source/lsp_definitions.lua`, `lsp_references.lua`,
  `lsp_declarations.lua`, `lsp_implementations.lua` — **modified** (one line each). Pass their
  display label to `lsp.create(method, label)`.
- `lua/beast/finder_status.lua` — **new**. Top-level shared module (alongside `visibility.lua`,
  per the codemap's "Shared modules" list) tracking the current pre-flight action label (or nil).
  `M.start(label)`, `M.stop()`, read via `M.action`. Fires `User BeastFinderStatusChanged` on
  every change, including on each spinner tick while active (see Phase 2 for why).
- `lua/beast/libs/statusline/components/finder_lsp.lua` — **new**. Provider reads
  `finder_status.action`; renders nothing when nil, else a time-derived spinner frame + the
  action label.
- `lua/beast/libs/statusline/components/init.lua` — **modified**. Register
  `M.finder_lsp = require("beast.libs.statusline.components.finder_lsp")`.
- `lua/beast/init.lua` — **modified**. Add `cpn.finder_lsp` to the statusline `setup()` component
  list (`lua/beast/init.lua:92-95`).

## Implementation Phases

### Phase 1: Pre-flight redesign (no statusline feedback yet)

Delivers PM spec success criteria 1, 2, and 4 (no picker flash on single-result, unchanged
multi/zero-result behavior, cursor bug gone) on its own — independently mergeable and testable
without touching the statusline lib at all.

1. **Create `preflight.lua`** (File: `lua/beast/libs/finder/preflight.lua`)
   - Action: `M.check(source, filter, on_done)` — calls `source.get(filter, cb)`, appends each
     streamed item to a local array, and calls `on_done(items)` once `cb(nil)` fires. Maintains a
     module-local `generation` counter incremented on every `check()` call; captures it at call
     time and compares on each `cb` invocation, silently dropping callbacks from a superseded
     generation (no `on_done` call at all for an abandoned check).
   - Why: `source.get`'s streaming contract (`cb(item)` ... `cb(nil)`) is identical to what
     `pipeline/match.lua` already consumes — no changes needed to `source/lsp.lua`'s request
     logic itself, only a new, simpler consumer that skips scoring/TopK/rendering entirely.
   - Depends on: None
   - Risk: Low

2. **Modify `finder/init.lua`** (File: `lua/beast/libs/finder/init.lua`)
   - Action: In `M.open(source_name, opts)`, after resolving `source = source_registry[source_name]`:
     - Unconditionally call `M.close()` first (preserves today's implicit guarantee that any
       `finder.open()` call resets a previously open picker — currently provided by
       `State:new()`'s `if instance then instance:reset() end`, which the pre-flight branches
       below bypass since they may never construct a `State`).
     - If `source.auto_select`: build `local filter = require("beast.libs.finder.filter")({ cwd = opts.cwd })`
       and `local main_win = View.win.find_normal()`, then call
       `require("beast.libs.finder.preflight").check(source, filter, function(items) ... end)`
       and `return` (skip the normal `State`/`keymaps`/`autocmds` path entirely for this call).
     - Inside the callback: `#items == 1` → `require("beast.libs.finder.action").open_file({ main_win = main_win }, items[1])`.
       `#items > 1` → fall through to the existing `state = State(source_name, opts)` +
       `keymaps.mount(state)` + `autocmds.mount(state)` sequence (picker opens exactly as today;
       it will re-run `source.get` itself via `pipeline/match.lua` — see Phase 3 for removing
       that duplicate fetch).
       `#items == 0` → nothing further; `source.get` (e.g. `source/lsp.lua:104-106`) already
       emits the not-found `vim.notify` before calling `cb(nil)`.
   - Why: This is the actual pre-flight gate the PM spec describes — deciding whether to build a
     picker at all, before any window exists.
   - Depends on: Step 1
   - Risk: Medium — this is the core behavioral change; needs careful manual verification against
     all 6 PM spec scenarios (see Testing Strategy).

3. **Modify `pipeline/match.lua`** (File: `lua/beast/libs/finder/pipeline/match.lua`)
   - Action: Delete the `if source.auto_select and #state.query.matched == 1 then ... end` block
     (current lines ~111-144) and its `KNOWN BUG` comment. The `vim.schedule` block that follows
     it (render + stop spinner + restart GC) becomes the only path after the coroutine's main
     loop.
   - Why: Dead code after Phase 1 step 2 — the picker is never opened at all for a single-result
     `auto_select` source anymore, so this branch can't fire. Leaving it in place would be
     confusing (a code path that looks reachable but never runs) and keeps the cursor-bug-prone
     `state:reset()` call alive for no reason.
   - Depends on: Step 2
   - Risk: Low — pure deletion, no logic change to the remaining code.

### Phase 2: Statusline checking indicator

Delivers PM spec success criterion 3. Independently mergeable on top of Phase 1 — Phase 1 alone
is already a complete, correct fix; this phase only adds the feedback layer for slow responses.

4. **Create `lua/beast/finder_status.lua`** (File: `lua/beast/finder_status.lua`)
   - Action: Follow `lua/beast/visibility.lua`'s exact shape (readonly-proxy metatable,
     `methods` table, module-local `cfg`). State is a single field: `action` (string|nil).
     - `M.start(label)`: sets `cfg.action = label`, fires
       `vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderStatusChanged" })`, and starts
       a `vim.uv.timer` (interval = 80ms, matching `finder/ui/input.lua`'s `SPINNER_INTERVAL_MS`)
       whose tick — `vim.schedule_wrap` — re-fires the same `User BeastFinderStatusChanged`
       autocmd (not a direct `vim.cmd("redrawstatus")` — see the note below). Calling `start()`
       again while already active just updates `cfg.action` and fires once immediately; it does
       not restart the timer.
     - `M.stop()`: sets `cfg.action = nil`, stops+closes the timer, fires the changed event once
       more so the statusline clears immediately rather than waiting for the next tick.
   - Why (the "fires the User event on every tick, not a raw redrawstatus" note): statusline
     components with a declared `update` list are cache-gated
     (`statusline/init.lua:82-131`) — `eval_component` only re-runs `provider()` when
     `invalidate_component` has cleared its cache entry, which only happens inside
     `register_event_autocmds`'s callback (`statusline/init.lua:192-209`), which only runs for a
     *declared* autocmd event. A bare `vim.cmd("redrawstatus")` repaints the bar but replays the
     *cached* fragment — the spinner would render once and then freeze. Re-firing the declared
     `User BeastFinderStatusChanged` event on each tick is what makes the existing plumbing
     invalidate + re-run + redraw, exactly as it already does for `git_branch.lua`'s fs_event
     watcher. This was the key subtlety this research phase surfaced.
   - Depends on: None
   - Risk: Low — small, isolated module; same shape as an existing, tested module
     (`visibility.lua` / `test-visibility.lua`).

5. **Create `statusline/components/finder_lsp.lua`** (File:
   `lua/beast/libs/statusline/components/finder_lsp.lua`)
   - Action: `update = { "User BeastFinderStatusChanged" }`, `scope = "global"`,
     `priority = 96` (transient/important, same tier as `macro.lua`'s 95 — should survive
     truncation whenever visible). `provider()`: if `finder_status.action == nil`, return `{}`
     (renders nothing, matching `macro.lua`'s hide-when-inactive pattern). Otherwise compute a
     time-derived spinner frame the same way `toast/progress.lua:41-47` does
     (`hrtime()`-based index into a frame table — reuse the same braille frame set already used by
     `finder/ui/input.lua:6` for visual consistency between this indicator and the picker's own
     spinner) and return two fragments: the spinner glyph, then `finder_status.action` (e.g.
     `"Definition"`).
   - Why: Matches the declarative `Beast.Statusline.ComponentSpec` shape every other component
     already uses; no new mechanism introduced into the statusline lib itself.
   - Depends on: Step 4
   - Risk: Low

6. **Wire `finder_status` into `finder/init.lua`** (File: `lua/beast/libs/finder/init.lua`)
   - Action: In the `auto_select` branch added in Phase 1 step 2, call
     `require("beast.finder_status").start(source.label)` immediately before
     `preflight.check(...)`, and `require("beast.finder_status").stop()` as the first line inside
     the `on_done` callback (before branching on `#items`).
   - Why: Because `preflight.lua`'s generation guard already drops an abandoned check's callback
     entirely (Phase 1 step 1), `finder_status.stop()` is only ever called by the *current*
     generation's own resolution — a superseded check can never clear the newer check's
     indicator. This is what makes PM spec scenario 6 (rapid re-trigger) work correctly without
     any extra generation-awareness inside `finder_status.lua` itself.
   - Depends on: Steps 4, 5; Phase 1 step 2
   - Risk: Low

7. **Register the source labels** (Files: `lua/beast/libs/finder/source/lsp.lua`,
   `lsp_definitions.lua`, `lsp_references.lua`, `lsp_declarations.lua`, `lsp_implementations.lua`)
   - Action: `lsp.lua`'s `M.create(method)` becomes `M.create(method, label)`, storing
     `source.label = label`. Each of the 4 thin source files passes its label, e.g.
     `require("beast.libs.finder.source.lsp").create("textDocument/definition", "Definition")`.
   - Why: Keeps the label declarative on the source table alongside `auto_select`/`live`/`async`,
     rather than a separate name→label lookup table living in `init.lua`.
   - Depends on: None (can land in either phase; grouped here since it's only consumed by the
     statusline indicator)
   - Risk: Low

8. **Register the component** (Files: `lua/beast/libs/statusline/components/init.lua`,
   `lua/beast/init.lua`)
   - Action: Add `M.finder_lsp = require("beast.libs.statusline.components.finder_lsp")` to
     `components/init.lua`; add `cpn.finder_lsp` to the `left` list in `init.lua`'s statusline
     `setup()` call (`lua/beast/init.lua:92-95`), next to `git_branch`/`diagnostics`.
   - Depends on: Step 5
   - Risk: Low

### Phase 3 (optional, efficiency-only — not required by the PM spec)

Not needed for any PM spec success criterion; flagged separately because Phase 1's multi-result
path causes `source.get` to run twice per multi-result jump (once during pre-flight, once again
when the picker opens and `pipeline/match.lua` loads normally) — functionally harmless (read-only
LSP requests) but wasteful. Skippable; only take this on if the duplicate request proves
noticeable in practice.

9. **Thread preloaded items through `Query`/`pipeline/match.lua`** (Files:
   `lua/beast/libs/finder/query.lua`, `lua/beast/libs/finder/pipeline/match.lua`,
   `lua/beast/libs/finder/init.lua`)
   - Action: `Query:new` accepts `opts.preloaded_items`; `pipeline/match.lua`'s `M.load` checks
     for it and, if present, skips calling `source.get()` entirely — treats the array as already
     fully streamed and feeds it straight into the existing TopK/render loop. `init.lua` passes
     the pre-flight's already-fetched `items` as `opts.preloaded_items` when opening the picker
     for the `#items > 1` branch.
   - Depends on: Phase 1
   - Risk: Medium — touches the async loader's streaming assumptions (`finder_done` currently
     comes from the callback; would need to default to `true` immediately when preloaded).

---

# Testing Strategy

- **Headless test**: `tests/test-finder-status.lua` (new) — mirror `tests/test-visibility.lua`'s
  structure exactly: defaults (`action == nil`), `start(label)` sets `action` and fires
  `BeastFinderStatusChanged` with the label, calling `start()` again updates the label without
  requiring `stop()` first, `stop()` clears `action` and fires the event once more, readonly-proxy
  assignment errors. Run: `nvim --clean --headless -l tests/test-finder-status.lua`.
- **Headless test**: extend or add a `preflight.lua` test with a fake source (`get(filter, cb)`
  that calls `cb(item)` N times then `cb(nil)` on a deferred callback) to verify: single item →
  `on_done` receives 1 item; a second `check()` call before the first's `cb(nil)` fires causes the
  first's `on_done` to never be called (generation supersession).
- **Bench**: `bench-finder-matcher.lua` is unaffected (pre-flight bypasses the matcher entirely
  for the single/zero-result cases) — run it anyway per `DEVELOPMENT.md`'s "before merging" step
  since `pipeline/match.lua` is touched (Phase 1 step 3).
- **Manual** (reference the PM spec's 6 scenarios directly — `docs/pm-specs/finder-auto-select.md`):
  1. In a buffer with an attached LSP client, place cursor on a symbol with exactly one
     definition, trigger go-to-definition — confirm no picker flash, cursor lands correctly
     (repeat 10+ times to rule out the old off-by-one-column bug reappearing intermittently).
  2. Trigger find-references on a symbol used in 3+ places — confirm picker opens normally,
     unchanged from current behavior.
  3. Simulate a slow LSP response (e.g. a large workspace on first request, or add a temporary
     artificial delay) with a single-result symbol — confirm `⠋ Definition…` appears in the
     statusline, then clears and jumps with no picker.
  4. Same slow-response setup with a multi-result symbol — confirm the indicator clears the
     instant the picker appears.
  5. Trigger go-to-definition on a symbol with no definition — confirm the existing warning
     notification appears, no picker, no lingering statusline indicator.
  6. Trigger go-to-definition, then immediately move the cursor and trigger it again before the
     first could plausibly resolve — confirm only the second symbol's result appears (jump or
     picker) and the statusline label reflects the second request throughout.

---

# Success Criteria

- [x] Single-result LSP jumps never render the picker UI, even briefly.
- [x] Multi-result and zero-result behavior is visually unchanged from today.
- [x] A statusline indicator (`⠋ <Action>…`) appears whenever a pre-flight check is slow enough
      to notice, and clears the instant it resolves.
- [x] The cursor no longer lands a column off from the target location on single-result jumps
      (the code path that caused it — `pipeline/match.lua`'s old auto-select branch — is removed,
      not patched).
- [x] `tests/test-finder-status.lua` passes.
- [x] `bench-finder-matcher.lua` still passes.
- [x] `stylua --check lua/beast/libs/finder/ lua/beast/libs/statusline/` is clean.

---

## Completed

**2026-08-08.** All 3 phases shipped, in order, each reviewed (`code-reviewer` agent) and verified
before commit.

**Deviation from this spec, made deliberately mid-implementation:** the shared status module was
built at `lua/beast/libs/finder/status.lua`, not the `lua/beast/finder_status.lua` top-level path
this spec describes throughout. Reasoning (from the user): finder is the *sole* writer of this
state — unlike `beast.visibility`, which has multiple independent writers (explorer, tabline) and
genuinely needs a neutral top-level home — so it belongs inside the finder lib. Finder only emits
`User BeastFinderStatusChanged`; it doesn't need to know or care who's listening. All references
to `beast.finder_status`/`lua/beast/finder_status.lua` above should be read as
`beast.libs.finder.status`/`lua/beast/libs/finder/status.lua`.

A second small deviation: `action.lua`'s `open_help`/`open_file`/`open_split`/`open_vsplit` were
refactored to take `win?: integer` directly instead of a full `Beast.Finder.State` (this spec's
Phase 1 step 2 originally called for reusing `open_file(state, item)` with a minimal
`{ main_win = win }` duck-typed table). That table literal tripped a real type-checker diagnostic
(`View.win.find_normal()` returns `integer?`, but `Beast.Finder.State.main_win` is a required
`integer` when the key is present) — rather than casting it away, the four leaf functions were
changed to accept the window id they actually use, which both fixed the diagnostic and removed the
need to fake up a partial `State` at all. `action.open(state, item)` still takes the full `state`,
since it also needs `state.query.source.name` to dispatch help/colorscheme handling.

Two tests beyond what this spec's Testing Strategy enumerated were added along the way:
`tests/test-preflight.lua` (Phase 1 — the spec called for it but didn't name the file) and
`tests/test-finder-preloaded-items.lua` (Phase 3 — verifies `source.get()` is skipped when items
are preloaded and still called exactly once when they aren't).

Commits (in order):
- `dcac35c` feat(finder): pre-flight LSP check before opening the picker
- `9a247e2` fix(finder): silence type-checker on preflight jump's minimal state table (superseded
  by the `c3ba587` refactor below — kept for history, not reverted)
- `c3ba587` refactor(finder): action open_* take a window id, not a full State
- `0e761cf` chore(finder): correct name (`open_picker` → `open_finder`, user's own commit)
- `8f70de4` feat(finder): statusline indicator for the pre-flight checking window
- `8276482` perf(finder): skip duplicate LSP fetch when pre-flight finds multiple results

Verification results:
- Phase 1: `tests/test-preflight.lua` 6/6 pass; `bench-finder-matcher.lua` PASS (full_scan ~17.5ms
  < 80ms, subset ~17ms < 50ms); `stylua --check` clean.
- Phase 2: `tests/test-finder-status.lua` 11/11 pass; `tests/test-preflight.lua` still 6/6;
  `bench-finder-matcher.lua` still PASS; `stylua --check` clean.
- Phase 3: `tests/test-finder-preloaded-items.lua` 4/4 pass; `tests/test-preflight.lua` and
  `tests/test-finder-status.lua` unaffected; `bench-finder-matcher.lua` still PASS; `stylua --check`
  clean.
- Codemap (`docs/CODEMAP/architecture.md`, `libraries.md`, `INDEX.md`) regenerated to reflect the
  new `preflight.lua`/`status.lua` files, the pre-flight control flow, and the new statusline
  component. Unrelated drift accumulated in other libs since the last full codemap generation
  (2026-08-02) — treesitter, mason, packer, tabline, theme — was **not** audited in this pass;
  it's out of scope for this spec and worth a dedicated `/update-codemap` run on its own.
