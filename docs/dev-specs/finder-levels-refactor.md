---
name: finder-levels-refactor
description: Refactor the finder into Session (windows) + Level (one search) with UI-free pipelines, behavior on the source, one key table, and a shared engine for the headless search - prerequisite for chained pickers
generated: 2026-11-15
---

> PM Spec: [docs/pm-specs/finder-continuous.md](../pm-specs/finder-continuous.md) (the motivating feature; this refactor itself has **no user-visible change**, apart from one bug fix called out in Phase 4)

# Summary
The finder's `State` is both "the set of windows" and "the current search", pipelines reach into that `State`, behavior is chosen by source *name* in five central files, key handling is written three times, and the explorer's headless search re-implements the engine. This refactor separates **Session** (windows, keys, autocmds) from **Level** (source + query + engine + prompt), makes the engines UI-free behind a small **host** interface, moves presentation/open/reload behavior onto the **source**, collapses the keymaps into one table, and makes `search.lua` a thin client of the same engine. After it, a chained picker is `session:push(Level)` and a new source is one file.

---

# Context

## Problem
Findings from reading the code (file:line at the time of writing):
1. `state.lua:56-97` builds windows, keymaps, `Query` and pipeline in one constructor; the input `on_change` closure captures the local `query` / `pipeline`. One window set can only ever show one search.
2. Pipelines read `state.query` at call time (`pipeline/match.lua:39,105,116`, `pipeline/stream.lua:30-31,61-63,93-104`) and call `ui.input.*` / `render.render(state)` directly. Swapping the query under a running search would let a late callback write into the wrong query; the engine cannot run without the UI.
3. Source behavior is dispatched by name: `render.lua:75-76` (`format[name]`, `format[name.."_header"]`), `render.lua:40` (`name:match("^lsp_")`), `action.lua:8-10`, `autocmds.lua:99`, `keymaps.lua:15`. The GitHub feature had to touch 12 core files outside its own.
4. The match pipeline is display-oriented: `matched` is a TopK(1000), no total count, no accessor for the full set.
5. Enter / `<C-s>` / `<C-v>` are written once per pane (`keymaps.lua` input, list, preview); copies already drifted (list-pane `<C-v>` calls `open_split`).
6. `search.lua` (headless, used by the explorer) re-implements load + score + generation guard because the pipelines are not usable without a `State`.
7. Two singletons (`init.lua:state`, `state.lua:instance`) and only four tests that open a real finder; none cover reset / reopen / reentrancy.

### Solution
```
Session (one, singleton)                Level (one per search; a stack of them)
 windows: input, list, preview,          source, query (items, matched, total, filter)
          backdrop                        engine (match | stream) + host
 keys, autocmds, picker opts             prompt text, title, count, cursor, offset
 level  -> current Level                 start() run() reload() stop()
 stack  -> parent Levels
 push(level) / pop()

Engine (pipeline)  - UI-free:  start/run/reload/abort/matches(query, host)
Host (interface)   - what an engine may tell its owner: alive, render, busy, count, title, rows
Source             - owns get + format + header + group + open + preview + reload_on
```
No behavior changes; each phase leaves the finder working and the suite green.

---

# Research

### Repo Search
- Searched for: `state.query|state.view|state.pipeline` (27 uses in `keymaps.lua`, 26 `render.lua`, 24 `pipeline/stream.lua`, 16 `autocmds.lua`, 15 `pipeline/match.lua`), `source.name|.name ==|format[`, `highlight_preview`, `initial_query|initial_text|preloaded_items|on_preview|on_close|freeze_colors`, `finder.search` consumers, `finder.open` callers, existing finder tests, `lua/beast/libs/finder/docs/`.
- Found:
  - Name dispatch: `render.lua:40,75,76`, `action.lua:8,10`, `autocmds.lua:99`, `keymaps.lua:15`.
  - Callers of `finder.open`: `init.lua` keys (`files`, `buffers`, `live_grep`, `help_tags`, `gh_pr`, `gh_issue`, `colorschemes` with `preview=false, layout="cards", separators, backdrop=false, freeze_colors, initial_text, on_preview, on_close`) and LSP keymaps (`auto_select` through `preflight.lua`).
  - `search.lua` is used only by `libs/explorer/search/init.lua:119` (`files({cwd})`, `query`, `refresh`, `close`; reports only final scored results, with `{capped, loading}`), covered by `tests/test-explorer-search.lua` (47 assertions) and `scripts/bench-explorer.lua`.
  - Existing precedent: `docs/pm-specs/finder-query-split.md` (earlier split of query into pipelines) and `lua/beast/libs/finder/docs/pipeline-overhaul.md` (scoring/queue/async design the engines keep).
  - Per-query registries in both pipelines are keyed by `query` (weak tables): several queries can coexist - the engines are closer to "level-ready" than `State` is.
  - Per-source module state: `live_grep` (`M.cmd`, `current_procs`, `building`), `colorscheme_swatches` (`running`); gh sources are closure-per-`create` (the pattern to follow).
  - Tests that open a real finder: `test-finder-gh-keys.lua`, `test-finder-input-initial.lua`, `test-finder-stream-retain.lua`, `test-explorer-search.lua` (each re-declares the same global stubs).
- Reuse opportunity: Yes - existing engines, `Query`, `Filter`, `matcher`, `TopK`, `initial_query` echo skip, gh factory pattern, `Util.debounce`, test boilerplate (extracted into a helper).

### Built-in / Existing Lib Check
- Checked: `libs/view` (buffers/windows), `libs/async` (`Task:running()`), `vim.keymap.set`, `vim.api.nvim_create_autocmd`, `maparg(..., dict).callback` for driving mappings in tests.
- Found: everything needed exists; no new dependency.
- Decision: **Reuse** engines, `Query`, `Filter`, views; **Build** Session, Level, host contract, results fields, source contract + normalizer, key table, test helper.

---

# Architecture Changes
- `lua/beast/libs/finder/state.lua` -> `session.lua` (renamed, slimmed): windows, keys, autocmds, picker opts, `level`, `stack`, `push/pop`. Type `Beast.Finder.State` -> `Beast.Finder.Session` (mechanical rename in all annotations).
- `lua/beast/libs/finder/level.lua` - **new**: one search (source, query, engine, prompt, title, count, cursor, offset).
- `lua/beast/libs/finder/host.lua` - **new**: type `Beast.Finder.Host` + `headless()` helper.
- `lua/beast/libs/finder/pipeline/match.lua`, `pipeline/stream.lua`, `pipeline/init.lua` - modified: `(query, host)` API, captured query, staleness checks, `matches`, results fields.
- `lua/beast/libs/finder/query.lua` - modified: `limit`, `loading`, `matching`, `total`; drop `highlight_preview`.
- `lua/beast/libs/finder/matcher.lua` - modified: `MatchState.total`.
- `lua/beast/libs/finder/source/init.lua` - modified: contract types + `normalize()` defaults.
- `lua/beast/libs/finder/source/{files,buffers,help_tags,colorschemes,live_grep/init,lsp,gh}.lua` - modified: declare `format`, `header`, `group`, `open`, `preview_highlight`, `reload_on` as needed.
- `lua/beast/libs/finder/render.lua`, `action.lua`, `autocmds.lua`, `keymaps.lua`, `ui/list.lua`, `init.lua` - modified: use `session.level` and source methods; no name dispatch.
- `lua/beast/libs/finder/keymaps.lua` - rewritten as one action table mounted on three panes.
- `lua/beast/libs/finder/search.lua` - rewritten on top of the match engine with a headless host.
- `tests/helpers/finder.lua` - **new** harness; new tests `tests/test-finder-*.lua` per phase.
- `docs/CODEMAP/libraries.md`, `INDEX.md`, finder section - updated in the last phase.

---

# Intended Usage (pseudo code)

> Pseudo code, not final. Names and shapes are what we align on.

## 1. Source contract (R3) - a source is one file

```lua
---@class Beast.Finder.ASource
-- data
name, live, async, auto_select, label                          -- unchanged
get(filter, cb)  cancel?()  check?()                           -- unchanged
initial_query?  retain_results?  run_when_empty?  debounce_ms?
title?(filter)  count?(items)  preview?(view, item)            -- unchanged opt-ins
-- NEW: presentation
format(item, width)  -> Highlight[]        -- default: format.filename
header?(item, width) -> Highlight[]        -- grouped lists (grep, LSP); replaces format[name .. "_header"]
group?(item)         -> any                -- rows with the same value share one header; default item.file
preview_highlight?   -> "match" | "range"  -- replaces query.highlight_preview + name:match("^lsp_")
-- NEW: behavior
open(session, item)                        -- default: item.url and open_url or open_file
reload_on?  -> string[]                    -- User events that re-run it; default { "BeastVisibilityChanged" }
```

```lua
-- source/help_tags.lua  (after)
local format, action = require("beast.libs.finder.format"), require("beast.libs.finder.action")
local M = {}
M.format = format.help_tags
function M.open(session, item) action.open_help(session.main_win, item) end
function M.get() ... end            -- unchanged
return M

-- source/colorschemes.lua  (after)
M.format = format.colorschemes
M.reload_on = { "BeastFinderSwatchesReady" }
function M.open(_, item) if vim.g.colors_name ~= item.text then pcall(vim.cmd.colorscheme, item.text) end end

-- source/live_grep/init.lua  (after)
M.format, M.header, M.preview_highlight = format.live_grep, format.live_grep_header, "match"

-- source/init.lua: normalize(mod) after require fills defaults
mod.name        = k
mod.format      = mod.format or format.filename
mod.open        = mod.open   or default_open        -- url -> open_url, else open_file
mod.reload_on   = mod.reload_on or { "BeastVisibilityChanged" }
```
Central files then never look at `source.name` (gate: `grep -rn 'source\.name' finder/` only hits `source/init.lua`).

## 2. Engine + host (R2) - pipelines without a UI

```lua
---@class Beast.Finder.Host
alive() -> boolean       -- false once its level is stopped / not shown: engines drop late work
render()                 -- query.matched changed
busy(on)                 -- spinner
count(text?)             -- prompt count label
title(text)              -- prompt title
rows() -> integer        -- visible list rows (stream render budget)

-- engine interface, same for match and stream
engine = source.live and pipeline.stream or pipeline.match
engine.start(query, host)     -- match: load items; stream: run once if source.initial_query
engine.run(query, host)       -- prompt changed
engine.reload(query, host)    -- source data changed
engine.abort(query)
engine.matches(query)         -- full match set, nil while still working   (NEW: not just the top 1000)

-- results state on the query (written by the engine, read by anyone)
query.items        -- everything the source produced
query.matched      -- what the list shows (top `query.limit`, default 1000)
query.total        -- how many items match (NEW)
query.loading      -- source still delivering (NEW)
query.matching     -- scorer still running (NEW)

-- inside an engine every deferred callback captures its own query and checks the host
local function stale(s) return s.aborted or not host.alive() end
vim.schedule(function() if stale(s) then return end; query.matched = ...; host.render() end)
```

## 3. Session and Level (R1)

```lua
-- level.lua: one search, no windows
local level = Level.new("live_grep", {
  cwd = root, preloaded_items = nil, files = nil,          -- level-scoped opts
  title = "Live grep",
})
level.source, level.query, level.engine                    -- fixed at creation
level.text, level.cursor, level.offset, level.title        -- what a stack must restore
level:start(host)   level:run(text, host)   level:reload(host)   level:stop()

-- session.lua: windows + keys + autocmds; owns the stack
local session = Session.open("files", { preview = true, layout = nil,
                                        on_preview = fn, on_close = fn, initial_text = "init" })
session.level                 -- current Level (state.query -> session.level.query)
session:push(Level.new("live_grep", { files = paths }))   -- save current, attach new in the SAME windows
session:pop()                 -- stop child, restore parent exactly (prompt, cursor, offset), no search
session:close()               -- one place: aborts every level in the stack, closes windows

-- how a level is bound to the windows (the staleness guard lives here)
function Session:attach(level)
  self.level = level
  local host = {
    alive  = function() return self.level == level and not self.closed end,
    render = function() if self.level == level then render.render(self) end end,
    busy   = function(on) if self.level == level then (on and ui.input.start_spinner or ui.input.stop_spinner)(self.view.input) end end,
    count  = function(t) if self.level == level then ui.input.set_count(self.view.input, t) end end,
    title  = function(t) if self.level == level then ui.input.set_title(self.view.input, t) end end,
    rows   = function() return self.view.list._win_height end,
  }
  level.host = host
  ui.input.set_text(self.view.input, level.text)           -- echo-skipped, no double search
  level:start(host)
end
```

## 4. Key table (R4)

```lua
-- keymaps.lua: written once
local actions = {
  down = function(s) s:move(1) end,           up = function(s) s:move(-1) end,
  confirm = function(s) s:confirm() end,      split = function(s) s:open_in("split") end,
  vsplit  = function(s) s:open_in("vsplit") end,   copy = function(s) s:copy() end,
  close = function(s) s:close() end,          focus_input = ..., focus_preview = ...,
}
local common = {
  { "<C-j>", "down" }, { "<C-k>", "up" }, { "<C-n>", "down" }, { "<C-p>", "up" }, { "<Down>", "down" }, { "<Up>", "up" },
  { "<Tab>", "down" }, { "<S-Tab>", "up" }, { "<CR>", "confirm" }, { "<C-s>", "split" }, { "<C-v>", "vsplit" },
  { "<C-y>", "copy" }, { "<C-c>", "close" }, { "<Esc>", "close", modes = { "n" } },
}
local panes = {
  input   = { modes = { "i", "n" }, extra = { { "<C-h>", "noop" }, { "<C-l>", "focus_preview" } } },
  list    = { modes = { "n" },      extra = { { "<C-h>", "focus_input" }, { "<C-l>", "focus_preview" } }, redirect_printable = true },
  preview = { modes = { "n" },      extra = { { "<C-h>", "focus_input" }, { "<C-l>", "noop" } },         redirect_printable = true },
}
function M.mount(session) for pane, spec in pairs(panes) do bind(session.view[pane].buf, spec, common, actions) end end
-- a new key (e.g. <C-g>) is one line in `common` and works from every pane
```

## 4b. Headless search on the same engine (R5)

```lua
-- search.lua (explorer client) after the refactor
function M.files(opts)
  local query = Query(sources.files, { cwd = opts.cwd, limit = (opts.limit or 1000) + 1 })
  local self  = { query = query, closed = false }
  local host  = { alive = function() return not self.closed end,
                  render = function()
                    if self.cb and not query.matching then       -- only final scored results
                      local matched, capped = trim(query.matched, limit)
                      self.cb(matched, { capped = capped, loading = query.loading })
                    end
                  end,
                  busy = noop, count = noop, title = noop, rows = function() return 1 end }
  match.start(query, host)
  function self:query(pattern, cb) query.filter:update(pattern); self.cb = cb; match.run(query, host) end
  function self:refresh() match.reload(query, host) end
  function self:close() self.closed = true; match.abort(query) end
  return self
end
-- explorer code is unchanged: files({cwd}), :query, :refresh, :close
```

---

## Implementation Phases

Each phase is mergeable on its own: finder behavior unchanged, whole test suite green, stylua and luals clean. Order matters (R2 and R3 are used by R1).

## Phase 0: Safety net (R0) - characterize today's behavior before touching it
1. **Test helper** (File: `tests/helpers/finder.lua`)
   - Action: one place for the boilerplate every finder test repeats (rtp, `Util`, `View`, `Theme`, `Toast` capture, stubbed `beast` and the grep index), plus `fake_source{ name, live, async, items | get }`, `open(name, opts)`, `press(session, lhs, mode?)` (calls the mapping's callback via `maparg(..., true, true)`), `rows(session)`, `wait(cond, ms)`, `windows()` (valid finder windows).
   - Why: refactoring without a harness is guesswork; later phases reuse it.
   - Depends on: None. Risk: Low
2. **Lifecycle tests** (File: `tests/test-finder-lifecycle.lua`)
   - Action: open twice leaves one window set; close is idempotent; `WinEnter` outside closes; reentrant `open()` from `on_close`; `confirmed` flag and `on_close(confirmed)`; `initial_text` selects the matching row; `Esc` closes; backdrop/preview options.
   - Risk: Low
3. **Engine tests** (File: `tests/test-finder-engines.lua`)
   - Action: match: async load + typing filters + subset narrowing + abort; stream: run per keystroke, `retain_results`, `run_when_empty`, cancelled-run callbacks dropped; both through the real `State` for now.
   - Risk: Low
4. **Behavior tests** (Files: `tests/test-finder-keys.lua`, `tests/test-finder-source-behavior.lua`)
   - Action: key matrix per pane (current behavior, including the list-pane `<C-v>` -> split, marked "fixed in Phase 4"); per source: row formatting, header grouping for grep/LSP, open dispatch for files/help/colorscheme/url, preview hook calls (selected item, nil on empty), colorscheme picker options (`on_preview`, `on_close`, `freeze_colors`, `initial_text`), visibility event reload.
   - Risk: Low
5. **Baselines** - record `scripts/bench-finder-matcher.lua`, `scripts/bench-explorer.lua` and `scripts/bench-ux.sh all` numbers on the starting commit (baseline worktree).
   - Risk: Low

## Phase 1: Engines without a UI (R2)
1. **Results fields** (Files: `query.lua`, `matcher.lua`)
   - Action: `Query` gets `limit` (TopK capacity, default `1000`), `loading`, `matching`, `total`; `MatchState.total` counted in the final pass (empty pattern: `#items`); keep `highlight_preview` for now (its three uses, in `keymaps.lua`, and twice in `render.lua`, move to source fields in Phase 2, where it is removed).
   - Risk: Medium (matcher hot path: O(1) counter only)
2. **Host contract** (File: `host.lua`)
   - Action: the `Beast.Finder.Host` type and a `headless(overrides)` constructor with no-op methods.
   - Risk: Low
3. **Match engine** (File: `pipeline/match.lua`)
   - Action: public API `start/run/reload/abort/matches(query, host)`; replace every `state.query` with the captured `query`; all UI calls go through `host`; per-query `s.aborted` + `host.alive()` checks in every `vim.schedule`/coroutine tail; `matches(query)` returns `query.items` for an empty pattern, else items with `scores[idx] > 0`, nil while `loading or matching`; TopK capacity from `query.limit`.
   - Why: late callbacks of a replaced search become no-ops; the engine runs headless.
   - Also fix (found by the Phase 0 engine test): while an async source is open but idle, the loader does a bare `coroutine.yield()` without `suspend()`, so it busy-spins and re-renders every loop tick (starves the event loop; a slow `fd` run does the same). The loader must `suspend()` when it has nothing to do and be resumed by the source callback.
   - Depends on: Steps 1-2. Risk: High (hot path, async)
4. **Stream engine** (File: `pipeline/stream.lua`)
   - Action: same API; `host.busy/count/title/rows` replace direct `ui.input` / `state.view.list` access; `run_id` guard kept and combined with `host.alive()`; `matches(query)` = `query.items` when settled.
   - Depends on: Steps 1-2. Risk: High
5. **Adapt `State`** (File: `state.lua`, still the old class)
   - Action: `State` builds a host from its own views and passes `(query, host)`; no other behavior change.
   - Depends on: Steps 3-4. Risk: Medium
6. **Tests** (File: `tests/test-finder-host.lua` new, existing suite)
   - Action: engines with `host.headless()`: results fields, `matches` beyond 1000, late callback after `host.alive() == false` changes nothing, abort mid-load, `limit`; all Phase 0 tests unchanged and green.
   - Risk: Low

## Phase 2: Behavior on the source (R3) - migrate every source
1. **Contract + normalizer** (File: `source/init.lua`)
   - Action: document the new fields; `normalize(mod, name)` fills `name`, `format`, `open`, `reload_on`, `group` defaults (gh and lsp factories are normalized too).
   - Risk: Low
2. **Migrate all sources** (Files: `source/files.lua`, `buffers.lua`, `help_tags.lua`, `colorschemes.lua`, `live_grep/init.lua`, `lsp.lua`, `gh.lua`)
   - Action: each declares what it needs per the pseudo code (`format`, `header`, `preview_highlight`, `open`, `reload_on`). `format.lua` stays the library of formatters; `<name>_header` aliases and the `lsp_*` alias block go away.
   - Risk: Medium
3. **Remove name dispatch** (Files: `render.lua`, `action.lua`, `autocmds.lua`, `keymaps.lua`, `ui/list.lua`)
   - Action: `render` uses `source.format/header/preview_highlight`; `action.open(session, item)` calls `source.open`; `autocmds` reload only when the event is in `source.reload_on`; `keymaps.move_cursor` takes the format function from the render helper; `list` groups by `source.group` (default `item.file`).
   - Depends on: Steps 1-2. Risk: Medium
4. **Tests** (File: `tests/test-finder-source-contract.lua`)
   - Action: table-driven over every registered source: normalized fields present, `format(item, width)` returns highlights for a sample item, `open` defaults, grouping, `reload_on`; static gate: no `source.name ==`, `.name:match`, `format[` outside `source/init.lua`.
   - Risk: Low

## Phase 3: Session + Level (R1)
1. **Level** (File: `level.lua`)
   - Action: per pseudo code; holds source, query, engine, prompt text, title, cursor, offset; `start/run/reload/stop`.
   - Depends on: Phases 1-2. Risk: Medium
2. **Session** (File: `session.lua`, replaces `state.lua`)
   - Action: windows, backdrop, picker opts (`on_preview`, `on_close`, `layout`, `frozen`, `initial_text`, `main_win`, `confirmed`), single singleton (`init.lua`'s `state` removed), `attach(level)`, `push/pop`, `close` aborting every level, the reentrancy guard moved as-is; input `on_change` goes through `session.level`.
   - Why: the one place where windows and levels meet; `push/pop` is the only new capability and is not bound to any key.
   - Depends on: Step 1. Risk: High (singleton lifecycle)
3. **Mechanical rename** (all finder files)
   - Action: `Beast.Finder.State` -> `Beast.Finder.Session`; `state.query` -> `session.level.query`; `require("...state")` -> `session`; update `init.lua` open path (`preflight`/`preloaded_items` handled as level opts).
   - Risk: Low
4. **`ui/input.lua`** - add `set_text(view, text)` (uses the existing echo-skip so a programmatic write does not search twice).
   - Risk: Low
5. **Tests** (File: `tests/test-finder-session.lua`)
   - Action: `push` swaps in the same windows (same win ids, backdrop untouched), `pop` restores prompt/cursor/offset/results with no source call, late callbacks of a popped level are ignored, `close` aborts the whole stack, reopen after close; the whole Phase 0 suite stays green.
   - Risk: Medium

## Phase 4: One key table (R4)
1. **Rewrite `keymaps.lua`** per pseudo code (actions + common bindings + per-pane extras, printable-char redirect for list/preview).
   - Behavior change (bug fix): the list-pane `<C-v>` now opens a vertical split like the other two panes; the Phase 0 test asserting the old behavior is updated and noted in the commit.
   - Depends on: Phase 3. Risk: Medium
2. **Tests** (File: `tests/test-finder-keys.lua` updated): the same matrix passes on all three panes.
   - Risk: Low

## Phase 5: Headless search on the engine (R5)
1. **Rewrite `search.lua`** per pseudo code (explorer API unchanged: `available`, `files`, `:query`, `:refresh`, `:close`); delete the duplicated load/score/generation code.
   - Depends on: Phase 1. Risk: Medium
2. **Verify**: `tests/test-explorer-search.lua` (47 assertions) unchanged and green; `scripts/bench-explorer.lua` equal to baseline within noise; manual: explorer search mode on a large repo (typing, hidden/gitignored toggle refresh, close).
   - Risk: Medium (final-result-only reporting and `capped`/`loading` semantics must match)

## Phase 6: Docs and wrap-up
1. Update `docs/CODEMAP/libraries.md` and `INDEX.md` (finder section: Session/Level/host/engine/source contract/key table), remove the stale `state.lua` description, note the refactor in `lua/beast/libs/finder/docs/`.
2. Update `docs/dev-specs/finder-continuous.md`: its "Phase 2 chain core" shrinks to scoped grep, hint window, keys and the `drill` field because Session/Level, host, results and the key table now exist.
3. Final verification (below).

# Testing Strategy
- Headless: Phase 0 suite first and unchanged after every phase (`tests/test-finder-*.lua`, `tests/test-explorer-search.lua`, `tests/test-preflight*`); new tests per phase listed above; stylua (`stylua --check lua/ tests/`) and luals as in `DEVELOPMENT.md`.
- Bench: `bench-finder-matcher.lua` (Phase 1: counter and captured-query changes sit on the hot path), `bench-explorer.lua` (Phase 5), `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all` at the end, each against the Phase 0 baseline.
- Manual (real wezterm pane, `NVIM_APPNAME=BeastVim`), after each phase that touches runtime: `<leader>f` (type, Enter, `<C-s>`, `<C-v>`, Esc), `<leader>b`, `<leader>F` (grouped grep, preview highlight), `<leader>h` (open help), `<leader>c` (colorscheme cards: live preview, Esc restores, Enter keeps), LSP definitions/references (auto-select and picker), `<leader>ghp`/`<leader>ghi`, explorer search mode, hidden/gitignored toggle while a picker is open, terminal resize.
- Not testable headless (reported at the end): pixel-level look in wezterm beyond the manual pass.

# Success Criteria
- [ ] The finder looks and behaves exactly as before in every manual check above; the only difference is `<C-v>` in the list pane opening a vertical split.
- [ ] Whole existing test suite plus the new tests pass; stylua and luals clean.
- [ ] `grep -rn 'source\.name' lua/beast/libs/finder` only matches `source/init.lua`; no `format[<name>]` lookups remain.
- [ ] Engines run without `ui` (tests with `host.headless()`); a late callback of a stopped level changes nothing.
- [ ] `engine.matches(query)` returns the full match set (not capped at 1000) and `query.total` is correct.
- [ ] `session:push(level)` / `pop()` swap levels in the same windows (same window ids) and restore prompt, cursor, offset and results with no source call; no key is bound to them yet.
- [ ] One key table drives input, list and preview panes; adding a key is one line.
- [ ] `search.lua` contains no private copy of the load/score loop; explorer search tests and bench unchanged.
- [ ] `bench-finder-matcher`, `bench-explorer` and `bench-ux.sh all` are within noise of the Phase 0 baseline.
- [ ] A new source needs no edit outside its own file (verified by writing the fake source in `tests/helpers/finder.lua` with every behavior declared on the source).

# Risks and notes
- **Hot path (Phase 1):** keep the counter O(1); compare `bench-finder-matcher` before/after.
- **Known pre-existing bugs found by the Phase 0 tests:** (1) the match loader spins while an async source is open and idle (fixed in Phase 1); (2) opening a picker from `on_close` is closed again by the first picker's window teardown and raises E367 (shared autocmd group name; each Session gets its own group in Phase 3).
- **Singleton lifecycle (Phase 3):** the reentrancy guard from `reset()` (commit `ef31ad3` on the `new-input-ui` branch is the same fix) must be preserved; Phase 0 lifecycle tests exist for it.
- **R5 semantics:** explorer relies on "only final scored results" and `{capped, loading}`; covered by `test-explorer-search.lua`.
- **Scope guard:** no new user feature; `push/pop` exist but are unbound. The chain feature (`docs/dev-specs/finder-continuous.md`) is rebased onto this refactor after Phase 6.
