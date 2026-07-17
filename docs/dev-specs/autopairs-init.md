---
name: autopairs-init
description: "Beast Autopairs Library"
generated: 2026-06-08
---

> **Completed:** 2026-06-08. All three phases shipped.
> Commits: Phase 1 `f348436`, Phase 2 `2c893d0`, Phase 3 (this commit).
> Tests: `tests/test-autopairs-engine.lua` (53/53), `tests/test-autopairs-skip.lua` (28/28).

# Summary

Native autopairs library at `lua/beast/libs/autopairs/` that owns the entire
keymap engine, neighborhood matching, `<BS>`/`<CR>` handling, and the smart
veto layer (skip-next, treesitter-aware skip, unbalanced-line skip, markdown
triple-backtick expansion). No dependency on `mini.pairs` or `nvim-autopairs`.

The architecture follows the same recipe `mini.pairs` itself uses — each
paired key becomes an `<expr>` mapping returning a keystroke string. Vetoes
are pure functions composed in front of the action. This shape is why undo,
dot-repeat, and macros all work for free: Neovim never sees a plugin in the
loop, it sees keystrokes.

The lib ships in three independently mergeable phases:

1. **Engine** — pair registry, `open`/`close`/`closeopen`/`bs`/`cr` actions,
   neighborhood matcher, keymap installer. Functionally equivalent to vanilla
   `mini.pairs` minus smart vetoes. Not yet wired.
2. **Smart vetoes** — `skip_next`, `skip_ts`, `skip_unbalanced`, `markdown`
   fence expansion, plus per-buffer/global disable flag. Still not wired.
3. **Wire-up & cutover** — `packer.lazy(...)` in `beast/init.lua`, remove the
   `mini.pairs` plugin entry from `lua/beast/plugins/init.lua`, health check.

**Public API:**

```lua
local autopairs = require("beast.libs.autopairs")
autopairs.setup({
  pairs = { ... },             -- override or extend the default pair table
  modes = { insert = true, command = true },
  skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
  skip_ts = { "string" },
  skip_unbalanced = true,
  markdown = true,
})
autopairs.enable()             -- (re)install mappings
autopairs.disable()            -- remove mappings
autopairs.toggle()             -- flip global enable flag
```

Per-buffer opt-out: `vim.b.beast_autopairs_disable = true`.
Global opt-out: `vim.g.beast_autopairs_disable = true` (also flipped by
`<leader>up` once Phase 3 adds the keymap).

# Requirements

### Functional

- **Engine**
  - Install `<expr>` mappings in insert mode (and cmdline when configured) for
    each registered pair character.
  - Three primitive actions:
    - `open` — return `"<o><c><Left>"` when the neighborhood matches; else `o`.
    - `close` — if next char == close char, return `<Right>` (jump over); else
      insert literal `c`.
    - `closeopen` — for symmetric chars (`"`, `'`, `` ` ``): if next char == c,
      jump over; else fall through to `open`.
  - `<BS>` between an open/close pair returns `"<BS><Del>"` (deletes both).
  - `<CR>` between an open/close pair returns `"<CR><C-o>O"` (newline below,
    open line above in normal mode → cursor lands indented in the middle).
  - Neighborhood matcher: each pair carries a Lua pattern matched against
    `[char_before][char_after]`. Default per pair type:
    - Brackets `( [ {`: `"[^\\]."`  (don't pair after backslash)
    - Quotes `" ' `` `: `"[^%w\\\"][^%w]"`  (don't pair adjacent to wordy text)
  - Pair table is configurable. Default set: `() [] {} "" '' \`\``.
- **Smart vetoes** (applied inside the `open` path, before fall-through)
  - `skip_next` — when next char matches the supplied Lua pattern, return just
    the open char.
  - `skip_ts` — when cursor's treesitter capture (via
    `vim.treesitter.get_captures_at_pos`) is in the list (default
    `{ "string" }`), return just the open char.
  - `skip_unbalanced` — when next char equals close char AND open ≠ close
    AND line has more closers than openers, return just the open char.
  - `markdown` — when typing `` ` `` in a markdown buffer and the line so far
    matches `^%s*``` `` (two backticks), expand to a full ` ```…``` ` fence
    with cursor positioned inside.
- **Lifecycle**
  - `setup(opts)` merges config, registers `:checkhealth` provider, but does
    NOT install mappings on its own — installation happens on first
    `InsertEnter` (via `packer.lazy`).
  - `enable()` is idempotent — calling twice does not double-map.
  - `disable()` unmaps cleanly (no orphaned mappings).
  - Per-buffer disable flag: respected at action time (early return into
    literal char). Per-buffer disable does NOT remove mappings — it
    short-circuits them, so toggling is instant and cheap.
- **Mapping installation** uses `Key.safe_set` so the keys appear in the
  managed registry and cheatsheet.

### Non-Functional

- **No external plugin dependency.** Pure Lua + Neovim core APIs (`vim.api`,
  `vim.fn`, `vim.bo`, `vim.b`, `vim.g`, `vim.treesitter`).
- **State only in `init.lua`** — `pairs.lua`, `actions.lua`, `skip.lua`,
  `keymap.lua` are stateless modules (pure functions or constructors). This
  matches the established BeastVim convention (see `breadcrumb-init.md`
  § *State Ownership*).
- **Config is frozen** via metatable, identical to
  `lua/beast/libs/confirm/config.lua` — direct assignment raises a clear
  error; mutation goes through `setup()`.
- **Type names**: `Beast.Autopairs.Config`, `Beast.Autopairs.Pair`,
  `Beast.Autopairs.Opts`.
- **No reliance on `vim.fn.feedkeys`** for normal autopair behavior.
  Everything is `<expr>` returning keystrokes — required for dot-repeat and
  macro replay to work correctly.
- **No bench script.** Autopairs runs at human typing speed (≤ ~10 keystrokes
  per second); a microbenchmark provides no actionable signal. Performance is
  guarded by unit tests on the pure functions.

### Out of Scope

- **Fast-wrap** (Alt-E in `nvim-autopairs` style) — could be a follow-up spec.
- **Treesitter-rule-based pairs** (e.g., open `<>` only inside JSX) — Phase 2
  vetoes are filetype/treesitter-aware but the pair set itself is static per
  config.
- **Multi-char pairs** (`/*  */`, ` <%  %> `) — same limitation as
  `mini.pairs`; use snippets.
- **Completion engine integration** — BeastVim's `blink.cmp` uses
  `accept = { auto_brackets = { enabled = false } }`, so there's no
  cross-coordination needed. If `auto_brackets` is enabled later, that's a
  separate spec.
- **Wiring into `lua/beast/init.lua`** is done in Phase 3 of this spec
  (different from breadcrumb where wiring was deferred — here the cutover
  removes `mini.pairs` and is part of the deliverable).

# Research

### Repo Search

- Searched for: `autopairs`, `mini.pairs`, `nvim-autopairs`, `<BS>`, `<CR>`,
  insert-mode keymap setup, treesitter-capture-at-cursor.
- Found:
  - `lua/beast/plugins/init.lua:21` — recently added `mini.pairs` plugin entry
    with inline LazyVim-style monkey-patch wrapper (~60 lines). **This is the
    code being replaced.** Wrapper logic (skip_next/skip_ts/skip_unbalanced/
    markdown) maps 1:1 to the `skip.lua` module planned in Phase 2.
  - `lua/beast/libs/key/core.lua` — `Key.safe_set(mode, lhs, rhs, opts)`.
    Used by every lib that installs keymaps. Required here for managed
    registry + cheatsheet visibility (`group = "Autopairs"`).
  - `lua/beast/libs/confirm/config.lua` — frozen-config metatable pattern.
    Adopted verbatim for `autopairs/config.lua`.
  - `lua/beast/libs/confirm/health.lua` — `:checkhealth` template (Neovim
    version check, module-loaded check, API-contract probes, config dump).
    Adopted as the shape for `autopairs/health.lua`.
  - `lua/beast/libs/breadcrumb/init.lua` — example of state-in-init.lua with
    `setup()` and a separate lazy `ensure_autocmds()` guard. Same shape used
    here, except autopairs registers keymaps (via `Key.safe_set`) instead of
    autocmds.
  - `lua/beast/libs/scroll/init.lua` — example with `enable()`/`disable()`/
    `toggle()` triplet. Same triplet exported here.
  - `tests/test-tabline-edge-trim.lua` and `tests/test-indent-scope.lua` —
    headless test convention: `nvim --clean --headless -l tests/X.lua`,
    `package.path` prepend, exit code 0 = pass / 1 = fail, `assert_test`
    helper that prints `PASS`/`FAIL` lines. **Adopted directly.** No external
    test framework.
- Reuse opportunity:
  - **Adopt** `Key.safe_set` for mapping installation.
  - **Adopt** confirm's frozen-config metatable.
  - **Adopt** confirm's `:checkhealth` shape.
  - **Adopt** the existing headless test runner pattern.
  - No existing autopairs code in the repo. Build from scratch is the right
    call.

### Package Search

- Searched: native Neovim APIs for insert-mode `<expr>` mappings, treesitter
  capture lookup, cursor/line read.
- Found:
  - `vim.keymap.set("i", lhs, rhs, { expr = true })` — what `Key.safe_set`
    eventually calls. `rhs` is a function returning a string; that string is
    interpreted as keystrokes (with `<CR>`/`<BS>` decoded via
    `vim.api.nvim_replace_termcodes`).
  - `vim.api.nvim_get_current_line()` — line under cursor (1 syscall, ns
    range).
  - `vim.api.nvim_win_get_cursor(0)` — `{row, col}` (col is byte index, 0-based).
  - `vim.treesitter.get_captures_at_pos(bufnr, row, col)` — returns
    `{ {capture, lang, metadata}, ... }`. Already used by LazyVim's wrapper.
    Wrapped in `pcall` because it errors on buffers without an active parser.
  - `vim.api.nvim_replace_termcodes("<CR>", true, true, true)` — used for
    `<CR>`/`<BS>`/`<Left>`/`<Right>`/`<Up>` in returned strings.
  - `vim.fn.getcmdline()` / `vim.fn.getcmdtype()` — to disambiguate cmdline
    vs insert mode inside the same expression mapping.
- Decision: **Build** — entirely on top of native APIs. No plugin needed.
  This is the third "small custom lib instead of plugin" decision in BeastVim
  (after `confirm`, `notify`); the pattern is well-established.

# Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/autopairs/config.lua` | Create (Phase 1) | Frozen-config metatable, defaults, `setup()`. |
| `lua/beast/libs/autopairs/pairs.lua` | Create (Phase 1) | Default pair registry, neighborhood matcher (pure). |
| `lua/beast/libs/autopairs/actions.lua` | Create (Phase 1) | `open`, `close`, `closeopen`, `bs`, `cr` — pure functions returning keystroke strings. |
| `lua/beast/libs/autopairs/keymap.lua` | Create (Phase 1) | Install/uninstall `<expr>` mappings via `Key.safe_set`. |
| `lua/beast/libs/autopairs/init.lua` | Create (Phase 1) | Public API: `setup`/`enable`/`disable`/`toggle`, state, lazy init guard. |
| `tests/test-autopairs-engine.lua` | Create (Phase 1) | Unit tests for `pairs.lua`, `actions.lua`, `keymap.lua` behavior. |
| `lua/beast/libs/autopairs/skip.lua` | Create (Phase 2) | The four vetoes: `skip_next`, `skip_ts`, `skip_unbalanced`, `markdown`. |
| `lua/beast/libs/autopairs/actions.lua` | Modify (Phase 2) | `open` action calls `skip.evaluate(ctx)` first; literal fall-through on veto. |
| `tests/test-autopairs-skip.lua` | Create (Phase 2) | Unit tests for each veto rule (table-driven). |
| `lua/beast/libs/autopairs/health.lua` | Create (Phase 3) | `:checkhealth` provider matching confirm's shape. |
| `lua/beast/init.lua` | Modify (Phase 3) | Add `packer.lazy("beast.libs.autopairs", { event = "InsertEnter", ... })` + extend `Beast.Config` type. |
| `lua/beast/plugins/init.lua` | Modify (Phase 3) | Remove the `mini.pairs` entry added 2026-06-08. |

# Implementation Phases

### Phase 1: Engine — pair registry, actions, keymap installer, BS/CR

This phase ships a working autopairs engine and all unit tests, but does NOT
wire it into `beast/init.lua` (`mini.pairs` remains active in plugins/init.lua).
The lib is verifiable via `require("beast.libs.autopairs").enable()` from
`:lua` and the headless test suite.

1. **Create `config.lua`** (File: `lua/beast/libs/autopairs/config.lua`)
   - Action: Define `Beast.Autopairs.Config` with fields:
     - `enabled = true`
     - `modes = { insert = true, command = true, terminal = false }`
     - `pairs` — table keyed by open char, value `{ close, neigh_pattern, register = { bs, cr } }`. Defaults: `( [ {` brackets with `"[^\\]."`; `" ' \``  symmetric with `"[^%w\\\"][^%w]"`.
     - Reserve fields for Phase 2 (`skip_next = nil, skip_ts = nil, skip_unbalanced = false, markdown = false`) so the type is stable across phases.
     - Frozen metatable pattern from `confirm/config.lua` — `__newindex` raises, methods table for `setup()`.
   - Why: Every other module reads config inline; defining shape up front prevents Phase 2 from needing config shape changes.
   - Depends on: None
   - Risk: Low

2. **Create `pairs.lua`** (File: `lua/beast/libs/autopairs/pairs.lua`)
   - Action: Pure module exporting:
     - `M.neigh_matches(neigh_pattern, before, after)` → boolean. `before` and `after` are single chars (`""` allowed when at line edge). Implementation: `(before .. after):match("^" .. neigh_pattern .. "$") ~= nil`.
     - `M.is_symmetric(pair_spec)` → boolean (open == close).
     - `M.iter_active(cfg)` → iterator yielding `(open_char, spec)` for use by the keymap installer.
   - Why: Single source of truth for the "should we pair here?" primitive. Pure → trivially unit-testable.
   - Depends on: Step 1
   - Risk: Low

3. **Create `actions.lua`** (File: `lua/beast/libs/autopairs/actions.lua`)
   - Action: Five pure-ish functions. Each takes a `ctx` table built by `keymap.lua` (`{open, close, neigh_pattern, line, col, mode}`) and returns the keystroke string to feed back.
     - `M.open(ctx)`:
       - If `vim.b.beast_autopairs_disable` or `vim.g.beast_autopairs_disable`: return `ctx.open`.
       - Compute `before = line:sub(col, col)`, `after = line:sub(col+1, col+1)`.
       - If `pairs.neigh_matches(ctx.neigh_pattern, before, after)`: return `ctx.open .. ctx.close .. nvim_replace_termcodes("<Left>")`.
       - Else: return `ctx.open`.
     - `M.close(ctx)`:
       - If next char == `ctx.close`: return `<Right>`.
       - Else: return `ctx.close`.
     - `M.closeopen(ctx)`:
       - If next char == `ctx.close`: return `<Right>`.
       - Else delegate to `M.open(ctx)`.
     - `M.bs(ctx)`:
       - If `before == ctx.open` and `after == ctx.close`: return `<BS><Del>`.
       - Else: return `<BS>`.
     - `M.cr(ctx)`:
       - If `before == ctx.open` and `after == ctx.close`: return `<CR><C-o>O`.
       - Else: return `<CR>`.
   - Why: All branching logic in one stateless file. Tests drive these functions directly with synthetic ctx tables.
   - Depends on: Step 2
   - Risk: Low — but get the termcode decoding right (cache results from `nvim_replace_termcodes` at module load).

4. **Create `keymap.lua`** (File: `lua/beast/libs/autopairs/keymap.lua`)
   - Action: Two functions:
     - `M.install(cfg, registry)` — for each `(open, spec)` from `pairs.iter_active(cfg)`:
       - If symmetric: install `closeopen` on `open` (open == close).
       - Else: install `open` on `open` and `close` on `spec.close`.
       - Install `bs` on `<BS>` and `cr` on `<CR>` once globally (not per pair). When fired, `bs`/`cr` walk the configured pairs and check `(before, after)` against each — match wins.
       - All keymaps installed in modes from `cfg.modes` via `Key.safe_set(mode, lhs, fn, { expr = true, group = "Autopairs", desc = ... })`. Store every installed `{mode, lhs}` in `registry` for `uninstall()`.
     - `M.uninstall(registry)` — `pcall(vim.keymap.del, mode, lhs)` for each entry; clear `registry`.
   - Why: Centralizes mapping side effects. Idempotency lives here (registry check before install).
   - Depends on: Steps 1–3
   - Risk: Medium — `<expr>` mappings have several footguns: must use `vim.api.nvim_replace_termcodes` on returned strings; cmdline mode needs `mode = "c"` separately; must not feed keys that re-trigger the mapping.

5. **Create `init.lua`** (File: `lua/beast/libs/autopairs/init.lua`)
   - Action: Public API + state owner.
     - State: `local installed = false`, `local registry = {}` (list of `{mode, lhs}`).
     - `setup(opts)`: `config.setup(opts)`. Does **not** install mappings — first `enable()` does that. Reason: installation should be lazy via `InsertEnter`, not eager.
     - `enable()`: if already installed, return; else `keymap.install(config, registry)`, set `installed = true`. Honors `config.enabled` (no-op if false).
     - `disable()`: `keymap.uninstall(registry)`, `installed = false`.
     - `toggle()`: flips `vim.g.beast_autopairs_disable`. Does not unmap (cheap toggle — actions see the flag).
   - Why: Clear lifecycle. Lazy install matches every other lib in `beast/init.lua`.
   - Depends on: Steps 1–4
   - Risk: Low

6. **Create `tests/test-autopairs-engine.lua`** (File: `tests/test-autopairs-engine.lua`)
   - Action: Headless test file following `tests/test-tabline-edge-trim.lua` shape. No external framework — local `assert_test(name, cond, msg)` printing `PASS`/`FAIL` and incrementing counters; final `os.exit(failed > 0 and 1 or 0)`.
   - Coverage (table-driven where possible):
     - `pairs.neigh_matches`: 12 cases covering edge-of-line (`""`), backslash, alnum, brackets adjacent.
     - `pairs.is_symmetric`: quote/backtick = true; bracket = false.
     - `actions.open`: 8 cases — empty line, before alnum (currently pairs since skip_next isn't in P1), before close bracket, after backslash, at end of line.
     - `actions.close`: jump-over when matching, literal when not.
     - `actions.closeopen`: jump-over symmetric case; fall-through to open.
     - `actions.bs`: between pair (returns `<BS><Del>` decoded), not between pair (returns `<BS>`), with `vim.b.beast_autopairs_disable = true` (returns `<BS>` literal).
     - `actions.cr`: between `{}` (returns `<CR><C-o>O` decoded), not between pair (returns `<CR>`).
     - `keymap.install` + `keymap.uninstall`: install, assert `vim.fn.maparg("(", "i") ~= ""`, uninstall, assert empty. Roundtrip twice for idempotency.
     - `init.enable` / `init.disable`: same roundtrip via public API. Verify `vim.g.beast_autopairs_disable` toggle.
   - Run command: `nvim --clean --headless -l tests/test-autopairs-engine.lua` — expect exit 0.
   - Why: Pure modules are useless without tests; they're also trivially testable, so there's no excuse not to.
   - Depends on: Steps 1–5
   - Risk: Low

**Phase 1 acceptance**: `nvim --clean --headless -l tests/test-autopairs-engine.lua` exits 0. Manually `:lua require("beast.libs.autopairs").enable()` in a scratch buffer, typing `(` produces `(|)`, `<BS>` inside removes both, `<CR>` inside `{}` produces a 3-line block. `mini.pairs` is still in `plugins/init.lua` and still active — both can be loaded simultaneously without conflict (last-registered wins per key, which is fine since they're not both enabled at once during testing).

### Phase 2: Smart vetoes — skip_next, skip_ts, skip_unbalanced, markdown

This phase teaches the engine the four "shut up" rules. Still not wired into
`beast/init.lua`.

1. **Create `skip.lua`** (File: `lua/beast/libs/autopairs/skip.lua`)
   - Action: Pure module exporting `M.should_skip(cfg, ctx)` → `boolean, string?` where the optional string is an override-keystroke (used by `markdown` to return a multi-char expansion instead of just suppressing the pair).
     - Rule 1 — `skip_next` (cfg.skip_next is a Lua pattern, may be nil): if `ctx.after ~= "" and ctx.after:match(cfg.skip_next)` → return `true, nil`.
     - Rule 2 — `skip_ts` (cfg.skip_ts is a list of capture names, may be nil): wrap `vim.treesitter.get_captures_at_pos(0, row-1, math.max(col-1, 0))` in `pcall`; if any capture's `.capture` is in the list → return `true, nil`.
     - Rule 3 — `skip_unbalanced` (cfg.skip_unbalanced boolean): only when `ctx.after == ctx.close and ctx.close ~= ctx.open`; count opens/closes on `ctx.line` via `gsub(vim.pesc(c), "")`; if closers > openers → return `true, nil`.
     - Rule 4 — `markdown` (cfg.markdown boolean): only when `ctx.open == "`" and vim.bo.filetype == "markdown" and ctx.before_full:match("^%s*``")`; return `true, "\`\n\`\`\`" .. <Up>` (decoded).
     - `before_full` (whole line up to col) is part of `ctx` — populated by `actions.lua` for this rule.
   - Why: One file, one rule type per branch. Easy to extend.
   - Depends on: Phase 1 complete.
   - Risk: Medium — treesitter call must handle buffers without parsers (pcall); markdown expansion must use replace_termcodes for `<Up>`.

2. **Modify `actions.lua`** (File: `lua/beast/libs/autopairs/actions.lua`)
   - Action: Update `M.open(ctx)`:
     - Build `ctx.line`, `ctx.before_full`, `ctx.before`, `ctx.after`, `ctx.row`, `ctx.col` once at the top.
     - Call `local skipped, override = skip.should_skip(config, ctx)`.
     - If `override` ≠ nil → return `override`.
     - If `skipped` → return `ctx.open`.
     - Else: run the Phase 1 neighborhood-match path.
   - Why: Keeps `open` as the single integration point for vetoes (mirrors the LazyVim monkey-patch shape, but without monkey-patching).
   - Depends on: Phase 2 Step 1
   - Risk: Low

3. **Create `tests/test-autopairs-skip.lua`** (File: `tests/test-autopairs-skip.lua`)
   - Action: Table-driven unit tests for `skip.should_skip` (no Neovim UI needed for rules 1, 3, 4; rule 2 uses a real buffer with `vim.treesitter.start`).
   - Cases per rule:
     - `skip_next`: nil pattern → never skip. `[%w]` pattern + `after="f"` → skip. `[%w]` + `after=" "` → no skip. `after=""` (end of line) → no skip.
     - `skip_unbalanced`: balanced line → no skip. More closers → skip. Equal → no skip. Symmetric quote pair → never skip (early bail on `c ~= o`).
     - `markdown`: not markdown ft → no skip. Markdown ft but only one `` ` `` → no skip. Two `` ` `` + markdown ft + typing `` ` `` → returns override string (assert exact bytes after termcode decode).
     - `skip_ts`: open a buffer with `vim.treesitter.start(buf, "lua")`, place cursor in a string literal, assert skipped. Place cursor in code, assert not skipped. (Lua parser ships with Neovim core, no install needed.)
   - Why: Each veto is a tiny pure function; tests are the only way to keep them honest as the lib evolves.
   - Depends on: Phase 2 Steps 1–2
   - Risk: Low — `skip_ts` test needs a real buffer; the rest are string-only.

**Phase 2 acceptance**: both `nvim --clean --headless -l tests/test-autopairs-engine.lua` and `nvim --clean --headless -l tests/test-autopairs-skip.lua` exit 0. Manually `:lua require("beast.libs.autopairs").setup({ skip_next = [=[[%w]]=], skip_ts = {"string"}, skip_unbalanced = true, markdown = true }); require("beast.libs.autopairs").enable()` — typing `(` before a word does not pair; typing `(` inside a string does not pair; typing `` ``` `` in a `.md` buffer expands the fence.

### Phase 3: Wire-up, health check, retire mini.pairs

1. **Create `health.lua`** (File: `lua/beast/libs/autopairs/health.lua`)
   - Action: `:checkhealth beast.libs.autopairs` provider matching `confirm/health.lua` shape:
     - Section *beast.libs.autopairs*: Neovim version, config loaded, module loaded, enable state (`vim.g.beast_autopairs_disable`).
     - Section *API contract*: `setup`, `enable`, `disable`, `toggle` are functions.
     - Section *Mappings*: for each registered open char, verify `vim.fn.maparg(char, "i") ~= ""` when `installed == true`.
     - Section *Configuration*: dump effective `skip_next`, `skip_ts`, `skip_unbalanced`, `markdown`, `modes`, pair-count.
   - Why: User-facing diagnostic. Catches "I called setup but forgot to enable" and "treesitter parser missing for skip_ts" classes.
   - Depends on: Phase 2 complete
   - Risk: Low

2. **Modify `lua/beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action:
     - Extend `Beast.Config` type annotation with `---@field autopairs? Beast.Autopairs.Config`.
     - Add a `packer.lazy` block, placed next to `scroll`/`window` for grouping:
       ```lua
       packer.lazy("beast.libs.autopairs", {
         event = { name = "InsertEnter", defer = false },
         setup = function(autopairs)
           autopairs.setup(cfg.autopairs or {
             skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
             skip_ts = { "string" },
             skip_unbalanced = true,
             markdown = true,
           })
           autopairs.enable()
         end,
       })
       ```
     - Add `<leader>up` toggle keymap (mirrors LazyVim convention):
       ```lua
       Key.safe_set("n", "<leader>up", function()
         require("beast.libs.autopairs").toggle()
       end, { desc = "Toggle autopairs", group = "Autopairs" })
       ```
   - Why: Activates the lib. `defer = false` because `InsertEnter` is already lazy — we want mappings live as soon as the user enters insert mode.
   - Depends on: Phase 2 complete
   - Risk: Low

3. **Modify `lua/beast/plugins/init.lua`** (File: `lua/beast/plugins/init.lua`)
   - Action: Remove the entire `mini.pairs` plugin entry (the block starting `name = "mini.pairs"` added 2026-06-08). Verify the file still parses with `luac -p`.
   - Why: Cutover. Two autopair systems running at once would race on the same keys.
   - Depends on: Phase 3 Steps 1–2
   - Risk: Medium — if the cutover ships before Phase 1/2 land, the user loses autopairs entirely. **Mitigation**: this step is explicitly inside Phase 3, which depends on Phase 2 acceptance.

4. **Update codemap** (File: `docs/CODEMAP/libraries.md` + `docs/CODEMAP/INDEX.md`)
   - Action: Add an `## autopairs — Insert-Mode Autopairs` section to `libraries.md` listing the 6 files, API, loaded-via line. Increment the library count in `INDEX.md` from `18` → `19` and update the lib list. Per `codemap-freshness.instructions.md`, this must land in the same PR as the lib.
   - Why: Codemap drift is the single most common cause of stale specs. Update it as part of the cutover, not afterwards.
   - Depends on: Phase 3 Steps 1–3
   - Risk: Low

**Phase 3 acceptance**: `:checkhealth beast.libs.autopairs` shows all OKs. After `nvim`-restart, typing `(` in insert pairs correctly. `<leader>up` toggles globally. `mini.pairs` is gone from `plugins/init.lua`. Both unit-test files still exit 0.

# Testing Strategy

- **Unit tests** (`tests/`)
  - `tests/test-autopairs-engine.lua` (Phase 1) — pure functions, no UI: pair matcher, all 5 action functions, keymap install/uninstall roundtrip. Run: `nvim --clean --headless -l tests/test-autopairs-engine.lua`.
  - `tests/test-autopairs-skip.lua` (Phase 2) — table-driven veto rules + one real-buffer test for `skip_ts` using the bundled Lua parser. Run: same command.
  - Convention: local `assert_test(name, cond, msg)` helper, PASS/FAIL print lines, exit-code-1 on any failure. Matches `tests/test-tabline-edge-trim.lua`.
- **Bench**: none — autopairs runs at human keystroke rate. The two unit-test files are the perf guard (they assert correctness on every key permutation we care about; perf is implicitly bounded by the fact that nothing here is O(n) in anything bigger than the pair count or the current line).
- **`:checkhealth`** (Phase 3) — must show all OKs after `setup()` + `enable()`.
- **Manual verification** (run after Phase 3 cutover, in this order):
  1. Open scratch buffer, type `(` → cursor lands inside `(|)`.
  2. Press `<BS>` → both parens gone.
  3. Type `{` then `<CR>` → 3 lines with cursor indented on middle line.
  4. Type `(` immediately before existing `foo` → only `(` appears (skip_next).
  5. Open a Python file, place cursor inside `"hello |"`, type `(` → only `(` appears (skip_ts).
  6. On a line `foo))|`, type `(` → only `(` appears (skip_unbalanced).
  7. In a `.md` buffer, type ` ``` ` at start of empty line → expands to a fenced block, cursor in middle.
  8. Press `<leader>up` → typing `(` no longer pairs. Press again → pairs resume.
  9. `:set buftype=` is unaffected; cmdline `(` pairs (config default `modes.command = true`).
  10. `nvim --clean -u NORC` — verify lib does nothing without `setup()`.

# Risks & Mitigations

- **Risk**: `<expr>` mapping for `<CR>` collides with `blink.cmp`'s `<CR>` accept binding.
  **Mitigation**: BeastVim's blink uses `keymap = { preset = "enter", ... }` which installs its own `<CR>`. Whichever is registered last wins. The autopairs `<CR>` should be installed via `Key.safe_set`, which preserves an audit trail. If a collision shows up in manual verification step 3, the fix is to install autopairs' `<CR>` *before* `blink.cmp` loads, OR to make autopairs' `<CR>` defer to the existing mapping via `vim.fn.maparg` fall-through. Address concretely in Phase 1 step 4 if `maparg("<CR>", "i")` is non-empty at install time.

- **Risk**: `vim.treesitter.get_captures_at_pos` errors on buffers without an active parser.
  **Mitigation**: Wrapped in `pcall` per the LazyVim reference. Test case in `test-autopairs-skip.lua` covers a buffer with no parser (assert no-skip, no error).

- **Risk**: `vim.b.beast_autopairs_disable` check on every keystroke is wasteful.
  **Mitigation**: It isn't — a single buffer-variable lookup is sub-microsecond. Verified by inspection (no I/O, just a table access). No special caching needed.

- **Risk**: Mapping in cmdline mode (`modes.command = true`) interferes with `:` ex commands containing parens.
  **Mitigation**: Default cmdline `neigh_pattern` for `(` is the same as insert (`"[^\\]."`). Manual verification step 9 covers this; if real-world cmdline use suffers, set `modes.command = false` in `init.lua`'s default config.

- **Risk**: The `mini.pairs` removal in Phase 3 step 3 lands without Phases 1/2 being merged.
  **Mitigation**: Phase 3 depends explicitly on Phase 2 acceptance (unit tests passing). The cutover step is the *last* step of the *last* phase.

# Success Criteria

- [ ] `nvim --clean --headless -l tests/test-autopairs-engine.lua` exits 0.
- [ ] `nvim --clean --headless -l tests/test-autopairs-skip.lua` exits 0.
- [ ] `:checkhealth beast.libs.autopairs` shows OK on all sections.
- [ ] All 10 manual verification steps pass.
- [ ] `lua/beast/plugins/init.lua` no longer references `mini.pairs`.
- [ ] `docs/CODEMAP/libraries.md` includes an `autopairs` section; `INDEX.md` library count is incremented and the libraries list updated.
- [ ] No mention of `mini.pairs` or `nvim-autopairs` anywhere in `lua/beast/`.

# ADR Required

This dev spec involves architectural decision(s) that must be documented as
ADRs once committed:

- **New library `beast.libs.autopairs`** — adds a 19th in-house lib. Decision
  worth recording: we chose to build a from-scratch autopairs engine rather
  than wrap `mini.pairs`, on the rationale that *(a)* the smart veto layer is
  the only part anyone cares about and writing the engine underneath it is
  ~250 LOC of mostly-pure Lua, and *(b)* removing the external dependency
  matches the established BeastVim posture (see confirm, notify, finder,
  explorer — all rebuilt rather than wrapped).
- **Reversal of the 2026-06-08 `mini.pairs` decision.** That plugin was added
  earlier the same day with a LazyVim-style monkey-patch wrapper. The ADR
  should reference the prior addition and explain why we walked it back
  (rebuild was preferred once it became clear the smart layer was the
  interesting part).
