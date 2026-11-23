---
name: breadcrumb-symbol-trail
description: Winbar symbol trail from LSP documentSymbol with a treesitter ancestor-walk fallback, rendered by the existing native breadcrumb
generated: 2026-11-23
---

> PM Spec: [docs/pm-specs/breadcrumb-symbol-trail.md](../pm-specs/breadcrumb-symbol-trail.md)

# Summary

**TL;DR:** add a `symbols/` submodule to the breadcrumb lib. It produces an ordered list of `{ name, kind }` for the cursor of a given window, from LSP `textDocument/documentSymbol` when a server answers, else from a treesitter ancestor walk using a small per-language node table. `filepath.lua` renders that list after the file name with kind icons, truncating outer dirs first then outer symbols, and moves the modified marker to the end. The existing per-window cache stays; a debounced "cursor settled" event invalidates it. No new plugin, no new global, one new config key (`symbols`).

---

# Context

## Problem

`filepath.render` draws path + file + modified marker and nothing else, so the "code context" promised by `breadcrumb-init` does not exist. There is no symbol data source in the repo (nothing requests `documentSymbol`), no cursor-driven invalidation (the cache only reacts to buffer/name/modified changes), and the truncation logic only knows about directories.

### Solution

After this change the breadcrumb lib owns a symbol pipeline: an LSP store (per-buffer symbol tree, refreshed on attach/progress/edit), a treesitter fallback (per-call ancestor walk), and a `trail(bufnr, winid)` entry point that picks one source and returns the chain at that window's cursor. `render()` calls it only on cache miss. Cursor movement invalidates the window's cache entry after a short quiet period, so rendering stays on the cheap cached path while the cursor is moving.

---

# Research

### Repo Search
- Searched for: `documentSymbol`, `document_symbol`, `workspace/symbol`, `navic`, `buf_request_all`, `client:request`, `LspProgress`, `Icon.kinds`, `locals.scm`, `context.scm`, `tags.scm`, `on_attach`/`subscribe`.
- Found:
  - No existing `documentSymbol` consumer. The only LSP request precedent is `lua/beast/libs/finder/source/lsp.lua:82` (`vim.lsp.buf_request_all`, handler fires once after all clients respond, avoids the pending-count race). Same call shape is reused here.
  - `lua/beast/icon.lua` `Icon.kinds` has an entry for every LSP `SymbolKind` name (Module, Namespace, Package, Class, Method, Property, Field, Constructor, Enum, Interface, Function, Variable, Constant, String, Number, Boolean, Array, Object, Key, Null, EnumMember, Struct, Event, Operator, TypeParameter, File).
  - `lua/beast/libs/lsp/attach.lua` exposes `subscribe(fn)` (public as `Lsp.on_attach`) which runs after per-server handlers on every `LspAttach`.
  - Treesitter sticky context (`lua/beast/libs/treesitter/context/`) walks ancestors with local helpers (`get_parent_nodes`) driven by `context.scm`. Those queries capture header *ranges* only: no names, no kinds, so they cannot drive the trail. `locals.scm` is installed for only 14 languages and yields identifier nodes, not symbol ranges. `tags.scm` exists for 3.
  - `lua/beast/libs/breadcrumb/*` (cache, `g:statusline_winid` context, highlight refresh, health, `scripts/bench-breadcrumb.lua`) is reused as is.
  - Tests are standalone `tests/test-*.lua` run with `nvim --clean --headless -l`, with `assert_eq`/`assert_test` helpers and exit code 0/1 (see `tests/test-autopairs-skip.lua`).
- Reuse opportunity: **Yes** - `buf_request_all` pattern, `Lsp.on_attach`, `Icon.kinds`, existing cache/highlight/health/bench scaffolding.

### Built-in / Existing Lib Check
- Checked: `vim.lsp.buf_request_all`, `client:supports_method`, `LspAttach`/`LspDetach`/`LspProgress` autocmds (Neovim >= 0.11), `vim.treesitter.get_node`, `get_parser(..., { error = false })`, `vim.uv.new_timer`, `Lsp.on_attach`, `Icon.kinds`, treesitter context lib internals.
- Found: Neovim covers requests, events, timers and node lookup. `get_node` already ignores injections by default, which is what we want (headings in markdown, not code inside fences). The treesitter context walker is private and range-oriented, so it is not reused; the ancestor walk here is ~15 lines on top of `get_node` + `:parent()`.
- Decision: **Reuse + Build** - reuse the platform APIs and breadcrumb scaffolding; build the symbol store, kind table, per-language node table and render changes. nvim-navic is deliberately not used (per request).

### Design decisions

| Question | Choice | Why |
|---|---|---|
| Symbol shape | Normalize both LSP forms (hierarchical `DocumentSymbol[]` and flat `SymbolInformation[]`) to one tree `{ name, kind, range, children }` | Lookup code and tests have a single input type |
| Which LSP client | All clients supporting the method via `buf_request_all`; first non-empty result in client-id order | Matches finder precedent; avoids picking by name |
| Source choice per buffer | LSP if its stored tree is non-empty, else treesitter, else none. Decided per `trail()` call, whole trail from one source | PM: server wins, never mix |
| Cursor tracking | Debounced `CursorMoved`/`CursorMovedI` invalidates that window's cache entry; render recomputes from the live cursor | Keeps the cache hit path untouched while moving |
| Debounce | Two `vim.uv` timers, each restarted on every event: cursor 60 ms (flushes dirty windows), refresh 300 ms (flushes dirty buffers) | Holding `j` repeats faster than 60 ms so nothing recomputes until release; one request per typing pause, not per key |
| Stale tree while editing | Keep last tree; a newer successful reply replaces it (a successful empty reply clears it), an errored reply keeps it; only the newest sequence number is applied | Out-of-order replies cannot regress the trail; no blanking; a file emptied of symbols stops showing stale ones |
| Treesitter table | Per-language table in `symbols/treesitter.lua`: node type -> `{ kind, name = field or fn }` | Smallest thing that works; no per-language query files to ship or download |

---

# Architecture Changes

- `lua/beast/libs/breadcrumb/config.lua` (modified) - add `symbols = true` default.
- `lua/beast/libs/breadcrumb/highlights.lua` (modified) - add `BeastBcSymbol` (name) and four icon-family groups (`BeastBcSymCallable`, `BeastBcSymType`, `BeastBcSymModule`, `BeastBcSymValue`).
- `lua/beast/libs/breadcrumb/filepath.lua` (modified) - take an optional symbol list; render icon + name segments; new truncation order (dirs, then outer symbols); modified marker moved to the end.
- `lua/beast/libs/breadcrumb/symbols/kinds.lua` (new) - LSP `SymbolKind` number -> `Icon.kinds` key, and key -> highlight family.
- `lua/beast/libs/breadcrumb/symbols/lsp.lua` (new) - per-buffer symbol store, request/refresh, normalization, `find(tree, row, col)`.
- `lua/beast/libs/breadcrumb/symbols/treesitter.lua` (new) - ancestor walk with per-language node table.
- `lua/beast/libs/breadcrumb/symbols/init.lua` (new) - `trail(bufnr, winid)` source selection, `refresh(bufnr)` and `clear(bufnr)` passthroughs.
- `lua/beast/libs/breadcrumb/init.lua` (modified) - call `symbols.trail` on cache miss; new autocmds (`LspAttach` via `Lsp.on_attach`, `LspDetach`, `LspProgress`, `TextChanged`, `InsertLeave`, `FileType`, cursor debounce); extend invalidation; skip all of it when `symbols = false`.
- `lua/beast/libs/breadcrumb/health.lua` (modified) - check new submodules, source availability for the current buffer, symbols toggle.
- `scripts/bench-breadcrumb.lua` (modified) - add trail lookup and render-with-trail cases.
- `tests/test-breadcrumb-symbols.lua` (new) - headless tests for render, lookup, normalization, treesitter walk.
- `docs/CODEMAP/libraries.md` (regenerate) - breadcrumb section via `/update-codemap`; not hand-edited.

## Implementation Phases

## Phase 1: Render a trail - symbols in, truncated winbar out
Smallest slice: given a symbol list, the bar renders correctly. Mergeable alone (nothing supplies symbols yet, so the bar is unchanged).

1. **Config key** (File: `lua/beast/libs/breadcrumb/config.lua`)
   - Action: add `symbols = true` with a short comment.
   - Why: single off-switch used by every later phase.
   - Depends on: None
   - Risk: Low

2. **Kind table** (File: `lua/beast/libs/breadcrumb/symbols/kinds.lua`)
   - Action: export `by_number` (1..26 -> `Icon.kinds` key) and `family(key)` returning `"Callable" | "Type" | "Module" | "Value"` (Function/Method/Constructor/Operator/Event -> Callable; Class/Struct/Interface/Enum/TypeParameter -> Type; File/Module/Namespace/Package -> Module; everything else -> Value). Unknown number falls back to `Variable`.
   - Why: LSP numbers and treesitter kind names both resolve to one icon + color path.
   - Depends on: None
   - Risk: Low

3. **Highlights** (File: `lua/beast/libs/breadcrumb/highlights.lua`)
   - Action: add `Symbol` (dimmed2, same as `File`) and `SymCallable` (accent4), `SymType` (accent5), `SymModule` (accent2), `SymValue` (accent6) through the existing `Util.colors.build("BeastBc", ...)`. Colors follow the treesitter palette table (`treesitter/highlights.lua` header comment); tune by eye in step 5.
   - Why: icon color follows kind family, names one calm color.
   - Depends on: None
   - Risk: Low

4. **Render + truncation** (File: `lua/beast/libs/breadcrumb/filepath.lua`)
   - Action: `M.render(ctx, separator, modified_icon, symbols?)`. Build symbol segments (`icon .. " "` in family group, name in `BeastBcSymbol`, each with display width, skipping empty names). Assemble `dirs > file > symbols > modified marker`. Width fitting: compute total; if too wide drop dirs from the left (existing leading `…`); if still too wide drop symbols from the left but always keep the innermost, replaced by a `…` segment right after the file. File and marker are never dropped. Remove the marker from `build_file_part` and append it last. Extract one `drop_left(list, need)` helper used for both lists instead of duplicating the loop.
   - Why: PM rules for truncation order and marker position.
   - Depends on: Steps 2-3
   - Risk: Medium (width arithmetic; existing dir truncation must behave identically when no symbols are passed)

5. **Phase 1 tests + visual check** (File: `tests/test-breadcrumb-symbols.lua`)
   - Action: create the test file. Cover `filepath.render` with a fake ctx: no symbols (output identical to the pre-change output for several widths), 1-3 symbols, empty-name skipped, each truncation stage (dirs only, dirs gone then symbols, innermost kept), marker last. Then open a real nvim with a hard-coded symbol list injected (temporary local patch, not committed) and compare against the PM mockups in light and dark colorschemes.
   - Why: lock the truncation contract before data sources exist.
   - Depends on: Step 4
   - Risk: Low

## Phase 2: LSP source - live trail from the language server
Mergeable alone: LSP-backed files get a trail; others unchanged.

1. **Store, request, lookup** (File: `lua/beast/libs/breadcrumb/symbols/lsp.lua`)
   - Action: per-buffer `{ tree, seq }`. `refresh(bufnr)`: bail unless some attached client `supports_method("textDocument/documentSymbol", bufnr)`; bump `seq`; `vim.lsp.buf_request_all`; on reply, ignore if `seq` is not newest or buffer invalid; take the first non-error result in client order; normalize (`DocumentSymbol` already nested; `SymbolInformation[]` sorted by range start and nested with a stack by range containment); map `kind` through `kinds.by_number`; store; call an `on_change(bufnr)` callback. An errored reply keeps the previous tree; a successful empty reply clears it (the file has no symbols). The cursor's byte column is converted to the answering client's offset encoding before lookup. `find(tree, row, col)` binary-searches each level (siblings sorted by start) for the child whose range contains the position, return the chain (header line is inside because ranges start at the header). `clear(bufnr)` drops the entry.
   - Why: core data source; preserves "keep previous trail while refreshing".
   - Depends on: Phase 1 step 2
   - Risk: Medium (two response shapes, ordering, positions are 0-indexed `row, col` vs `nvim_win_get_cursor`)

2. **Source selection** (File: `lua/beast/libs/breadcrumb/symbols/init.lua`)
   - Action: `trail(bufnr, winid)` returns `Beast.Breadcrumb.Symbol[]` (`{ name, kind }`); reads the cursor via `nvim_win_get_cursor(winid)`; uses the LSP chain when the stored tree is non-empty, else `{}` (treesitter joins in Phase 3). Re-export `refresh`/`clear`.
   - Why: one stable entry point so Phase 3 adds a branch, not a new call site.
   - Depends on: Step 1
   - Risk: Low

3. **Wire into the lib** (File: `lua/beast/libs/breadcrumb/init.lua`)
   - Action: in `render()` cache-miss path call `symbols.trail(ctx.bufnr, ctx.winid)` when `config.symbols` and pass it to `filepath.render`. In `ensure_autocmds` (only when `config.symbols`): `LspAttach` autocmd in the breadcrumb augroup (not `Lsp.on_attach`: its subscriber list cannot be unsubscribed, so a repeated `setup()` would stack handlers); `LspDetach` -> clear then refresh (a different server may remain); `LspProgress` with `kind == "end"` -> `refresh` for buffers of that client, so a slow server's first real answer arrives without a keypress; `TextChanged`/`TextChangedI`/`InsertLeave`/`BufEnter` -> `refresh` (debounced by the refresh timer; `BufEnter` and `setup()` also cover servers attached before the lib loaded); `BufDelete`/`BufWipeout` -> `symbols.clear`. Set `symbols.on_change = invalidate_buf + redrawstatus`. Add a 60 ms cursor timer fed by `CursorMoved`/`CursorMovedI` that records `winid` in a dirty set and on fire does `invalidate_win` + `redrawstatus`. All new autocmds live in the existing `BeastBreadcrumb` augroup so `setup()` re-run stays idempotent. `setup()` must also stop and reset the timer.
   - Why: cursor-driven invalidation is the missing piece; keeps cache semantics (`invalidate_win/invalidate_buf`) as the single mutation path.
   - Depends on: Steps 1-2
   - Risk: High (event ordering, timer lifetime, redraw storms; verify per Testing Strategy)

4. **Phase 2 tests** (File: `tests/test-breadcrumb-symbols.lua`)
   - Action: add lookup tests on hand-built trees (nested, siblings, cursor on header line, cursor between symbols, outside all) and normalization tests (flat `SymbolInformation` with `containerName`-less nesting by range, out-of-order replies via `seq`, empty reply keeps previous tree). Use a stub client/`buf_request_all` replacement for the request path.
   - Why: PM scenarios 1, 3 logic without a real server.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Treesitter fallback - trail without a language server
Mergeable alone: files with a parser but no server get a trail.

1. **Ancestor walk** (File: `lua/beast/libs/breadcrumb/symbols/treesitter.lua`)
   - Action: `trail(bufnr, row, col)`: `vim.treesitter.get_parser(bufnr, nil, { error = false })` (nil -> `{}`), then `vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })`, walk `:parent()`; for each node whose type is in `NODES[lang]` emit `{ name, kind }` (prepend, so outermost first). `NODES[lang]` maps node type to `{ kind = "Function", name = "name" }` (field name) or `{ kind, name = function(node, bufnr) ... end }` for cases without a `name` field. Names via `vim.treesitter.get_node_text`. Skip empty names. v1 languages: `lua`, `python`, `javascript`, `typescript`, `tsx`, `c`, `cpp`, `markdown`, `xml`. Lua: `function_declaration`, `function_definition` assigned to a name (name from the parent assignment/field), `table` fields are not symbols. Markdown: nested `section` nodes, name from the heading's inline text, kind `Module`. Node type names are verified against the installed parsers by fixture tests, not assumed.
   - Why: covers files without a server, exactly what the PM spec promised.
   - Depends on: Phase 1 step 2
   - Risk: Medium (node/field names differ per grammar; unnamed function expressions)

2. **Select source** (File: `lua/beast/libs/breadcrumb/symbols/init.lua`)
   - Action: when the LSP tree is empty/absent, return `treesitter.trail(...)`. Never concatenate the two.
   - Why: PM rule "server wins, never mix".
   - Depends on: Step 1
   - Risk: Low

3. **Invalidation hooks** (File: `lua/beast/libs/breadcrumb/init.lua`)
   - Action: add `FileType` to the buffer-invalidating events (parser appears after first install) and let the existing `TextChanged`/`InsertLeave` hook invalidate the buffer when the treesitter source is active. LSP `refresh` is a no-op without a client.
   - Why: treesitter has no push signal; edits and parser availability must clear the cache.
   - Depends on: Step 2
   - Risk: Low

4. **Fixtures + tests** (File: `tests/test-breadcrumb-symbols.lua`; fixtures are inline scratch buffers, no fixture files)
   - Action: one small inline fixture per language with nested symbols; assert the chain at known cursor positions; skip (not fail) a language whose parser is not installed, printing `SKIP`. Include a markdown fixture with a fenced code block (headings only, fence ignored) and a Lua fixture with an anonymous callback.
   - Why: lock grammar-specific node names.
   - Depends on: Step 1
   - Risk: Low

## Phase 4: Health, bench, docs
1. **Health** (File: `lua/beast/libs/breadcrumb/health.lua`)
   - Action: add `symbols`, `symbols.kinds`, `symbols.lsp`, `symbols.treesitter` to the submodule load check; report `symbols` toggle, LSP clients supporting `documentSymbol` for the current buffer, and treesitter table coverage for its filetype. Update the "All submodules load" message.
   - Depends on: Phases 2-3
   - Risk: Low
2. **Bench** (File: `scripts/bench-breadcrumb.lua`)
   - Action: add (a) `find` on a synthetic tree (5k symbols, depth 6) and (b) cache-miss render with a 5-symbol trail; keep the existing cache-hit case and thresholds. Cache-hit must not regress.
   - Depends on: Phase 2
   - Risk: Low
3. **Codemap** (File: `docs/CODEMAP/libraries.md`)
   - Action: run `/update-codemap`; do not hand-edit. Do not touch `CHANGELOG.md`.
   - Depends on: Steps 1-2
   - Risk: Low

---

# Testing Strategy

- Headless tests: `nvim --clean --headless -l tests/test-breadcrumb-symbols.lua` (render/truncation, lookup, normalization, treesitter fixtures). Parsers that are not installed print `SKIP`.
- Bench: `nvim --clean --headless -l scripts/bench-breadcrumb.lua` (FAIL at 1 ms, WARN at 50 us as today); then `./scripts/bench-startup.sh` since the lib loads at startup, and `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all` because new cursor autocmds touch input-to-paint latency. Per DEVELOPMENT.md these are mandatory after touching a benched lib.
- Type check: `lua-language-server --check . --checklevel=Warning` (command in DEVELOPMENT.md).
- Manual E2E (real editor, `NVIM_APPNAME=BeastVim`, driven through tmux, not headless typing), mapping to PM scenarios:
  1. Scenario 1: open `lua/beast/libs/breadcrumb/init.lua` with lua_ls, walk into `M.render`, a nested callback, then out.
  2. Scenario 2: cold-start the editor on a big file; confirm the trail appears without a keypress once lua_ls is ready.
  3. Scenario 3: type inside a function, pause, add a function above, rename the current one; confirm no blank frame.
  4. Scenario 4: `:vsplit`, move in one split only.
  5. Scenario 5: shrink the window with `:vertical resize`; confirm order `...` dirs, then symbols, file + innermost kept, marker last.
  6. Scenario 6: set `symbols = false`; confirm no `documentSymbol` request (`:lua vim.lsp.log` or a stub counter) and an unchanged bar.
  7. Scenario 7: open a `.md` file with no server (headings trail), attach nothing, then open a `.txt` file (path only).
  8. Hold `j` through a large file; check for stutter. Inspect every state at pixel level in a light and a dark colorscheme (icon family colors, separators, marker).

# Success Criteria

- [x] Moving the cursor into a function, method or class shows its name with a kind icon after the file name.
- [x] Nested symbols show as an ordered chain, outermost first.
- [x] Outside any symbol, only the path and file name show.
- [x] Two windows on one file show independent trails.
- [x] The trail appears by itself once a slow server finishes starting.
- [x] Typing never blanks the trail; it refreshes shortly after typing pauses.
- [x] Narrow windows keep the file name and innermost symbol visible; truncation order is dirs, then outer symbols; marker is last.
- [x] Files with no server but a known language show a trail with the same look; the server wins when both exist and sources never mix.
- [x] Plain text and unknown languages look exactly as they do today.
- [x] `symbols = false` restores today's bar and issues no `documentSymbol` request.
- [x] Holding `j` or `k` through a large file shows no stutter.
- [x] Technical gates: new headless test passes, breadcrumb bench passes with cache-hit time unchanged, `bench-ux.sh all` shows no regression, lua-language-server check is clean, no `vim.notify`, no keymaps added by the lib.

---

# Implementation Notes

- Go and Rust are not in v1: their parsers are not installed in this environment, so node names could not be verified. Adding them is a table entry each plus a test case once a parser is available.
- `health.lua` reports the symbol source per window that carries a breadcrumb (language server, syntax tree, or path only), not just the current buffer.
- `scripts/bench-breadcrumb.lua` gained `find` (5.4k-symbol tree) and `trail render` (5 symbols) cases; the existing cold/hot metrics and thresholds are unchanged.
- Noticed, not changed: lua_ls reports control-flow blocks (`if`) and call expressions (`vim.api.nvim_create_autocmd`) as symbols, so trails inside nested Lua callbacks get long. A kind filter is out of scope for v1 (see PM spec).

---

# Completed

2026-11-23. Phase 1 render + truncation, Phase 2 LSP source and wiring, Phase 3 treesitter fallback, Phase 4 health, bench, codemap. Each phase passed a code-reviewer pass.

- `a68036e` docs(breadcrumb): symbol trail pm and dev specs
- `2b809bd` feat(breadcrumb): add symbols config key and kind table
- `e77038a` feat(breadcrumb): add symbol highlight groups
- `925fce2` feat(breadcrumb): render symbol trail with left-first truncation
- `2f89256` refactor(breadcrumb): hoist icon table lookup
- `ad69bbb` feat(breadcrumb): LSP document symbol store and lookup
- `3ad223e` feat(breadcrumb): wire symbol trail into winbar with cursor and refresh debounce
- `aaa5720` docs(breadcrumb): align dev spec with lsp source implementation
- `cf71241` feat(breadcrumb): treesitter fallback for files without a symbol server
- `3ab4488` feat(breadcrumb): report symbol source and new groups in health check
- `b81e78d` bench(breadcrumb): add symbol lookup and trail render cases
- `2d5703e` docs(breadcrumb): record implementation notes in dev spec
- `ec3cd32` docs(codemap): breadcrumb symbol trail
- (the `coding.lua` indentation change inside the LSP store commit is a stylua fix to an unrelated file, picked up by formatting `lua/`)

Verification: `tests/test-breadcrumb-symbols.lua` 67 passed, 0 failed (no SKIPs); `bench-breadcrumb.lua` cold ~65 us (pre-change ~60 us, soft-target WARN pre-existing), hot ~0.9 us, find 0.17 us, trail render ~61 us, all far below the 1 ms limit; `bench-startup.sh` mean 38 ms (green); `bench-ux.sh all` keypress/scroll/bufswitch/extmarks/keymaps all PASS; lua-language-server check clean; stylua clean on touched files. Real-editor E2E in tmux with lua_ls and markdown (no server): nested trail, outside-symbol, split independence, narrow truncation, typing without blanking, `symbols = false` issuing 0 requests, `:checkhealth`.
