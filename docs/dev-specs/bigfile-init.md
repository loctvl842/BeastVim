---
name: bigfile-init
description: New `bigfile` lib that classifies a buffer as big once, and a one-line guard in each costly lib (treesitter, lsp, git, breadcrumb symbols, scroll, statuscolumn) that consults it, and a bounded scope search for the indent guides, which stay on
generated: 2026-11-25
---

> PM Spec: [docs/pm-specs/bigfile-init.md](../pm-specs/bigfile-init.md)

# Summary
Add `lua/beast/libs/bigfile/`, a small lib with one question it answers: "is this buffer big, and is feature X switched off for it?". Detection is lazy and memoized per buffer, so any lib can ask at any time without depending on autocmd order. Each costly lib gets a single early-return guard that calls it. The lib itself owns only the notice (Toast) and the window-local options (manual folds, no conceal, matchparen off).

---

# Context

## Problem
Nothing in the config knows a buffer is big. Treesitter highlight, indentexpr and the sticky context, indent guides, the LSP clients, git signs, the breadcrumb symbol trail, smooth scroll and the statuscolumn producers all run per redraw, per cursor move or per edit, so on `realistic_orders_120k.xml` (7.4 MB, 121,112 lines) every keystroke pays for all of them. Each lib has its own exclusion mechanism (`exclude_filetypes`, `buffer_eligible`, `is_ignored`, `vim.b.beast_scroll_disabled`) and none is driven by size.

### Solution
One lib owns the definition of "big" and the list of features to switch off. Libs do not learn about each other: each calls `Bigfile.disabled(buf, "<feature>")` at its own existing exclusion point. The decision is made on first ask (buffer loaded, size on disk and line count known), memoized until the buffer unloads, and announced with one Toast per open. The filetype is untouched.

---

# Research

## Repo Search
- Searched for: `bigfile`, `big_file`, `max_filesize`, `max_lines`, `large file` in `lua/`
  - Found: only `vim.g.matchparen_timeout` in `lua/beast/option.lua` (a cap, not a switch) and treesitter context `max_lines` (unrelated, a display budget). No size-based logic anywhere.
- Searched for: per-buffer disable flags (`vim.b.*disable*`)
  - Found: `vim.b.beast_scroll_disabled` (`lua/beast/libs/scroll/init.lua:69`, `buf_disabled`), `vim.b.beast_autopairs_disable` (autopairs, not touched). Scroll already has the guard; the others have per-lib exclusion points instead:
    - treesitter `start_buf` (`libs/treesitter/init.lua`), `apply_indentexpr`, context `can_show`/`update_win`
    - indent `is_excluded` (`libs/indent/init.lua:15`)
    - git `buffer_eligible` (`libs/git/init.lua:75`)
    - breadcrumb `symbols.trail`/`symbols.refresh` (`libs/breadcrumb/symbols/init.lua`) and `request_refresh`
    - lsp `register` (`libs/lsp/init.lua:122`) and the `LspAttach` dispatcher (`libs/lsp/attach.lua:152`)
    - statuscolumn producer dispatch (`libs/statuscolumn/init.lua`)
- Searched for: how notices are shown
  - Found: global `Toast(message, level, { title })` (`libs/toast/init.lua`); memory rule says notices go through Toast, not `vim.notify`.
- Searched for: lib layout rules
  - Found: `docs/development/lib-conventions.md` (init + config with read-only proxy, `M.meta`, `M.setup(opts)` the only config writer; user config key in `Beast.Config` in `lua/beast/init.lua`).
- Reuse opportunity: **Yes** - every existing exclusion point above; `View.win.wo` for window options (used by treesitter fold); Toast; the config proxy pattern from `libs/treesitter/config.lua`.

## Built-in / Existing Lib Check
- Checked: `vim.filetype.add` pattern function (what snacks uses), `BufReadPost`/`FileType` autocmd order, `vim.lsp.enable` internals (`lsp_enable_callback`/`can_start` in nvim 0.12.6), matchparen plugin, `vim.fn.getfsize`.
  - `vim.filetype.add` function: runs during detection, but forces the filetype to `bigfile` (loses `xml`) and its return value is the only output. Rejected: the PM spec keeps the real filetype.
  - Autocmd ordering: `filetypedetect` runs on `BufRead`, so a `BufReadPost` autocmd of ours would run after `FileType` consumers (treesitter's `FileType` handler). A flag set by an autocmd is therefore racy. A lazy `is(buf)` query has no ordering problem.
  - `vim.lsp.enable`: `can_start` has no per-buffer hook. The one place we control is `root_dir`: Neovim only starts a client when `on_dir(root)` is called, so a wrapped `root_dir` that does not call it prevents the start.
  - matchparen: `:NoMatchParen` is global. The plugin builds its pair list from `&matchpairs`, which is buffer-local, so an empty `matchpairs` disables it for one buffer (verify in Phase 4).
- Found: everything needed exists in Neovim and in the libs above.
- Decision: **Build** a small new lib (the classifier and notice are new) + **Reuse** each lib's existing exclusion point for the guard.

---

# Architecture Changes
- **New** `lua/beast/libs/bigfile/init.lua` - `M.meta`, `M.setup(opts)`, `M.is(buf)`, `M.disabled(buf, feature)`, `M.size(buf)` (for the notice); registers the `FileType` autocmd (notice + window options) and the `BufUnload`/`BufWipeout` cleanup.
- **New** `lua/beast/libs/bigfile/config.lua` - defaults (`enabled`, `notify`, `size`, `line_length`, `disable` feature table) and the read-only proxy.
- **New** `lua/beast/libs/bigfile/window.lua` - apply and restore window-local options (`foldmethod`, `conceallevel`) as a buffer enters and leaves a window.
- **New** `lua/beast/libs/bigfile/health.lua` - `:checkhealth beast.libs.bigfile` (lists the config and the current buffer's verdict).
- **Modified** `lua/beast/init.lua` - eager `require("beast.libs.bigfile").setup(cfg.bigfile or {})` (must exist before the first `FileType`), `_G.Bigfile` mod, `---@field bigfile? Beast.Bigfile.Config`.
- **Modified** `lua/beast/libs/treesitter/init.lua` - `start_buf` early-return and `apply_indentexpr` guard when `disabled(buf, "treesitter")`.
- **Modified** `lua/beast/libs/treesitter/context/init.lua` (or `context.lua`'s `can_show`) - no overlay for a window whose buffer is big.
- **Modified** `lua/beast/libs/indent/scope/init.lua` + `scope/indent.lua` - indent guides and scope stay on for a big buffer (PM decision after review), but `find` skips the treesitter strategy (it parses the whole file) and caps the indent walk at 1000 lines each way (a depth-1 XML block spans the whole file). `is_excluded` still honors `disable.indent = true`.
- **Modified** `lua/beast/libs/scroll/init.lua` - `buf_disabled` also asks bigfile (the existing `vim.b.beast_scroll_disabled` still works).
- **Modified** `lua/beast/libs/lsp/init.lua` + `lua/beast/libs/lsp/attach.lua` - `register` wraps `root_dir`; the `LspAttach` dispatcher detaches a client from a big buffer as a backstop.
- **Modified** `lua/beast/libs/git/init.lua` - `buffer_eligible` returns false for a big buffer.
- **Modified** `lua/beast/libs/breadcrumb/symbols/init.lua` (+ `breadcrumb/init.lua` `request_refresh`) - no symbol request or trail for a big buffer; the path part of the winbar stays.
- **Modified** `lua/beast/libs/statuscolumn/init.lua` - for a big buffer render the number producer only (no git, diagnostic or fold producers).
- **New** `test/libs/bigfile/bigfile_spec.lua` - classifier + notice + config; **New** guard specs next to each touched lib's existing spec.
- **New** `scripts/bench-bigfile.lua` - headless open-to-ready and per-keystroke cost with and without the guards.
- **Modified** `docs/CODEMAP/libraries.md` + `INDEX.md` - add the lib (via `/update-codemap`, not by hand).

## Public API (target shape)

```lua
Bigfile.is(buf)                -- boolean; lazy, memoized per loaded buffer
Bigfile.disabled(buf, feature) -- is(buf) and config.disable[feature] == true
Bigfile.size(buf)              -- bytes on disk, for the notice text
```

`feature` is one of: `treesitter`, `indent`, `lsp`, `git`, `breadcrumb`, `scroll`, `matchparen`, `fold`, `conceal`, `signs`.

Detection rules (from the PM spec): `buftype == ""`, non-empty name, buffer loaded, `getfsize > 0`; big when `size > config.size` or `(size - lines) / lines > config.line_length`. A buffer that is not loaded yet answers `false` and is not memoized (otherwise a 1-line placeholder would look like a minified file).

## Implementation Phases

## Phase 1: Classifier + notice - the lib exists, nothing consumes it yet
1. **Config** (File: `lua/beast/libs/bigfile/config.lua`)
   - Action: defaults `{ enabled = true, notify = true, size = 1.5 * 1024 * 1024, line_length = 1000, disable = { treesitter = true, indent = false, lsp = true, git = true, breadcrumb = true, scroll = true, matchparen = true, fold = true, conceal = true, signs = true } }`, read-only proxy, `Beast.Bigfile.Config` class.
   - Why: single source of truth (lib-conventions section 2); the `disable` table is the "list is configurable" rule.
   - Depends on: None
   - Risk: Low
2. **Classifier** (File: `lua/beast/libs/bigfile/init.lua`)
   - Action: `is`, `disabled`, `size`, memo keyed by buffer, cleared on `BufUnload`/`BufWipeout`; `enabled = false` makes `is` return false.
   - Why: lazy and order-independent (see Research).
   - Depends on: Step 1
   - Risk: Medium (the "not loaded yet" and `:e` cases)
3. **Notice + wiring** (File: `lua/beast/libs/bigfile/init.lua`, `lua/beast/init.lua`)
   - Action: `FileType` autocmd calls `Toast` once per open (a `notified[buf]` set cleared with the memo) with title "Big File", the file name and the size in KB/MB, unless `notify = false`; `lua/beast/init.lua` requires and sets up the lib eagerly and publishes `_G.Bigfile`.
   - Why: `nvim file` fires `FileType` during startup, before any `VimEnter` deferral, so setup cannot be lazy.
   - Depends on: Step 2
   - Risk: Medium (Toast must be usable during startup; verify with `nvim realistic_orders_120k.xml` straight from the shell)

## Phase 2: Cheap guards - treesitter, indent, scroll
1. **Treesitter** (File: `lua/beast/libs/treesitter/init.lua`, `lua/beast/libs/treesitter/context/`)
   - Action: `start_buf` returns early when `Bigfile.disabled(buf, "treesitter")` (covers highlight, fold and indentexpr); context `can_show` false for a big buffer.
   - Why: highlighter and context are the largest per-redraw costs.
   - Depends on: Phase 1
   - Risk: Low
2. **Indent guides** (File: `lua/beast/libs/indent/init.lua`, `indent/scope/init.lua`, `indent/scope/indent.lua`)
   - Action: guides and scope stay on by default (`disable.indent = false`). `is_excluded` still ORs in `Bigfile.disabled(buf, "indent")` for users who opt out. For a big buffer `scope.find` skips the treesitter strategy (`Bigfile.disabled(buf, "treesitter")`) and passes a 1000-line limit to the indent strategy's `expand`.
   - Why: the decoration provider only draws the viewport, but treesitter scope parses the whole buffer and the indent walk is O(block size) with one Vimscript call per line; both are unbounded on a 121k-line file.
   - Depends on: Phase 1
   - Risk: Low
3. **Scroll** (File: `lua/beast/libs/scroll/init.lua`)
   - Action: `buf_disabled` also asks `Bigfile.disabled(buf, "scroll")`.
   - Why: no animation delay on `Ctrl-D`/`G`.
   - Depends on: Phase 1
   - Risk: Low

## Phase 3: Background workers - LSP, git, breadcrumb symbols
1. **LSP** (File: `lua/beast/libs/lsp/init.lua`, `lua/beast/libs/lsp/attach.lua`)
   - Action: in `register`, wrap `lsp_cfg.root_dir` (after the `root_markers` conversion) so it does not call `on_dir` for a big buffer; `LspAttach` dispatcher detaches the client from a big buffer (backstop for servers without `root_dir`).
   - Why: do not even start the server for the file.
   - Depends on: Phase 1
   - Risk: High (single-file servers with no `root_dir`; a server shared with other buffers must keep serving them: detach only this buffer)
2. **Git** (File: `lua/beast/libs/git/init.lua`)
   - Action: `buffer_eligible` returns false for a big buffer.
   - Why: no diff pipeline, no `on_lines` subscription, no blame.
   - Depends on: Phase 1
   - Risk: Low
3. **Breadcrumb symbols** (File: `lua/beast/libs/breadcrumb/symbols/init.lua`, `lua/beast/libs/breadcrumb/init.lua`)
   - Action: `trail` returns `{}` and refresh requests are skipped for a big buffer.
   - Why: the path part of the winbar is cheap and stays.
   - Depends on: Phase 1
   - Risk: Low

## Phase 4: Window-local behavior - folds, conceal, matchparen, gutter
1. **Window options** (File: `lua/beast/libs/bigfile/window.lua`, `lua/beast/libs/bigfile/init.lua`)
   - Action: on `BufWinEnter` of a big buffer save the window's `foldmethod` and `conceallevel` into `vim.w`, set `manual` and `0`; on `BufWinEnter` of any other buffer in a window that has saved values, restore them. `matchparen`: set `&matchpairs` empty buffer-locally.
   - Why: these options belong to the window, so they leak into whatever buffer the window shows next unless restored (PM scenario 4).
   - Depends on: Phase 1
   - Risk: Medium (restore on `:e`, splits, `:b` in the same window)
2. **Statuscolumn** (File: `lua/beast/libs/statuscolumn/init.lua`)
   - Action: producer dispatch uses only the number slot for a big buffer.
   - Why: line numbers stay, signs and fold marks go.
   - Depends on: Phase 1
   - Risk: Medium (per-line `%!` call, the check must be a table lookup, not a size recomputation)
3. **Syntax gate** (File: none unless needed)
   - Action: confirm regex syntax still colors the sample XML responsively. If scrolling stutters, set `synmaxcol` through the same window-option mechanism and add `synmaxcol` to the config.
   - Why: the PM spec keeps simple coloring; it must not become the new bottleneck.
   - Depends on: Step 1
   - Risk: Medium

## Phase 5: Verify, bench, document
1. **Specs** (File: `test/libs/bigfile/bigfile_spec.lua` plus one assertion block per touched lib)
2. **Bench** (File: `scripts/bench-bigfile.lua`, plus `./scripts/bench-startup.sh` and `scripts/bench-ux.sh` per DEVELOPMENT.md)
3. **Docs** - run `/update-codemap`; do not hand-edit generated files.
   - Depends on: Phases 1 to 4
   - Risk: Low

---

# Testing Strategy
- Headless specs (`make test`), code under test in the child Nvim, files written to a temp dir:
  - `test/libs/bigfile/bigfile_spec.lua`: small file is not big; over `size` is big; few huge lines (minified) is big; new/empty/unreadable file is not; `buftype ~= ""` is not; a not-yet-loaded buffer answers false and is not memoized; `enabled = false` disables everything; `disable.<feature> = false` keeps that feature on; the decision survives `:e`; memo cleared after `:bwipeout` then reopen; one Toast per open (stub `Toast` with a recorder, never `vim.notify`); `notify = false` silences it; filetype stays `xml`.
  - Guard specs: treesitter highlighter not active and `indentexpr` empty for a big buffer, active for a small one in the same session; `indent` scope walk capped and treesitter skipped (guides stay on); `scroll` skips; git does not attach; breadcrumb trail is `{}`; LSP: the wrapped `root_dir` does not call `on_dir`, and a client forced to attach is detached from the big buffer only; statuscolumn renders the number only.
  - Window options: split showing big + normal buffer keeps `foldmethod`/`conceallevel` per buffer; switching a window big -> normal restores them.
- Bench: new `scripts/bench-bigfile.lua` (headless: open the fixture with guards on and off, time to ready and one `j`/`Ctrl-D` batch). Per DEVELOPMENT.md also run `./scripts/bench-startup.sh` (setup runs eagerly, so startup cost must be measured) and `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all` to prove normal files did not regress. Read `docs/development/writing-benches.md` before writing the new bench.
- Manual (the PM spec scenarios, as a checklist):
  - 1: `NVIM_APPNAME=BeastVim nvim realistic_orders_120k.xml` straight from the shell (startup path), then `j`, `Ctrl-D`, `G`, `50000G`, type, `/ORD-0099999` + `n`
  - 2: open `lua/beast/option.lua`, nothing changes
  - 3: generate a ~900 KB, 3-line file and open it
  - 4: `:vsplit lua/beast/init.lua` next to the big file, hop windows, `:b` the big file into the other window
  - 5: `:bd` and reopen (notice again), `:b#` back (no notice)
  - 6: `nvim new_file.xml`
  - 7: paste 10 MB into a small file, confirm nothing changes until reopen
- The fixture `realistic_orders_120k.xml` is untracked at the repo root. Do not commit it; move it out of the repo (or generate it inside the bench) before the final commit.

# Success Criteria
- [x] Opening `realistic_orders_120k.xml` shows exactly one "Big File" toast with name and size, including when launched from the shell.
- [x] In that file `j`, `Ctrl-D` and `G` feel instant; typing shows immediately (bench: key-to-paint no worse than a small file within the bench tolerance).
- [x] No treesitter highlighter, no context overlay, no LSP client attached, no git signs, no symbol trail in that buffer.
- [x] Line numbers, regex coloring, search, search count, undo, statusline still work.
- [x] A minified 900 KB file triggers the same behavior.
- [x] A small file in the same session (including a split next to the big one) keeps every feature.
- [x] Filetype of the big file is still `xml`.
- [x] `notify = false` silences the toast without re-enabling features; `disable.<feature> = false` keeps that feature.
- [x] Reopening the same big file shows the toast once per open.
- [x] `make test`, `lua-language-server --check` (Warning level) and `stylua` are clean; startup bench shows no measurable regression.

## Completed

2026-11-25 - all five phases, plus a mid-implementation change (indent guides stay on) and fixes from the code review.

- `5f3d5fc` feat(bigfile): detect big buffers lazily and announce them with a toast
- `5bc8ee5` feat(bigfile): switch off treesitter, indent guides and smooth scroll for big buffers (the indent part was reversed in `1a5ea38`: guides stay on)
- `fa04e8e` feat(bigfile): keep LSP, git signs and breadcrumb symbols off big buffers
- `1a5ea38` feat(bigfile): manual folds, no conceal, matchparen off and number-only gutter for big buffers (also: indent scope skips treesitter and caps its walk at 1000 lines)
- `463a7b3` fix(bigfile): show the file size in decimal MB like ls and the Finder
- `55df656` bench(ux): add an xml fixture language for the scroll scenario
- `903ca85` bench(ux): add an edit scenario (insert and undo mid-file in the big fixture)
- `45b2dce` fix(bigfile): write window options locally, keep the original on re-entry, wait for BufReadPre (code review findings)

Deviations from this spec: guard specs live in `test/libs/bigfile/guards_spec.lua` rather than beside each lib; benchmarking used new `bench-ux.sh` scenarios (`FIXTURE_LANG=xml`, `edit`) instead of `scripts/bench-bigfile.lua`; a split window that never held a record restores to the global option default. Known, left as is: `Lsp.register` always replaces a previously merged `root_dir`, and the `LspAttach` backstop detaches but does not stop an idle client.

Verification: `make test` 1997 passed (44 bigfile specs), `stylua --check` clean, `lua-language-server --check` no problems, startup 41.1 ms vs 40.7 ms before (noise), real `realistic_orders_120k.xml` in tmux (one toast "7.4 MB", guides and regex coloring on, number-only gutter, no symbol trail, split with a normal file keeps its features), jump to line 50000 about 35-60 ms vs 120-160 ms before. `bench-ux.sh scroll|edit` key-to-paint is flat (p50 under 2 ms before and after): the savings are in work between keys, not in paint.

