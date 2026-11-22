---
name: xml-init
description: xml.bvim language plugin (parser, auto-close tag) plus per-language XML element scope in the indent lib
generated: 2026-11-22
---

> PM Spec: [docs/pm-specs/xml-init.md](../pm-specs/xml-init.md)

# Summary

Add an `xml.bvim` language plugin next to `json.bvim` and `markdown.bvim`. It ensures the XML tree-sitter parser (which gives highlighting and, through the upstream `folds.scm`, element folds), and owns the auto-close tag insert mapping. In BeastVim itself, the parser gets a registry entry and the indent scope lib learns that `element` is a scope node for XML only, with single-line elements skipped so the enclosing element is marked.

---

# Context

## Problem

`xml` has no parser, so `start_buf` never runs for it: folds stay `foldmethod=indent`, and scope detection falls to `scope/indent.lua`, which returns one contiguous run around the cursor. Even with a parser, the tree path cannot work for XML today: `scope_types` has no `element`, a single-line element would return nil (body empty) instead of climbing, and a multi-line start tag has no `body` field to anchor the body start. There is no insert-mode tag closing anywhere (`autopairs` advertises "tags" in its description only; no `>` mapping exists).

### Solution

After the change: opening an XML file triggers the `xml` plugin, which ensures the parser. The install path already re-runs `start_buf` for open buffers, so highlight, fold (`foldexpr`) and `indentexpr` switch on without a reopen. The scope finder uses a per-language set (`xml = { "element" }`), climbs past single-line elements, and anchors the body after the start tag. The plugin maps `>` buffer-locally with the same `<Cmd>` + `press` pattern as `markdown.bvim`.

---

# Research

### Repo Search
- Searched for: `xml`, `autotag`, `auto.close`, `closetag`, `close_tag` across `lua/` and `docs/CODEMAP`; `scope_types`, `find_scope_node`; the `ensure_parser` / `parsers.get` path; how `lang.lua` registers `*.bvim` plugins; `tests/test-indent-scope*.lua`.
- Found:
  - No XML code anywhere. `parsers.lua` has no `xml` entry; the fallback convention URL `tree-sitter/tree-sitter-xml` does not exist (the grammar is `tree-sitter-grammars/tree-sitter-xml`, `location = "xml"`, ships `src/parser.c` + `scanner.c`, so no `generate`). The pin used by nvim-treesitter is `5000ae8f22d11fbe93939b05c1e37cf21117162d`.
  - `install.lua` already downloads `folds.scm`, `indents.scm`, `highlights.scm` from nvim-treesitter `main` for any language. Upstream `xml/folds.scm` is `[(element) (doctypedecl) (Comment)] @fold`. Upstream `xml/indents.scm` exists, so `apply_indentexpr` will also turn on tree-sitter indenting for XML.
  - `autopairs` maps `()`, `[]`, `{}`, quotes, backtick only; no `>`/`<`. Its `keymap.lua` is global, not per-filetype.
  - `markdown.bvim` is the working template: `setup()` checks globals, `Treesitter.ensure_parser`, `FileType` autocmd plus a loop over already-open buffers (setup runs on the very FileType that lazy-loaded it), buffer-local insert mappings through `Key.safe_set` that return a constant `<Cmd>` calling `press` (decision made at run time, not while Neovim peeks queued keys; works behind blink.cmp), a `fallback(lhs)` for a pre-existing global mapping, and `tests/test-lists.lua` with stub globals.
  - `scope/treesitter.lua` `find_scope_node` matches on node type only (global set), returns nil for a single-line scope node (`body_from > body_to`), and only knows a `body` field for header wrapping. `collect_segments` already splits on shallower lines, which gives the two stretches (34 and 36) the PM spec expects once an `element` node is found.
  - `tests/test-indent-scope-treesitter.lua` skips a case when its parser is not installed; pattern for new XML cases.
- Reuse opportunity: **Yes.** `collect_segments`, the whole parser install/query sync path, `markdown.bvim`'s plugin structure and test harness.

### Built-in / Existing Lib Check
- Checked: `vim.treesitter.foldexpr`, `Treesitter.ensure_parser`, `Key.safe_set`, `autopairs`, `nvim_buf_set_text`, `<C-g>U`, an `InsertCharPre` autocmd.
- Found: folds, highlight and indent come free from the parser plus upstream queries. `autopairs` cannot host a per-filetype `>` without a new mechanism. `InsertCharPre` cannot modify text safely and would not cooperate with blink.cmp; the `<Cmd>` mapping pattern already proved itself in `markdown.bvim`.
- Decision: **Reuse** (parser pipeline, scope segments, plugin template). **Build** (auto-close text analysis, per-language scope types, start-tag anchoring).

---

# Decisions for you

1. **Where `element` becomes a scope type.** Recommended: per-language (`scope_types_by_lang = { xml = { "element" } }`). The HTML grammar also names its nodes `element`, so a global entry would change HTML scope drawing, which the PM spec puts out of scope. Alternative: global entry, simpler but changes HTML.
2. **Upstream folds also fold multi-line comments and the doctype.** The PM spec rule says folds are for multi-line elements. Recommended: accept the upstream query as is (same query set as every other language, no local fork to maintain) and treat the PM rule as "elements fold; comments and doctype may too". Alternative: ship a local `folds.scm` override, which means owning a query.
3. **Auto-close lives in `xml.bvim`**, not `autopairs`. Recommended: it is XML-only behaviour and `autopairs` has no filetype scoping. A shared HTML/JSX later can lift the pure function out then.
4. **Side effect to expect:** upstream `indents.scm` turns on tree-sitter `indentexpr` for XML, so `o` and `<CR>` now indent by element depth. Intended, but visible; not in the PM spec.

---

# Architecture Changes

BeastVim repo (`/Users/loctvl842/.config/BeastVim`):
- **Modified** `lua/beast/libs/treesitter/parsers.lua` - add `xml` entry (url, pinned revision, `location = "xml"`).
- **Modified** `lua/beast/libs/indent/config.lua` - add `scope.treesitter.scope_types_by_lang` with `xml = { "element" }`.
- **Modified** `lua/beast/libs/indent/scope/treesitter.lua` - per-language type set (cached per lang), climb past single-line nodes of per-language types, anchor body after the start tag when there is no `body` field.
- **Modified** `tests/test-indent-scope-treesitter.lua` - XML cases.
- **Modified** `lua/beast/plugins/lang.lua` - `xml` plugin spec, `lazy = { filetype = "xml" }`.
- **Modified** `docs/CODEMAP/libraries.md` - indent config key, lang plugin list (via `/update-codemap`).

New plugin repo (`/Users/loctvl842/Documents/Beast/Developments/neovim_plugins/xml.bvim`):
- **New** `lua/xml/init.lua` - `setup()`: globals check, `Treesitter.ensure_parser("xml")`, FileType autocmd + loop over open buffers, buffer-local `>` mapping.
- **New** `lua/xml/autoclose.lua` - pure `closing_tag(before, after)` and the run-time `press()`.
- **New** `tests/test-autoclose.lua`, `README.md`, `stylua.toml`, `.luarc.json`, `.git`.

## Implementation Phases

## Phase 1: Parser and folds - XML gets highlighting and element folds

1. **Registry entry** (File: `lua/beast/libs/treesitter/parsers.lua`)
   - Action: add `xml = { url = "https://github.com/tree-sitter-grammars/tree-sitter-xml", revision = "5000ae8f22d11fbe93939b05c1e37cf21117162d", location = "xml" }`.
   - Why: the convention fallback URL does not exist.
   - Depends on: None
   - Risk: Low
2. **Scaffold plugin** (File: `xml.bvim/` via the `new-lang` conventions, minus LSP)
   - Action: `lua/xml/init.lua` with the globals check (`Treesitter`, later `Key`), `Treesitter.ensure_parser("xml")`; README, `stylua.toml`, `.luarc.json` (globals `vim`, `Key`, `Treesitter`); `git init`.
   - Why: parser ensure is what triggers install for languages not in `ensure_installed`.
   - Depends on: Step 1
   - Risk: Low
3. **Register in BeastVim** (File: `lua/beast/plugins/lang.lua`)
   - Action: add the `xml` spec after `json`. The `src` is `gh("BeastVim/xml.bvim")`, so this step is **blocked on the GitHub repo existing**; until then verify by placing the plugin on the runtimepath manually. Creating and pushing that repo is outward-facing and yours to do.
   - Depends on: Step 2
   - Risk: Medium (remote not created yet)

## Phase 2: Element scope - the reported bug

1. **Per-language scope types** (Files: `lua/beast/libs/indent/config.lua`, `scope/treesitter.lua`)
   - Action: add `scope_types_by_lang`; build the matching set from `parser:lang()` plus the global list; cache per lang; `invalidate()` clears all.
   - Why: decision 1.
   - Depends on: None
   - Risk: Medium (config shape is public)
2. **Skip single-line elements** (File: `scope/treesitter.lua`)
   - Action: in `find_scope_node`, a node matched through the per-language set whose start and end rows are equal is skipped and the climb continues. Global types keep today's behaviour (nil falls to indent), so other languages do not change.
   - Why: PM scenario 3.
   - Depends on: Step 1
   - Risk: Medium
3. **Anchor the body after the start tag** (File: `scope/treesitter.lua`)
   - Action: when `scope_node:field("body")` is empty and the first child is `STag`, set `body_from = max(body_from, stag_end_row + 2)`. Wrapped attributes then do not count as body.
   - Why: XML start tags routinely span lines; the existing `body` field logic does not apply.
   - Depends on: Step 1
   - Risk: Medium
4. **Tests** (File: `tests/test-indent-scope-treesitter.lua`)
   - Action: add cases (skipped when no parser): the reported case (cursor 34, expect `{34,34}` and `{36,36}`, col 6, indent 8); cursor on 35 (single-line) gives the same; cursor on opening and closing tag give the same element; nested innermost; wrapped start tag; broken XML (missing closer) does not error; HTML buffer unchanged (no `element` scope).
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 3: Auto-close tag

1. **Pure analysis** (File: `xml.bvim/lua/xml/autoclose.lua`)
   - Action: `closing_tag(before, after)` returns the closing text or nil. `before` is the text from the last `<` to the cursor, scanning back at most 50 lines. Rules: quoted values are collapsed first; a remaining open quote returns nil; a `>`, a trailing `/`, a name that does not match `[A-Za-z_][%w:._-]*` (so `</x`, `<!`, `<?`, `< b`) return nil; `after` already starting with `</name>` returns nil. Result is `</name>`.
   - Depends on: None
   - Risk: Low
2. **Run-time press and mapping** (Files: `autoclose.lua`, `lua/xml/init.lua`)
   - Action: `Key.safe_set("i", ">", constant <Cmd> -> press, { buffer, expr, replace_keycodes = false, noremap })`, as in `markdown.bvim`. `press` reads the buffer at run time; no closing tag: feed a plain `>` (or the previous expr mapping, same `fallback` idea); closing tag: insert `>` and `</name>` and put the cursor between using keys that keep one undo step (`<C-g>U<Left>` repeated), fed with `nvim_feedkeys(..., "ni")`.
   - Why: PM rules (one undo, not on paste, exact name incl. prefix). Paste never goes through the mapping.
   - Depends on: Step 1
   - Risk: Medium (blink.cmp, dot-repeat, undo)
3. **Attach** (File: `lua/xml/init.lua`)
   - Action: FileType autocmd on `xml` plus a loop over already-open xml buffers.
   - Depends on: Step 2
   - Risk: Low
4. **Tests** (File: `xml.bvim/tests/test-autoclose.lua`)
   - Action: stub `Key`/`Treesitter` as in `markdown.bvim/tests/test-lists.lua`. Cover every PM scenario 8 and 9 line, multi-line start tag, one-undo, dot-repeat, behind a global `>` mapping, behind blink.cmp's mappings.
   - Depends on: Step 2
   - Risk: Low

## Phase 4: Docs

1. **Codemap and README** (Files: `docs/CODEMAP/libraries.md`, `xml.bvim/README.md`)
   - Action: run `/update-codemap`; document install snippet, features, the `scope_types_by_lang` option. No CHANGELOG edits.
   - Depends on: Phases 1-3
   - Risk: Low

---

# Testing Strategy

- Headless tests: `NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-indent-scope-treesitter.lua`, plus `test-indent-scope.lua` and `test-indent-scope-draw.lua` for regressions; in `xml.bvim`: `nvim --clean --headless -l tests/test-autoclose.lua`. Type check with the lua-language-server command in `DEVELOPMENT.md`.
- Bench: scope detection is on the cursor-move path, so run `tests/bench-scope.lua` and `scripts/bench-*.lua` for the indent lib before and after Phase 2; per-language set lookup must not add measurable cost. If a bench for statuscolumn/fold is affected, run `./scripts/bench-ux.sh all`.
- Manual (E2E, per the repo's bug-fix rule, reproduce first): in a tmux pane, `NVIM_APPNAME=BeastVim nvim complex.xml`, run `:lua require("beast.libs.indent.scope").debug()` at 34:12 before the change (expect your single run) and after (expect two). Then walk PM scenarios 1 to 9. Scenario 6: remove the installed `xml` parser under `~/.local/share/BeastVim/site/parser/` and reopen. Check pixel details: sign position, element line column, closed-fold glyph.

# Success Criteria

- [x] In `complex.xml`, no fold sign on lines 34, 35 or 36; signs on 32 and 33 and every other multi-line element.
- [x] Cursor at 34:12 draws the element line on 34 and 36, not 35; `debug()` lists `{from=34,to=34}` and `{from=36,to=36}`, both `col=6`, `indent=8`.
- [x] Cursor on line 35 (single-line element), on 33 (opening tag) and 37 (closing tag) marks the annotation element.
- [x] `zc` inside an element folds everything between its tags; the opening and closing tag stay visible (amendment).
- [x] First open without the parser works without restart once installed.
- [x] A file with a missing closing tag opens with no errors and complete elements still fold and mark.
- [x] `<class` + `>` gives `<class>|</class>`; prefix names keep the prefix; self-closing, closing, comment, declaration, doctype, quoted `>` and existing closer add nothing; one undo reverts both.
- [x] HTML and all existing indent scope tests are unchanged; scope bench shows no regression.
- [x] `lua-language-server --check` passes.

---

# Amendment 2026-11-22: folded element keeps its closing tag

Feedback after implementation: a closed fold must still show the closing tag. This supersedes decision 2 (accept upstream folds): `xml.bvim` now replaces the `folds` query for `xml` with `vim.treesitter.query.set` in `setup()`, where `element` is captured with `(#offset! @fold 0 0 -1 0)` so the fold ends one line early and the closing tag line stays visible; `doctypedecl` and `Comment` keep the upstream capture. `query.set` is used over a `queries/xml/folds.scm` file because the file would lose to the one the installer syncs into `site/` depending on runtimepath order. Elements with nothing between their tags get no fold of their own (PM scenario 5, step 4). Test: `xml.bvim/tests/test-folds.lua`.

---

# Completed

2026-11-22. Phases 1 (except the `lang.lua` registration), 2, 3 and 4 done.

BeastVim (`/Users/loctvl842/.config/BeastVim`):
- `ff28f51` feat(treesitter): register the xml parser
- `0cf0479` feat(indent): xml element scope with per-language scope types
- `f06c9b4` docs: xml pm and dev specs, codemap notes for per-language scope types

xml.bvim (`/Users/loctvl842/Documents/Beast/Developments/neovim_plugins/xml.bvim`, its own repo, no remote yet):
- `77749af` feat: scaffold the xml plugin and ensure the xml parser
- `0f2cb1c` feat: close the opening tag when > is typed
- `7fc75b2` docs: describe the auto-close tag
- `53a44ed` feat: keep the closing tag visible when an element is folded (amendment above; `tests/test-folds.lua` 6/6)

Not done: Phase 1 step 3, the `xml` spec in `lua/beast/plugins/lang.lua`. It is blocked on `BeastVim/xml.bvim` existing on GitHub; adding the spec first would make BeastVim try to fetch a missing repo. Verified with the plugin on the runtimepath instead.

Deviations from the plan:
- No fallback to a previous global `>` mapping (nothing maps `>` today); `>` falls back to the plain key. No blink.cmp wrapper test for the same reason.
- Decision 4 did not materialise: XML buffers kept Neovim's own `XmlIndentGet` indentexpr (the tree-sitter `indentexpr` was not applied), so `o` and `<CR>` indenting is unchanged.
- Known limit: typing `<b>` inside a comment or CDATA still closes the tag.

Verification: `test-indent-scope-treesitter` 16/16, `test-indent-scope` 35/35, `test-indent-scope-draw` 6/6, plugin `test-autoclose` 36/36; `lua-language-server --check` clean; `stylua --check` clean. `bench-scope`: treesitter path 4.04 to 4.15 us/call (+0.1 us, on a 30 ms debounced path). E2E in tmux on `complex.xml` with the real config: signs only on 32 and 33 (not 34 to 36), scope line at column 6 on 34 and 36 and none on 35, `zc` inside folds the whole annotation, `<class>` + `>` gives `<class>|</class>` and one `u` undoes it, and with the parser removed beforehand the same session switched to tree-sitter folds and highlighting once it installed.
