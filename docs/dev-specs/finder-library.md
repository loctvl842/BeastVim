# Dev Spec: Finder Library

## Summary

Build `lua/beast/libs/finder/` — a pure-Lua fuzzy picker that lives entirely inside Neovim,
with no mandatory external binary. It presents three floating windows (input prompt, scrollable
results list, file preview), scores items with a port of fzf's boundary-bonus algorithm, and
drives async work with a lightweight `uv.new_check()` coroutine executor. Architecture borrows
the correct ideas from **snacks.nvim** (structured items, Filter/Matcher separation, async
cooperative scheduling, `format → Highlight[]` pipeline) while discarding its complexity
(layout engine, MinHeap top-k, frecency persistence, per-picker autocmd forests). fzf-lua's
architecture — terminal buffer + external binary + ANSI strings — is deliberately not adopted.

## Research

### Repo Search

- Searched for: `picker`, `finder`, `fzf`, `fuzzy`, `snacks`
  (`git grep -niE 'picker|finder|fzf|fuzzy|snacks' lua/beast/`)
- Found in **BeastVim**: `beast/libs/packer/triggers/module.lua` uses `fzf` only as a string
  literal in comments; `beast/plugins/bars/init.lua` has no picker references. No existing
  picker/finder code in BeastVim.
- Reuse opportunity:
  - `Beast.View` (`beast/libs/view.lua`) — **Adopt**: all three UI windows (input, list,
    preview) must subclass this. `is_valid()` + `close()` come for free.
  - `Util.create_scratch_buf(filetype)` (`beast/util/init.lua`) — **Adopt**: list and preview
    windows both need scratch buffers. This is the already-extracted helper.
  - `Util.wo(win, k, v)` — **Adopt**: version-safe window option setter; use for all
    `wo.*` mutations in the three view files.
  - `Palette` — **Adopt**: `BeastFinder*` highlight groups resolve colors through
    `Palette.get()` + `Util.colors.set_hl`, exactly as every other lib's `highlights.lua`.
  - `animate.lua` — **Skip**: finder windows open/close without animation; the extra cost
    is not justified (no slide-in, no fade).

### External Research — snacks.nvim Picker

- Read: `core/picker.lua`, `core/finder.lua`, `core/matcher.lua`, `core/filter.lua`,
  `core/list.lua`, `core/input.lua`, `core/preview.lua`, `source/files.lua`, `format.lua`
- Key findings:
  - **Item shape**: Structured Lua table `{idx, score, text, file?, buf?, pos?, cwd?, ...}`.
    Never serialized, always in-memory — correct for BeastVim.
  - **Filter/Matcher split**: `Filter` holds what the user typed + search context (cwd, buf);
    `Matcher` scores items asynchronously against the filter. These are deliberately separate.
  - **Async kernel**: `uv.new_check()` executor fires on every libuv tick; processes all
    active coroutines up to a 10ms wall-clock budget; stops itself when queue is empty.
    Finder and Matcher are separate coroutines signaling each other.
  - **Format pipeline**: `fun(item, picker) → Highlight[]` where
    `Highlight = {text, hl_group?}`. Written to buffer via `nvim_buf_set_lines` + extmarks.
  - **Input throttle**: `TextChangedI` → 30ms debounce (200ms for live/reload sources).
  - **Skipped**: MinHeap top-k optimization, frecency JSON persistence, `Snacks.layout`
    box-layout engine, per-picker autocmd instance handlers.
- Decision: **Adopt patterns, build simplified implementation** (~800–1200 LOC target vs
  snacks.nvim's ~12,700 LOC).

### External Research — fzf-lua

- Read: `core.lua` (top-level), `win.lua` (FzfWin singleton), `providers/files.lua`,
  `make_entry.lua`
- Key findings:
  - Architecture is `terminal buffer + fzf subprocess`. All matching/display/keys happen
    inside fzf's C TUI. Neovim only receives the final selected string on exit.
  - Items are ANSI-coded strings with `U+00A0` field separator. No structured data — decode
    happens on selection by stripping ANSI and splitting on separator.
  - `fzf` binary is **mandatory**. `fd`/`rg`/`bat`/`git`/`tmux` are all expected.
  - One Neovim window (terminal) + one optional preview float. Input and list are fzf's
    own TUI panels, not Neovim windows — cannot use `Beast.View`.
- Decision: **Skip entirely**. The architecture is incompatible with BeastVim conventions
  at every level (binary dependency, untyped items, no View subclasses, no Lua async).

### Package Search — Neovim Native APIs

- `vim.api.nvim_open_win` — for the three floating windows. No plugin needed.
- `vim.api.nvim_buf_set_lines` + `nvim_buf_set_extmark` — for list rendering with highlights.
- `vim.fn.prompt_setprompt` + `buftype=prompt` — for the input window (same as snacks.nvim).
- `vim.uv.new_check()` + `vim.uv.hrtime()` — for the coroutine executor (already used by
  `Util.hrtime()`).
- `vim.uv.spawn` — for `files` and `grep` sources (fd/rg/find).
- Decision: **Use native** throughout. No new plugin dependency.

## Requirements

### Functional

- Single entry point: `Finder.open(source, opts?)` opens the three-window picker.
- **Input window**: floating prompt (`buftype=prompt`). User types to filter. Debounced
  `TextChangedI` triggers re-match (30ms normal, 200ms live-grep sources).
- **List window**: floating scratch buffer. Displays `Item[]` sorted by `score` desc. Arrow
  keys move cursor; `<Enter>` confirms selection and calls the configured action.
- **Preview window**: floating scratch buffer. Updates on cursor move (60ms debounce) by
  reading `item.file` (or `item.buf`) and rendering content with Neovim syntax highlighting.
- **Fuzzy matching**: fzf-compatible scoring — boundary bonuses (`/`, `_`, `-`, camelCase),
  gap penalties, first-char bonus ×2, forward+backward scan for tightest window.
- **Pattern syntax**: space-separated AND terms, `|` OR, `!` inverse, `^` prefix, `$` suffix,
  `'` exact. No field-targeting in v1.
- **Multi-selection**: `<Tab>` toggles items; `<S-Tab>` toggles and moves cursor. Selected
  items are passed as a list to the action on confirm.
- **Keymaps** (in input window):
  - `<C-j>` / `<C-k>` or `<Down>` / `<Up>`: move cursor in list
  - `<Enter>`: confirm with current item (or all selected if multi)
  - `<Esc>` / `<C-c>`: close picker
  - `<C-p>`: toggle preview
  - `<Tab>` / `<S-Tab>`: multi-select toggle
- **Built-in sources**: `files`, `buffers`. Each is a function returning `Item[]` or an async
  coroutine function.
- **`vim.ui.select` override**: replace built-in `vim.ui.select` with the finder's list window
  (no preview, single-select). Respects `opts.prompt` and `opts.format_item`.
- Config-driven: `Finder.setup(opts)` deep-merges into a read-only-by-metatable config.
- Highlight groups: `BeastFinder*` resolved through `Palette` + `Util.colors.set_hl`,
  refreshed via `M.highlight_modules` registration.

### Non-Functional

- Picker open-to-visible latency: < 20ms for sources returning ≤ 5000 items synchronously.
- Matcher throughput: ≥ 50,000 items/sec on a single-core budget slice.
- No external binary required for `buffers` source. `files` source tries `fd` → `rg` → `find`.
- No mandatory plugin dependency beyond BeastVim's own `beast.libs.*` modules.
- Follow AGENTS.md conventions: state only in `init.lua`, single augroup via
  `ensure_autocmds()`, `Beast.View` subclasses for all windows, read-only config metatable.

### Out of Scope (v1)

- Field-targeted matching (`name:foo`, `file:bar`)
- Frecency scoring (score_add hook is the extension point for later)
- Resume last picker
- Layout cycling on window resize (positions recomputed on each `open()`)
- Live-grep source (needs `fn_reload` pattern — Phase 4 spec)
- Preview for non-file items (buffers source shows buffer content; no LSP hover, no diff)
- Marks, registers, command history sources

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/init.lua` | **Create** | Public API: `open`, `close`, `setup`, module-level state, `vim.ui.select` override |
| `lua/beast/libs/finder/config.lua` | **Create** | Defaults, live `cfg`, `setup(opts)`, read-only metatable |
| `lua/beast/libs/finder/async.lua` | **Create** | Lightweight `uv.new_check()` coroutine executor (≤ 100 LOC) |
| `lua/beast/libs/finder/filter.lua` | **Create** | `Filter` factory — holds pattern, search, cwd, buf |
| `lua/beast/libs/finder/matcher.lua` | **Create** | Fuzzy scorer: fzf boundary-bonus algorithm, coroutine-based |
| `lua/beast/libs/finder/format.lua` | **Create** | Built-in format functions → `Highlight[]`; filename, icon, buffer |
| `lua/beast/libs/finder/picker.lua` | **Create** | `Picker` class: orchestrates filter→finder→matcher→list→preview pipeline |
| `lua/beast/libs/finder/actions.lua` | **Create** | Built-in action handlers (open file, open split, open vsplit, copy path) |
| `lua/beast/libs/finder/ui/input.lua` | **Create** | `Beast.Finder.InputView : Beast.View` — prompt window |
| `lua/beast/libs/finder/ui/list.lua` | **Create** | `Beast.Finder.ListView : Beast.View` — results window |
| `lua/beast/libs/finder/ui/preview.lua` | **Create** | `Beast.Finder.PreviewView : Beast.View` — preview window |
| `lua/beast/libs/finder/sources/files.lua` | **Create** | File-system source (fd → rg → find fallback chain) |
| `lua/beast/libs/finder/sources/buffers.lua` | **Create** | Listed buffer source (pure Lua, no shell) |
| `lua/beast/libs/finder/highlights.lua` | **Create** | `BeastFinder*` highlight groups via Palette |
| `lua/beast/init.lua` | **Modify** | Register `Finder` global, wire `packer.lazy` trigger, `highlight_modules` |

## Implementation Phases

### Phase 1: Core Engine — async + filter + matcher (no UI)

Goal: the matching pipeline works and is unit-testable in isolation.

1. **Create `async.lua`** (File: `lua/beast/libs/finder/async.lua`)
   - Action: `M.spawn(fn)` — wraps `fn` in a coroutine and adds to `_active` queue;
     starts `uv.new_check()` executor if not running. `M.yielder(ms)` — returns a closure
     that yields the coroutine if > `ms` ms elapsed (checked every 100 iterations).
     Budget: 10ms per executor tick. Queue: plain array, processed front-to-back.
   - Why: All finder sources and the matcher run as cooperating coroutines. Must exist
     before matcher or sources can be written.
   - Depends on: None
   - Risk: Low — the pattern is well-understood from snacks.nvim's `util/async.lua`.

2. **Create `filter.lua`** (File: `lua/beast/libs/finder/filter.lua`)
   - Action: `M.new(opts)` returns a `Beast.Finder.Filter` table:
     `{ pattern="", search="", cwd=vim.fn.getcwd(), buf=nil }`.
     `M.update(filter, pattern)` sets `filter.pattern`. Pure data, no methods.
   - Why: Decouples "what the user typed" from both the source and the scorer.
   - Depends on: None
   - Risk: Low

3. **Create `matcher.lua`** (File: `lua/beast/libs/finder/matcher.lua`)
   - Action: Implement `M.score(item, filter) → number` — fzf boundary-bonus algorithm:
     - Parse `filter.pattern` into AND-groups (space-split), OR-terms (`|`), modifiers
       (`!`, `^`, `$`, `'`).
     - For each term: forward scan finds first match positions; backward scan from each end
       position finds tightest window; score = `16 × match_count - 3 × gap_start
       - 1 × gap_extension + bonuses`. Boundary bonus: `+8` for `/`, `_`, `-` predecessor;
       first-char ×2. Inverse terms score 1000 if no match.
     - Returns `0` if any AND-group has no matching OR-term (item is excluded).
     - `M.run(items, filter, on_done)` — spawns via `async.spawn`; iterates `items`,
       sets `item.score = M.score(item, filter)`, yields every 100 items. Calls
       `on_done(matched_items)` when complete, where `matched_items` is items with score > 0,
       sorted by score desc.
   - Why: The heart of the picker. Phase 1 so it can be tested without any UI.
   - Depends on: Step 1 (`async.lua`), Step 2 (`filter.lua`)
   - Risk: Medium — scoring algorithm has subtle edge cases (empty pattern = match all,
     case folding, multi-byte characters). Needs manual test cases.

4. **Create `config.lua`** (File: `lua/beast/libs/finder/config.lua`)
   - Action: `defaults` table with window sizing (`width=0.8`, `height=0.8`, `preview_ratio=0.5`),
     debounce times (`normal_ms=30`, `live_ms=200`, `preview_ms=60`), matcher options
     (`smartcase=true`, `ignorecase=true`). `cfg` starts as deep copy of defaults.
     `M.setup(opts)` deep-merges. Read-only metatable identical to `notify/config.lua` pattern
     (AGENTS.md § *Known DRY Opportunities #2*).
   - Why: All other modules read `config.cfg.*` — must exist before UI or picker code.
   - Depends on: None
   - Risk: Low

---

### Phase 2: UI Views — three `Beast.View` subclasses

Goal: three floating windows open, close, and stay valid independently.

1. **Create `ui/input.lua`** (File: `lua/beast/libs/finder/ui/input.lua`)
   - Action: `Beast.Finder.InputView : Beast.View`. Constructor
     `InputView(buf, win, on_change)` — `on_change` is the debounced callback.
     `M.create(on_change) → InputView`: calls `Util.create_scratch_buf("beastvim-finder-input")`,
     opens float with `nvim_open_win` (position computed from `config.cfg`), sets
     `buftype=prompt` via `vim.bo`, calls `vim.fn.prompt_setprompt(buf, "")`,
     enters insert mode. Mounts `TextChangedI` autocmd on the buffer that calls
     `vim.defer_fn(on_change, config.cfg.debounce.normal_ms)` (resets timer on each change).
     `M.get_text(view) → string` — reads line 1 of the prompt buffer.
   - Why: Input window is the entry point for user interaction. Its `on_change` drives the
     entire matcher pipeline.
   - Depends on: Phase 1 config.lua, `Beast.View`
   - Risk: Low — `buftype=prompt` is documented; the same pattern is in snacks.nvim.

2. **Create `ui/list.lua`** (File: `lua/beast/libs/finder/ui/list.lua`)
   - Action: `Beast.Finder.ListView : Beast.View`. Extra fields: `items`, `cursor`, `ns`.
     `M.create(ns) → ListView`: `Util.create_scratch_buf("beastvim-finder-list")` +
     `nvim_open_win`. `M.render(view, items, format_fn)`: calls `nvim_buf_set_lines` with
     `items[i].text` (or formatted text), then applies extmarks per `Highlight[]` returned
     by `format_fn(item)`. `M.move(view, delta)`: clamp-moves `view.cursor`, re-applies
     cursor-line highlight, triggers preview debounce. `M.selected(view) → Item`.
   - Why: Results display. Must be independent of input so preview can update without
     re-rendering the full list.
   - Depends on: Phase 1 config.lua, `Beast.View`, `Util.create_scratch_buf`
   - Risk: Low

3. **Create `ui/preview.lua`** (File: `lua/beast/libs/finder/ui/preview.lua`)
   - Action: `Beast.Finder.PreviewView : Beast.View`. `M.create() → PreviewView`.
     `M.show(view, item)`: if `item.file` → read file with `vim.fn.readfile` (capped at
     500 lines), `nvim_buf_set_lines`, set `filetype` from extension via `vim.filetype.match`.
     If `item.buf` → `nvim_buf_get_lines`. Highlights via Neovim's built-in syntax (no TS
     in preview — avoids the TS-injector complexity fzf-lua had to work around).
     `M.toggle(view)` — `nvim_win_hide`/`nvim_win_show` (keeps buffer alive).
   - Why: Preview adds usability for file sources. Independent window so it can be toggled
     without closing the picker.
   - Depends on: Phase 1 config.lua, `Beast.View`, `Util.create_scratch_buf`
   - Risk: Low — no TS injection needed in v1.

---

### Phase 3: Picker Orchestrator + First Sources

Goal: first end-to-end working picker (`Finder.open("buffers")` and `Finder.open("files")`).

1. **Create `format.lua`** (File: `lua/beast/libs/finder/format.lua`)
   - Action: `M.filename(item) → Highlight[]` — icon (from `Icon.get(item.file)` if
     available, else none) + relative path segments with `BeastFinderDir` / `BeastFinderFile`
     highlight groups. `M.buffer(item) → Highlight[]` — bufnr + name + modified flag.
     `Highlight = { text: string, hl: string? }` — same shape as statusline component
     fragments.
   - Why: Decouples display from data; list.lua calls `format_fn(item)` without knowing
     what type of item it is.
   - Depends on: None (pure functions)
   - Risk: Low

2. **Create `actions.lua`** (File: `lua/beast/libs/finder/actions.lua`)
   - Action: Action signature `fun(picker, items: Item[])`. Built-ins:
     `M.open(picker, items)` — `nvim_set_current_win(picker.main_win)` + `edit {item.file}`;
     `M.open_split`, `M.open_vsplit` — same with `split`/`vsplit`;
     `M.copy_path(_, items)` — `setreg("+", item.file)`.
     Actions table is stored in `config.cfg.actions` and read by `picker.lua`.
   - Why: Actions are the user-facing output of the picker. Separating them from picker.lua
     keeps picker.lua focused on orchestration.
   - Depends on: None
   - Risk: Low

3. **Create `sources/buffers.lua`** (File: `lua/beast/libs/finder/sources/buffers.lua`)
   - Action: `M.get(filter) → Item[]` — pure Lua, no shell. Calls
     `vim.fn.getbufinfo({ buflisted = 1 })`, maps each entry to
     `{ idx=i, score=0, text=name, buf=info.bufnr, file=vim.api.nvim_buf_get_name(bufnr) }`.
     Excludes `beastvim-*` filetypes. Returns synchronously (≤ a few hundred items, no async needed).
   - Why: Buffers source is the simplest possible source — no shell, no async. Good for
     validating the full pipeline without external binary dependency.
   - Depends on: `filter.lua`
   - Risk: Low

4. **Create `sources/files.lua`** (File: `lua/beast/libs/finder/sources/files.lua`)
   - Action: `M.get(filter, cb)` — async source. Tries `fd --type f --hidden --exclude .git`
     → `rg --files --hidden --glob '!.git'` → `find . -type f -not -path './.git/*'` (first
     executable wins). Spawns via `vim.uv.spawn`; reads stdout chunks in the `onread`
     callback; splits on newline; for each path calls `cb({ idx=i, score=0, text=rel_path,
     file=abs_path, cwd=filter.cwd })`. Calls `cb(nil)` on process exit to signal completion.
   - Why: Files is the most-used source. Async spawn keeps the UI responsive during large
     directory scans.
   - Depends on: `filter.lua`, `async.lua`
   - Risk: Medium — libuv spawn + chunk splitting requires careful newline buffering.

5. **Create `picker.lua`** (File: `lua/beast/libs/finder/picker.lua`)
   - Action: `Picker` class with fields:
     `{ filter, items, matched, input_view, list_view, preview_view, main_win, source, opts }`.
     `M.new(source_name, opts) → Picker`:
     - saves `main_win = nvim_get_current_win()`
     - creates input, list, preview views
     - calls `M._load_items(picker)` to populate `picker.items` from source
     - calls `M._rematch(picker)` to score all items against the empty filter
     - renders list
     - mounts keymaps (see Requirements) on input window buffer
     `M._load_items(picker)`: calls `source.get(filter, cb)` — cb appends items to
     `picker.items`, calls `M._rematch` on each batch (async sources) or once (sync sources).
     `M._rematch(picker)`: calls `matcher.run(picker.items, picker.filter, function(matched)`
     `  picker.matched = matched; list.render(picker.list_view, matched, format_fn) end)`.
     `M._on_input(picker, text)`: `filter.update(picker.filter, text)` + `M._rematch(picker)`.
     `M.close(picker)`: closes all three views, restores `main_win`.
   - Why: The Picker is the single orchestrator — the only file that knows about all three
     views simultaneously (AGENTS.md § *State Ownership*: state lives here, not scattered).
   - Depends on: all of Phase 1 + Phase 2 + Steps 1–4 above
   - Risk: Medium — wiring the async source → batch render loop correctly requires
     discipline (avoid calling `nvim_buf_set_lines` from a libuv callback without
     `vim.schedule`).

6. **Create `highlights.lua`** (File: `lua/beast/libs/finder/highlights.lua`)
   - Action: `M.setup()` — registers `BeastFinderBorder`, `BeastFinderPrompt`,
     `BeastFinderMatch`, `BeastFinderFile`, `BeastFinderDir`, `BeastFinderSelected`,
     `BeastFinderPreviewBorder` via `Util.colors.set_hl` + `Palette.get()`. Same pattern
     as `notify/highlights.lua`.
   - Why: Highlights must exist before any window opens. Registered in `init.lua` via
     `M.highlight_modules`.
   - Depends on: None (pure side-effects on Neovim state)
   - Risk: Low

7. **Create `init.lua`** (File: `lua/beast/libs/finder/init.lua`)
   - Action: `M.setup(opts)`: calls `config.setup(opts)` + `highlights.setup()` +
     `ensure_autocmds()`. `M.open(source_name, opts)`: creates and returns a `Picker`.
     `M.close()`: closes the active picker (stored in module-level `_picker`). Registers
     `vim.ui.select` override. Sets `_G.Finder = M`.
     `ensure_autocmds()` guard: registers `BeastFinder` augroup with `ColorScheme` handler
     → `highlights.setup()`.
   - Why: Module-level state lives only here (AGENTS.md § *State Ownership*). All external
     entry points are here. `Finder.open("files")` is the public API.
   - Depends on: all above
   - Risk: Low

8. **Modify `lua/beast/init.lua`**
   - Action: Add `packer.lazy("beast.libs.finder", { defer = true, highlights = true })`.
     Add keymaps: `<leader>ff` → `Finder.open("files")`, `<leader>fb` → `Finder.open("buffers")`.
   - Why: Deferred loading keeps startup time unaffected (matches tabline/explorer pattern).
   - Depends on: Step 7
   - Risk: Low

---

### Phase 4: Live-grep Source (separate spec)

This phase is deliberately deferred. Live-grep requires a `fn_reload` pattern: on input
change, cancel the running `uv.spawn` process and start a new one with the search term
passed to the shell command (not to the Lua matcher). This is architecturally distinct
enough to warrant its own dev spec once Phase 3 ships.

## Testing Strategy

- **Unit — matcher**: `tests/finder/matcher_spec.lua`. Cases: empty pattern matches all;
  exact match scores higher than fuzzy; `!` inverse excludes; `^` prefix; `$` suffix;
  boundary bonus (file.lua scores higher than filelua for query `fl`); multi-byte safe
  (UTF-8 filename).
- **Unit — async**: `tests/finder/async_spec.lua`. Cases: `spawn` runs fn in coroutine;
  `yielder` yields when budget exceeded; multiple concurrent tasks interleave correctly.
- **Manual**: `:lua Finder.open("buffers")` — picker opens, typing filters, `<Enter>` jumps
  to buffer, `<Esc>` closes cleanly. `:lua Finder.open("files")` — files stream in, list
  updates live, preview shows content. `:lua vim.ui.select({"a","b","c"}, {prompt="Pick:"}, print)` — finder replaces the built-in select.
- **Bench**: `scripts/bench-finder.lua` — time `matcher.run` over 10,000 synthetic items
  for 10 different patterns. Report mean µs/item. Target: < 2µs/item (= 50k items/sec).

## Risks & Mitigations

- **Risk**: `buftype=prompt` input captures `<Esc>` before our keymap sees it → Mitigation:
  use `vim.keymap.set("i", "<Esc>", ...)` on the prompt buffer with `{ buffer=buf }`.
- **Risk**: `vim.schedule` latency between `libuv.spawn` `onread` and `nvim_buf_set_lines`
  causes perceived jank → Mitigation: batch items (100 at a time) before scheduling a
  render, not one-item-at-a-time.
- **Risk**: Multi-byte filenames break character-level scoring → Mitigation: use
  `vim.str_utf_pos(s)` for character indexing in the matcher; ASCII fast-path for all-ASCII
  patterns (most common case).
- **Risk**: Three floating windows fight z-order with other Beast UI (notify, toast) →
  Mitigation: use `zindex=50` for finder windows (above default 0, below notify's 100).
- **Risk**: `vim.ui.select` override breaks other plugins that call it expecting synchronous
  return → Mitigation: `vim.ui.select` is inherently async (callback-based); store the
  callback, call it from the action handler. This is the documented contract.

## Success Criteria

- [ ] `Finder.open("buffers")` opens within < 20ms, filters correctly, confirms to buffer
- [ ] `Finder.open("files")` streams ≥ 1,000 files into the list without locking the UI
- [ ] `bench-finder.lua` reports < 2µs/item for the matcher (50k items/sec target)
- [ ] `vim.ui.select` override works with dressing.nvim disabled
- [ ] `:checkhealth beast` passes (if a checkhealth is added in Phase 3)
- [ ] All three windows close cleanly on `<Esc>` with no lingering buffers
- [ ] Codemaps regenerated (`/tec-update-codemaps`) and committed alongside Phase 3

## ADR Required

This dev spec involves architectural decisions that must be documented as ADRs once committed:

- **New `uv.new_check()` async executor** (`finder/async.lua`) — first time BeastVim uses
  a libuv check handle for cooperative scheduling. Previous libs used `vim.schedule` /
  `vim.defer_fn`. This is a new async primitive in the codebase.
- **Three `Beast.View` subclasses in one lib** — largest UI component so far. Establishes
  the pattern for multi-window pickers (future: command palette, git log viewer).
- **`vim.ui.select` override** — BeastVim will own `vim.ui.select` natively, removing the
  dependency on `dressing.nvim` for select UI. This is a plugin-replacement decision
  (ref ADR-009 pattern).
