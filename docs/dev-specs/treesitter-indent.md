---
name: treesitter-indent
description: Structure-aware indentexpr driven by upstream `indents.scm` queries, wired per-buffer alongside existing highlight/fold treesitter setup
generated: 2026-08-02
---

> PM Spec: [docs/pm-specs/treesitter-indent.md](../pm-specs/treesitter-indent.md)

# Summary

Add a treesitter-driven `'indentexpr'` that computes indent from the buffer's real node structure, using the same `indents.scm` query files BeastVim already downloads (but doesn't yet consume) for every parser. The buffer's `indentexpr` is only ever set when a compiled `indents` query actually exists for its language; otherwise the buffer is left untouched, so Neovim's built-in per-filetype indent methods (`cindent`/`smartindent`/ftplugin `indentexpr`) keep working exactly as before.

---

# Context

## Problem

`lua/beast/libs/treesitter/init.lua` already starts highlighting (`vim.treesitter.start`) and, when enabled, expr-folding (`foldexpr = v:lua.vim.treesitter.foldexpr()`) per buffer. There is no equivalent for indentation: Neovim core has no `vim.treesitter.indentexpr()` (confirmed absent in this build — `vim.treesitter.indentexpr` is `nil`), so buffers fall back entirely to whatever generic `cindent`/`smartindent`/ftplugin-provided `indentexpr` Neovim ships, which has no concept of markup-style nesting (e.g. JSX/HTML tags) and only shallow bracket/keyword matching elsewhere.

Meanwhile, `lua/beast/libs/treesitter/install.lua` already syncs `indents.scm` from upstream nvim-treesitter for every installed language (`QUERY_FILES` includes `"indents.scm"`), and these files are sitting unused on disk at `~/.local/share/BeastVim/site/queries/<lang>/indents.scm`.

### Solution

A new `lua/beast/libs/treesitter/indent.lua` module implements `M.indentexpr()`, following the standard treesitter-indent algorithm (the same query capture convention the `indents.scm` files themselves already use: `@indent.begin`, `@indent.end`, `@indent.branch`, `@indent.dedent`, `@indent.align`, `@indent.auto`, `@indent.ignore`, `@indent.zero`). `treesitter/init.lua`'s `start_buf` sets `vim.bo[buf].indentexpr` to call it, but **only when `vim.treesitter.query.get(lang, "indents")` returns a query** — the same per-buffer gate already used for highlight/fold, extended with an existence check. A new custom predicate (`kind-eq?`, and its auto-negated `not-kind-eq?` form) is registered once at setup, since the ecma-family query files (shared by JS/TS/JSX/TSX) use it and Neovim core's query engine doesn't ship it.

---

# Research

### Repo Search
- Searched for: `indentexpr`, `indent` in `lua/beast/`, `foldexpr` wiring pattern, `ensure_queries`, `query.get`, existing `beast.libs.indent` lib.
- Found:
  - `lua/beast/libs/indent/**` is the **visual indent-guide** lib (scope highlighting for indent guides) — has nothing to do with `'indentexpr'`. Confirmed out of scope per the PM spec's "Visual indent guides — already covered" exclusion; no naming collision risk since it's a separate top-level lib and this feature lives entirely inside `beast.libs.treesitter`.
  - `lua/beast/libs/treesitter/init.lua:109-167` (`start_buf`) is the exact pattern to extend: it gates `vim.treesitter.start`/foldexpr on `config.highlight.enable`/`config.fold.enable` and `has_parser(lang)`, and re-triggers itself once `install.lua`'s `ensure_queries` reports `changed`.
  - `lua/beast/libs/treesitter/install.lua:7` — `QUERY_FILES` already includes `"indents.scm"`; it's downloaded from upstream nvim-treesitter (`NVIM_TS_QUERY_BASE`) alongside highlights/folds/injections/locals for every language, and `; inherits:` resolution already pulls in shared bases (e.g. `ecma` for JS/TS/JSX/TSX). Confirmed present on disk today for lua, python, json, markdown, html, html_tags, ecma, javascript, typescript, jsx, tsx, query.
  - `tests/test-indent-scope.lua` is the only precedent for a treesitter-adjacent headless test; it does **not** touch `indents.scm` (the scope lib uses a config-driven node-type set, not queries), so there's no existing fixture/test pattern for query-driven indent to reuse directly, but its `runtimepath:prepend(vim.fn.getcwd())` + stub-globals harness pattern is reusable.
- Reuse opportunity: Yes — reuse the `start_buf` gating pattern, the `ensure_queries` changed-callback re-trigger pattern, and the `tests/test-indent-scope.lua` headless harness shape. No existing indent-expr code to reuse or collide with.

### Built-in / Existing Lib Check
- Checked: `vim.treesitter.indentexpr` (absent in this Neovim build — confirmed `nil` via `:lua print(vim.treesitter.indentexpr)`), `vim.treesitter.query.get(lang, "indents")`, `vim.treesitter.query.list_predicates()` (core provides `eq?`, `any-eq?`, `match?`/`any-match?`, `lua-match?`/`any-lua-match?`, `any-of?`, `has-parent?`, `has-ancestor?`, `contains?`/`any-contains?` — **and generically auto-negates any `not-<pred>?` by stripping the prefix and inverting the result**, confirmed by reading `vim/treesitter/query.lua:54-79`), `vim.fn.shiftwidth()`, `'indentexpr'`/`'indentkeys'` semantics (`:help 'indentexpr'`, `:help indent.txt`).
- Found:
  - Core's `not-*?` auto-negation means `#not-has-parent?` and `#not-any-of?` (used in `lua`, `python`, `html`, etc. `indents.scm`) already work with **zero** custom predicate code — they resolve against the core `has-parent?`/`any-of?` handlers.
  - `#not-kind-eq?` (used only in `ecma/indents.scm`, shared by javascript/typescript/jsx/tsx via `; inherits:`) needs a `kind-eq?` handler registered — core does **not** provide one. Upstream nvim-treesitter registers it via `plugin/query_predicates.lua`; BeastVim has no equivalent today.
  - `'indentexpr'` returning a negative value means "copy the previous line's indent" (autoindent-style) — it does **not** fall back to the buffer's original `cindent`/`smartindent`/ftplugin `indentexpr`, and once `'indentexpr'` is set non-empty it permanently overrides those for that buffer. This means PM spec Scenario 5 ("no parser → behaves exactly as before") can only be honored by **never assigning `'indentexpr'`** to buffers whose language has no `indents` query — not by having the expr function return -1 as a fallback signal. This is the one point where this implementation intentionally diverges from upstream nvim-treesitter's own recommended setup (which sets `indentexpr` unconditionally on `FileType` and relies on -1 for the no-query case) — that upstream approach would violate the PM spec's exact-parity requirement for the no-parser case.
  - `'indentkeys'` (controls which typed characters trigger reindent, e.g. Scenario 2's `}`) is left untouched — it's already set per-filetype by Neovim's own `ftplugin/indent/<lang>.vim` (e.g. html's ftplugin already includes `>` for closing tags), and this feature only overrides `'indentexpr'`, never `'indentkeys'`.
- Decision: **Build** `lua/beast/libs/treesitter/indent.lua` (the algorithm) and a small `query_predicates.lua` (the one missing predicate) — no built-in or existing lib covers either.

---

# Architecture Changes

- `lua/beast/libs/treesitter/indent.lua` — **new**. `M.indentexpr()` (entry point matching `:help indentexpr`'s zero-arg contract, reading `v:lnum`) and `M.get_indent(lnum)`, walking `indents.scm` captures up the node ancestry the way the query captures are designed to be consumed.
- `lua/beast/libs/treesitter/query_predicates.lua` — **new**. Registers `kind-eq?` (`vim.treesitter.query.add_predicate`) so ecma-family `indents.scm` files compile; core's `not-*?` auto-negation then covers `not-kind-eq?` for free.
- `lua/beast/libs/treesitter/config.lua` — **modified**. Add `indent = { enable = true }` alongside the existing `fold`/`highlight`/`context` toggles.
- `lua/beast/libs/treesitter/init.lua` — **modified**. `start_buf`: when `config.indent.enable` and `vim.treesitter.query.get(lang, "indents")` is non-nil, set `vim.bo[buf].indentexpr = "v:lua.require'beast.libs.treesitter.indent'.indentexpr()"`. The `ensure_queries` "changed" callback path (currently re-triggers highlight + context refresh) also re-checks and assigns `indentexpr` for buffers that didn't get it the first time because the query hadn't downloaded yet. `M.setup` requires `query_predicates` once.
- `tests/test-treesitter-indent.lua` — **new**. Headless test exercising `get_indent` against fixture buffers.
- `tests/fixtures/queries/lua/indents.scm` — **new**. A committed copy of the (already-synced) lua `indents.scm`, so the test is deterministic and doesn't depend on a network download or a pre-populated `~/.local/share/BeastVim` cache.

## Implementation Phases

## Phase 1: Core algorithm + wiring for core-predicate languages — get Lua/Python/JSON/Markdown/HTML indenting via treesitter
1. **`get_indent`/`indentexpr` implementation** (File: `lua/beast/libs/treesitter/indent.lua`)
   - Action: Implement the capture-walking algorithm: collect `indents` query captures for the buffer's (smallest enclosing, non-comment) parse tree; for the target line, walk from the first/last relevant node up through its ancestors, applying `@indent.begin`/`@indent.end`/`@indent.branch`/`@indent.dedent`/`@indent.align`/`@indent.auto`/`@indent.ignore`/`@indent.zero` the way the queries are designed to be interpreted (one indent step per "begin" ancestor not on the target line, one step back per "branch"/"dedent" match, `@indent.auto` and blank/comment lines returning -1 to copy the previous line, `@indent.zero` short-circuiting to 0). Use `vim.fn.shiftwidth()` for the step size. Memoize the per-`(bufnr, root, lang)` capture map (invalidate naturally since it's keyed by `root:id()`, which changes when the tree reparses).
   - Why: This is the actual feature — everything else is wiring.
   - Depends on: None
   - Risk: High (this is the one genuinely intricate piece; get Scenarios 1/2/4/6 passing against the Lua fixture before touching any other language)

2. **`config.indent.enable` toggle** (File: `lua/beast/libs/treesitter/config.lua`)
   - Action: Add `indent = { enable = true }` to `defaults`, matching the existing `fold`/`highlight` shape.
   - Why: Consistent, discoverable on/off switch alongside the other treesitter features; also gives a kill-switch if the algorithm misbehaves for some language without needing a revert.
   - Depends on: None
   - Risk: Low

3. **Wire `indentexpr` into `start_buf`** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: In `start_buf`, after the existing `fold.enable` block, add: if `config.indent.enable` and `vim.treesitter.query.get(lang, "indents")` is truthy, set `vim.bo[buf].indentexpr`. Extract the "has indents query" check into a small local helper so the `ensure_queries` changed-callback path (step 4) can reuse it.
   - Why: Mirrors the existing fold-wiring pattern exactly; the query-existence gate is what makes Scenario 5 (no parser → unchanged behavior) hold, since `'indentexpr'` must never be touched for those buffers.
   - Depends on: Step 1, Step 2
   - Risk: Low

4. **Retroactive assignment after async query download** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: In the `ensure_queries(lang, function(changed) ... end)` callback inside `start_buf` (currently loops `started` buffers to restart highlighting + refresh context), also (re-)apply the `indentexpr` gate from step 3 for each matching buffer.
   - Why: `indents.scm` may not exist on disk yet the first time `start_buf` runs (it's downloaded async) — without this, a buffer opened before the download completes would silently miss treesitter indent until its next `:e`/`FileType` trigger.
   - Depends on: Step 3
   - Risk: Low

5. **`kind-eq?` predicate registration** (File: `lua/beast/libs/treesitter/query_predicates.lua`, `lua/beast/libs/treesitter/init.lua`)
   - Action: New module registering `kind-eq?` via `vim.treesitter.query.add_predicate` (mirrors upstream nvim-treesitter's `plugin/query_predicates.lua` logic: check the captured node(s)' `:type()` against the predicate's string args). `require` it once, unconditionally, from `M.setup`.
   - Why: `ecma/indents.scm` (inherited by javascript/typescript/jsx/tsx) uses `#not-kind-eq?`; without this the query fails to compile and those languages silently get no treesitter indent (falls through to whatever `vim.treesitter.query.get` does on a bad query — must confirm it returns nil/errors gracefully rather than throwing into the indentexpr call path).
   - Depends on: None (can land independently of steps 1-4, but needed before JS/TS/JSX/TSX indent works)
   - Risk: Low

## Phase 2: Test coverage
1. **Fixture query + headless test** (File: `tests/fixtures/queries/lua/indents.scm`, `tests/test-treesitter-indent.lua`)
   - Action: Commit a copy of the lua `indents.scm` as a fixture; write a headless test (`nvim --clean --headless -l tests/test-treesitter-indent.lua`, following `tests/test-indent-scope.lua`'s rtp-prepend + stub-globals harness) that opens small Lua buffers covering each PM spec scenario (open line inside nested block, type-and-check a closing `end`, deeply nested tag-like structure via a Lua table constructor, blank line, whole-buffer reindent) and asserts `get_indent(lnum)` against expected columns.
   - Why: `'indentexpr'` is evaluated on every `Enter`/`o`/`=` — a regression here is felt constantly; needs a fast headless check, not just manual verification.
   - Depends on: Phase 1 step 1
   - Risk: Low

---

# Testing Strategy
- Headless tests: `nvim --clean --headless -l tests/test-treesitter-indent.lua` (new). Run alongside the existing suite (`test-indent-scope.lua` etc. are unaffected — different lib).
- Bench: `'indentexpr'` fires on every `Enter`/`o`/`=`/qualifying keystroke, so per `DEVELOPMENT.md` this is a hot path — run `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all` before merging (key-to-paint on `o`/Enter specifically) to confirm no perceptible latency regression versus the pre-change fallback indent.
- Manual: Walk through PM spec Scenarios 1-6 in a real buffer (`NVIM_APPNAME=BeastVim nvim`) per the memory note to always use `NVIM_APPNAME=BeastVim`:
  - A `.tsx`/`.jsx` file for Scenario 1/4 (nested tag → deeper indent) and Scenario 2 (closing tag dedent) — this is also the path that exercises the `kind-eq?` predicate (Phase 1 step 5).
  - A `.lua` file for Scenario 6 (`gg=G` reindent) and Scenario 3 (blank line / comment).
  - A filetype with no parser installed (e.g. open a `.txt` file, or temporarily rename a parser out of the way) for Scenario 5 — confirm `vim.bo.indentexpr` stays empty/untouched and behavior is bit-for-bit identical to before this change.

# Success Criteria
- [x] Opening a new line inside a nested tag/block indents one level deeper than the line that opened it, matching existing sibling content.
- [x] Typing a closing character dedents the line to match its opening line.
- [x] Deeply nested structures accumulate the correct total depth, not just one level.
- [x] Blank lines and comments get a sensible indent rather than fighting the writer.
- [x] Filetypes without a parser keep behaving exactly as they do today (`vim.bo.indentexpr` is never assigned for buffers whose language has no `indents` query).
- [x] Reindenting existing lines (`gg=G` / `=`) produces the same result as typing them fresh would.
- [x] `ecma`-derived languages (javascript/typescript/jsx/tsx) compile and apply their `indents.scm` correctly (validates the `kind-eq?` predicate).
- [ ] `./scripts/bench-ux.sh` shows no meaningful key-to-paint regression on `o`/Enter. Not run this session (no wezterm harness available) — worth a manual pass before this ships to daily use.

## Known limitation (discovered during implementation)
Neovim's built-in `typescriptreact`/`javascriptreact` ftplugins don't add `>` to `'indentkeys'`, so typing a JSX/TSX closing tag (e.g. `</footer>`) doesn't trigger an *immediate* reindent-on-type the way typing `}` does (default `indentkeys` already includes `0}`). The line still gets the right indent when opened via `o`/Enter or reindented via `gg=G`/`=` — only the "reindent the instant you finish typing the closing tag" sub-case of Scenario 2 is unaffected by this fix, because it's gated by `'indentkeys'`, which this feature deliberately never touches (touching it would mean overriding more than `'indentexpr'`, contradicting the Scenario 5 exact-parity requirement's minimal-footprint approach). Upstream nvim-treesitter has the same gap. Not fixed here; flagged for a follow-up decision if it turns out to matter in practice.

---

## Completed

**2026-08-02** — Both phases implemented in one session: the capture-walking algorithm, the per-buffer gate, async re-check, the `kind-eq?` predicate, and headless test coverage.

- `b2e38bc` feat(treesitter): add structure-aware indentexpr (`indent.lua`, `query_predicates.lua`, `config.lua` indent toggle, `init.lua` wiring — Phase 1 steps 1-5 landed as one commit; a code-reviewer pass caught and fixed two real bugs before commit: `resolve_align`'s third return value could regress `is_processed` back to `false` after an earlier begin/branch/dedent step had already set it `true`, and `get_root_for_line` was reparsing only the target line instead of the visible window, risking stale injected-tree discovery for HTML/Markdown)
- `fa4d979` test(treesitter): cover the indentexpr algorithm (Phase 2 — vendored lua `indents.scm` fixture + `tests/test-treesitter-indent.lua`, 10 assertions, all passing under `--clean`)

Verification: `stylua --check` clean on all touched/new files; full existing test suite run (`nvim --clean --headless -l tests/test-*.lua` for each) shows no regressions from this change (3 pre-existing, unrelated failures in `test-git-preview.lua`, `test-key-hint.lua`, `test-tabline-edge-trim.lua` — confirmed untouched by this diff, flagged to the user separately, not fixed here); manual end-to-end verification via headless `nvim --headless <file>` + simulated keypresses covered Lua (nested block open, `end` dedent, 3-level table nesting, blank-in-`if`), Python (`@indent.align` hanging/absolute/ERROR-promotion paths), TSX (nested JSX tag depth matching STATE 1, `}` dedent through the `kind-eq?`-gated ecma query), and the no-parser fallback (`.txt` file, `indentexpr` confirmed never assigned). `scripts/bench-ux.sh` was not run this session (no wezterm harness available in this environment) — flagged as outstanding in Success Criteria above.
