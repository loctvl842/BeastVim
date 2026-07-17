---
name: git-init
description: "Beast Git Library"
generated: 2026-05-31
---

# Summary

Native git library at `lua/beast/libs/git/` providing the absolute minimum
gitsigns.nvim-equivalent surface BeastVim needs:

1. **Per-line hunk signs** placed as extmarks the existing `statuscolumn`
   library already routes (the `git` producer becomes self-sufficient and
   `gitsigns.nvim` can be removed from the plugin list).
2. **Hunk navigation** — `]c` / `[c` motions + a `nav_hunk("next" | "prev")`
   public API.
3. **Hunk preview** — a `View`-subclassed float that shows the diff for the
   hunk under the cursor.

The diff engine is `vim.text.diff` (Neovim ≥ 0.11) which gitsigns itself
already delegates to. Base text comes from `git show HEAD:<path>` via
`vim.system` (async). One in-flight job per buffer, debounced ~200 ms on
edits.

Explicitly **out of scope** (deferred to follow-up specs):
blame line, staging/unstaging hunks, word diff, hunk text-objects (`ih`),
reset hunk, fugitive integration, rename-following, staged-vs-working split,
`.git/HEAD` watcher (we re-diff on `BufWritePost` + `FocusGained` instead).

# Requirements

- A `git` namespace registered as `beast_git_signs` so the statuscolumn
  library's classifier can route our extmarks via a single new pattern
  (`^beast_git_signs`); real `gitsigns.nvim` may still be installed without
  collision.
- Per-line hunk type: one of `add | change | delete | topdelete |
  changedelete`. Glyphs sourced from the existing `beast.icon`
  `gitsigns` table — no new icon entries.
- Highlight groups linked to existing `GitSignsAdd / Change / Delete /
  TopDelete / Changedelete` defined by the BeastVim colorscheme.
- Attach on `BufReadPost` + `BufNewFile` when the file is inside a git work
  tree (resolved once per buffer, cached). No-op for files outside a repo,
  directories, scratch buffers, and excluded buftypes.
- Re-diff trigger: `BufWritePost` (re-fetch base + recompute) and
  debounced `TextChanged` / `TextChangedI` (~200 ms — re-diff current text
  only, base unchanged). `FocusGained` re-fetches the base in case of an
  external `git commit`.
- Public API:
  - `git.setup(opts)`
  - `git.attach(buf?)`, `git.detach(buf?)`
  - `git.get_hunks(buf?)` → list of hunks for that buffer
  - `git.nav_hunk("next" | "prev", { wrap = true })`
  - `git.preview_hunk()` — opens a float at the cursor hunk
- Default keymaps registered (opt-in via `keymaps = true`, default `true`):
  `]c`, `[c` for nav; `<leader>gp` for preview.
- `:checkhealth beast.libs.git` — reports git executable presence,
  `vim.text.diff` availability, namespace registration, attached-buffer
  count, and per-buffer last-diff timing.
- A bench `scripts/bench-git.lua` measures `compute_hunks(base, current)`
  median time for buffers of 1 k / 5 k / 20 k lines. Hard threshold:
  median ≤ 10 ms for the 5 k case (matches gitsigns; bench fails CI on
  regression).
- Statuscolumn `signs.lua` adds one pattern to `NS_PATTERNS`: `^beast_git_signs`
  → class `git`. No other statuscolumn change.

# Research

### Repo Search

- Searched for: `gitsigns`, `git_signs`, `vim.system.*git`, `vim.text.diff`,
  `nvim_buf_set_extmark.*sign_text`, `BufWritePost.*debounce`
- Found:
  - `lua/beast/libs/explorer/git.lua:329, 426` — already uses
    `vim.system({"git", "-C", root, "status", "--porcelain=v2", ... })`
    with `text = true` callback, plus `vim.uv.new_timer()` for periodic
    refresh. Sets the precedent for our `vim.system` shape.
  - `lua/beast/libs/explorer/git.lua:475` — uses
    `(vim.uv or vim.loop).new_timer()` for compatibility; we'll match.
  - `lua/beast/icon.lua:28-34` — `gitsigns = { add, change, delete,
    topdelete, changedelete }` icons already defined; the library reads
    them directly, no new icon entries needed.
  - `lua/beast/libs/statuscolumn/signs.lua:32-39` — `NS_PATTERNS` /
    `NAME_PATTERNS` already classify `^gitsigns` / `^GitSigns`. One new
    entry `^beast_git_signs` → `git` lets us coexist with real gitsigns.
  - `lua/beast/libs/statuscolumn/highlights.lua:16-18` — `BeastStcGitAdd
    / Change / Delete` link to `GitSignsAdd / Change / Delete`. No
    statuscolumn change needed on the highlight side.
  - `lua/beast/util/debounce.lua` — **does not exist**. `explorer/git.lua`
    rolls its own via `uv.new_timer`. We'll inline ours rather than
    extract (single use site; AGENTS rule of three).
  - `lua/beast/libs/view.lua` — the shared `View` base class for buf+win
    pairs. The preview float subclasses it (matches ADR-001, the
    breadcrumb-popover, the explorer-preview, the notify float).
  - `lua/beast/libs/packer/init.lua` — `packer.lazy(mod, {event, defer,
    setup, ...})` is the standard registration shape (matches every
    other lib).
- Reuse opportunity:
  - **Adopt** `vim.system` + `vim.uv.new_timer` shape from
    `explorer/git.lua`.
  - **Adopt** `View` base class for the preview float.
  - **Extend** statuscolumn's `signs.lua` `NS_PATTERNS` (1 line).
  - **No extraction needed** — debounce is single-use; if a third lib
    needs it we extract per ADR-004.

### Package Search

- Searched: `vim.text.diff` (Neovim ≥ 0.11), `vim.diff` (≥ 0.10
  fallback), `nvim_buf_set_extmark` sign behaviour, `vim.system`
  semantics, gitsigns.nvim diff engine.
- Found:
  - **`vim.text.diff(a, b, opts)`** returns hunk indices when
    `opts.result_type = "indices"`. Format: `{{a_start, a_count,
    b_start, b_count}, ...}`. Falls back to `vim.diff` on ≤ 0.10. This
    is exactly what gitsigns uses (`diff_int.lua:51-66` per the research
    pass). No external dependency.
  - **`nvim_buf_set_extmark`** with `sign_text` + `sign_hl_group` is the
    canonical sign API since 0.10; legacy `sign_place` is unnecessary.
    Statuscolumn already classifies sign-extmarks by namespace.
  - **`vim.uv.fs_event_start`** — could watch `.git/HEAD` for external
    commits, but the cost of attaching one event per repo isn't worth
    the complexity for a v1. Re-fetch on `FocusGained` instead.
- Decision: **Use native** — `vim.text.diff` + `vim.system` + extmarks.
  No external plugin. No FFI. No new shared helper extracted.

# Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/git/init.lua` | Create | Public API, state table, attach / detach, event wiring |
| `lua/beast/libs/git/config.lua` | Create | Frozen-metatable defaults (debounce_ms, keymaps, icons override) |
| `lua/beast/libs/git/repo.lua` | Create | `vim.system` wrappers: `resolve(buf)` (rev-parse), `get_base(buf)` (show) |
| `lua/beast/libs/git/diff.lua` | Create | `compute_hunks(base, current)` — `vim.text.diff` wrapper |
| `lua/beast/libs/git/hunks.lua` | Create | Hunk → per-line sign expansion (port of gitsigns' `calc_signs`) |
| `lua/beast/libs/git/signs.lua` | Create | Extmark placement in our namespace; clear/replace |
| `lua/beast/libs/git/nav.lua` | Create | Phase 2: `nav_hunk("next"\|"prev")` |
| `lua/beast/libs/git/preview.lua` | Create | Phase 3: `View`-subclassed float showing one hunk's diff |
| `lua/beast/libs/git/highlights.lua` | Create | `BeastGitAdd/Change/Delete/TopDelete/Changedelete` (link to existing groups) |
| `lua/beast/libs/git/health.lua` | Create | `:checkhealth` — git binary, `vim.text.diff`, namespace, attached bufs |
| `scripts/bench-git.lua` | Create | Bench `compute_hunks` for 1k/5k/20k synthetic buffers |
| `lua/beast/libs/statuscolumn/signs.lua` | Modify | Add `{ class = "git", pattern = "^beast_git_signs" }` to `NS_PATTERNS` |
| `lua/beast/init.lua` | Modify | Append `beast.libs.git.highlights` to `highlight_modules`; register lib via `packer.lazy(..., {event="BufReadPost", defer=true, ...})` |

# Implementation Phases

### Phase 1: Core engine + sign producer — `~/.config/BeastVim/lua/beast/libs/git/{init,config,repo,diff,hunks,signs,highlights,health}.lua` + statuscolumn pattern + bench

**Goal**: Replace `gitsigns.nvim` for the per-line sign use case. The
statuscolumn library's existing `git` producer continues to work unchanged
because we publish extmarks in a namespace it already (almost) routes — one
pattern is added.

1. **Create `config.lua`** (File: `lua/beast/libs/git/config.lua`)
   - Action: Frozen-metatable defaults matching `statuscolumn/config.lua`
     shape: `{ debounce_ms = 200, keymaps = true, icons = nil --[[ use
     beast.icon.gitsigns ]], ft_ignore = { ... }, bt_ignore = { "nofile",
     "prompt", "quickfix", "terminal", "help" } }`.
   - Why: Match every other lib's config pattern (ADR-003).
   - Depends on: None
   - Risk: Low

2. **Create `repo.lua`** (File: `lua/beast/libs/git/repo.lua`)
   - Action: Two async functions.
     - `resolve(buf, cb)` — runs `git -C <dir> rev-parse --show-toplevel
       --absolute-git-dir` via `vim.system`; callback gets
       `{ toplevel, gitdir, relpath }` or `nil` if not in a repo.
       Cache result by `buf` in a module-local table; bust on `BufFilePost`.
     - `get_base(buf, cb)` — runs `git -C <toplevel> show HEAD:<relpath>`;
       callback gets the base text as a string (split into lines on
       demand by `diff.lua`).
   - Why: Both calls match the `explorer/git.lua:329, 426` pattern.
   - Depends on: Step 1
   - Risk: Low (shells out; defensive `pcall` + exit-code checks)

3. **Create `diff.lua`** (File: `lua/beast/libs/git/diff.lua`)
   - Action: `compute_hunks(base_lines, current_lines, opts?)` →
     `{ {a_start, a_count, b_start, b_count, type}, ... }`. Calls
     `vim.text.diff(base_str, current_str, { result_type = "indices",
     algorithm = "histogram", linematch = 60 })`. `opts` falls back to
     `vim.diff` on ≤ 0.10 (one feature-detect at module load).
     `type` is computed from `(a_count, b_count)`:
     `a_count == 0` → `"add"`; `b_count == 0` → `"delete"`; else
     `"change"`.
   - Why: Pure function; the hot path's bench target.
   - Depends on: Step 1
   - Risk: Low

4. **Create `hunks.lua`** (File: `lua/beast/libs/git/hunks.lua`)
   - Action: `expand_signs(hunks, n_buffer_lines)` →
     `{ [lnum] = { type = "add"|"change"|"delete"|"topdelete"|"changedelete" } }`.
     Port the ~50 LOC of gitsigns' `hunks.calc_signs` (logic for
     `topdelete` when `b_start == 0`, `changedelete` for short `change`
     hunks).
   - Why: This is the only "interesting" transform; everything else is
     plumbing.
   - Depends on: Step 3
   - Risk: Medium — edge cases (file end, line 1, full-file change).
     Mitigated by adding 5 unit tests covering each marker type.

5. **Create `signs.lua`** (File: `lua/beast/libs/git/signs.lua`)
   - Action:
     - `local NS = vim.api.nvim_create_namespace("beast_git_signs")`.
     - `place(buf, line_signs)` — clear the namespace in `buf`, then
       `nvim_buf_set_extmark` for each entry with `{ sign_text = icon,
       sign_hl_group = hl, priority = 6 }`.
     - `clear(buf)` — `nvim_buf_clear_namespace(buf, NS, 0, -1)`.
   - Why: One extmark per signed line; statuscolumn picks them up via
     namespace pattern (Step 6).
   - Depends on: Step 4
   - Risk: Low

6. **Modify statuscolumn classifier** (File:
   `lua/beast/libs/statuscolumn/signs.lua`)
   - Action: Insert
     `{ class = "git", pattern = "^beast_git_signs" }` ahead of the
     existing `^gitsigns` entry in `NS_PATTERNS`.
   - Why: Routes our extmarks to the `git` producer without changing the
     statuscolumn API surface.
   - Depends on: Step 5
   - Risk: Low

7. **Create `init.lua`** (File: `lua/beast/libs/git/init.lua`)
   - Action: Module-local `state = { attached = {} }`; `attach(buf)`
     pipeline (`resolve` → `get_base` → diff → expand → place);
     `detach(buf)` clears extmarks + state; `setup(opts)` calls
     `config.setup`, attaches autocmds (`BufReadPost`, `BufNewFile`,
     `BufWritePost`, `FocusGained`, `BufDelete`, `BufWipeout`) in a
     dedicated `BeastGit` augroup, and registers the debouncer for
     `TextChanged` / `TextChangedI`. Single in-flight job per buffer via
     a `pending` flag; latest request wins (overwrite instead of queue).
   - Why: The orchestration layer. All other modules are leaves.
   - Depends on: Steps 1-5
   - Risk: Medium — async ordering. Mitigated by the single-flight flag
     and per-buffer state table.

8. **Create `highlights.lua`** (File: `lua/beast/libs/git/highlights.lua`)
   - Action: `Util.colors.set_hl("BeastGit", { Add = { link = "GitSignsAdd" },
     Change = ..., Delete = ..., TopDelete = ..., Changedelete = ... })`.
     Matches ADR-008 namespacing.
   - Why: Decouples from gitsigns being installed for highlight resolution
     — colorscheme defines `GitSignsAdd` etc. regardless.
   - Depends on: None
   - Risk: Low

9. **Create `health.lua`** (File: `lua/beast/libs/git/health.lua`)
   - Action: `vim.health` checks — `vim.fn.executable("git")`,
     `vim.text.diff` or `vim.diff` presence, namespace registered,
     count of attached buffers + last-diff duration.
   - Why: Mirrors every other BeastVim lib.
   - Depends on: Step 7
   - Risk: Low

10. **Create `scripts/bench-git.lua`** (File: `scripts/bench-git.lua`)
    - Action: Build synthetic buffers (1 k / 5 k / 20 k lines) with 50
      hunks each; call `diff.compute_hunks` in a tight loop; report
      median time per call. Hard fail at 10 ms for the 5 k case.
    - Why: Catches regressions in our diff plumbing (the algorithm is
      Neovim's; we measure overhead of the wrapper).
    - Depends on: Step 3
    - Risk: Low

11. **Wire into `lua/beast/init.lua`** (File: `lua/beast/init.lua`)
    - Action: Append `"beast.libs.git.highlights"` to `M.highlight_modules`;
      register the lib with `packer.lazy("beast.libs.git", { event =
      "BufReadPost", defer = true, setup = function(g) g.setup({}) end })`
      after the statuscolumn block.
    - Why: Lazy-load matches every other lib's wiring.
    - Depends on: Steps 7, 8
    - Risk: Low

12. **Remove `gitsigns.nvim` from plugin list (optional, user-driven)**
    - Action: Not performed in this phase. The lib coexists with
      gitsigns; the user can `vim.b.gitsigns_disabled = true` per buffer
      or remove the plugin once Phase 1 lands cleanly.
    - Why: Reversibility. Keep the safety net while the new lib is fresh.
    - Depends on: Phase 1 complete
    - Risk: None (no-op)

**Phase 1 checkpoint**: signs render in the statuscolumn for any git
buffer; toggling `gitsigns.nvim` off should produce identical visuals;
bench under 10 ms / 5 k lines.

### Phase 2: Hunk navigation — `~/.config/BeastVim/lua/beast/libs/git/nav.lua` + init/keymap wiring

**Goal**: `]c` / `[c` jump to the next / previous hunk. A direct port of
the gitsigns motion shape, scoped to our own hunk list.

1. **Create `nav.lua`** (File: `lua/beast/libs/git/nav.lua`)
   - Action: `nav_hunk(direction, opts)` with
     `opts = { wrap = true, foldopen = true }`. Reads current cursor row;
     scans the buffer's hunk list (already cached in `init.lua`'s state);
     jumps to the first hunk strictly after / before the cursor, with
     wrap; calls `vim.cmd("normal! zv")` to open any fold; sets a single
     mark for `''`.
   - Why: Pure cursor motion; no external state needed.
   - Depends on: Phase 1 complete
   - Risk: Low

2. **Expose API + keymaps** (File: `lua/beast/libs/git/init.lua`)
   - Action: `M.nav_hunk = nav.nav_hunk`. When `config.keymaps == true`,
     register `]c` / `[c` as buffer-local keymaps on attach (so
     non-git buffers don't see them).
   - Why: Match LazyVim-style defaults; per-buffer registration matches
     the breadcrumb / scroll libs.
   - Depends on: Step 1
   - Risk: Low

**Phase 2 checkpoint**: Cursor on line 1 of a buffer with hunks at lines
20, 50, 100; `]c` lands on 20, `]c` again lands on 50, `[c` from line 60
lands on 50.

### Phase 3: Hunk preview — `~/.config/BeastVim/lua/beast/libs/git/preview.lua` + keymap

**Goal**: `<leader>gp` opens a `View`-subclassed float showing the diff for
the hunk under the cursor. Closing is automatic on cursor move or `q`.

1. **Create `preview.lua`** (File: `lua/beast/libs/git/preview.lua`)
   - Action: Subclass `lua/beast/libs/view.lua` (per AGENTS *§ The View
     Pattern*).
     - `open(hunk, base_lines, current_lines)` — render diff text into a
       scratch buf, apply hl groups (`DiffAdd` / `DiffDelete` /
       `DiffChange`) per-line, open a child float anchored at the hunk
       start line, sized to the longest line + 2 padding, capped to
       `floor(vim.o.lines * 0.4)` height.
     - Lifecycle: close on `CursorMoved`, `BufLeave`, `q`, `<Esc>`.
   - Why: Reuse the View base class — preview is a buf+win pair with
     known cleanup needs (ADR-001, ADR-014).
   - Depends on: Phase 1 complete
   - Risk: Medium — float positioning when the hunk is at screen edges.
     Mitigated by reusing existing breadcrumb-popover anchoring logic.

2. **Expose API + keymap** (File: `lua/beast/libs/git/init.lua`)
   - Action: `M.preview_hunk = preview.open_for_current_line`. Register
     `<leader>gp` per attached buffer when `config.keymaps == true`.
   - Why: Same shape as Phase 2.
   - Depends on: Step 1
   - Risk: Low

3. **Update health** (File: `lua/beast/libs/git/health.lua`)
   - Action: Add `preview` section reporting that `View` is loadable and
     the keymap is set.
   - Why: One place to verify everything wired up.
   - Depends on: Step 2
   - Risk: Low

**Phase 3 checkpoint**: Cursor on a changed line; `<leader>gp` opens a
float showing the old vs new lines with the right `DiffAdd / DiffDelete`
colours; moving the cursor closes the float.

# Testing Strategy

- **Unit tests**: `tests/` is currently empty; this spec does not seed it
  (`statuscolumn` and `scroll` shipped without test files too). The
  per-marker logic in `hunks.lua` is small enough to verify by manual
  repro for v1 — when `tests/` gets its first runner, the
  `topdelete`/`changedelete` edge cases here are the natural candidates.
- **Bench**: `scripts/bench-git.lua` (Phase 1, Step 10) gates regressions.
- **Manual verification** — Phase 1:
  1. Open a file in a git repo, modify two lines, save → both lines
     show the `change` glyph in the statuscolumn.
  2. Delete a line → adjacent line shows `topdelete`.
  3. Modify and delete simultaneously → `changedelete`.
  4. Open a non-git file (e.g. `/tmp/foo`) → no signs, no errors.
  5. Disable gitsigns (`:lua vim.cmd('lua require("gitsigns").detach()')`)
     → our signs remain (proves no dependency).
- **Manual verification** — Phase 2:
  - Buffer with hunks at lines 20, 50, 100. `]c` from 1 → 20. `]c` from
    20 → 50. `[c` from 60 → 50. `]c` from 100 with `wrap = true` → 20.
- **Manual verification** — Phase 3:
  - Cursor on a `change` line; `<leader>gp` opens float with old / new
    lines colourised. `CursorMoved` closes. `q` closes. Resize the
    terminal — float stays anchored.

# Risks & Mitigations

- **Risk**: `vim.text.diff` is Neovim ≥ 0.11; older Neovim ships
  `vim.diff` with a slightly different signature.
  **Mitigation**: feature-detect once at module load in `diff.lua`;
  unify both behind a local function. `health.lua` reports the chosen
  back-end.

- **Risk**: `git show HEAD:<path>` fails for newly-tracked files
  (`fatal: path '...' exists on disk, but not in 'HEAD'`).
  **Mitigation**: treat non-zero exit as "base is empty string" — every
  line then renders as `add`. Matches gitsigns behaviour.

- **Risk**: `vim.system` overlapping jobs per buffer if an edit storm
  arrives faster than the debounce.
  **Mitigation**: single-flight flag in per-buffer state; new requests
  set a "dirty" bit, the in-flight job re-runs once on completion if
  dirty.

- **Risk**: Coexistence with `gitsigns.nvim` produces double signs in the
  statuscolumn.
  **Mitigation**: distinct namespace (`beast_git_signs`) + a `git.attach`
  call that sets `vim.b.gitsigns_disabled = true` per-buffer when our
  config opts in via `disable_gitsigns_on_attach = true` (default
  `false` for safety; user flips it once confident).

- **Risk**: External `git commit` invalidates the base but we don't
  watch `.git/HEAD`.
  **Mitigation**: `FocusGained` re-fetches the base for every attached
  buffer. Documented as the v1 trade-off (watcher is out of scope).

# Success Criteria

- [x] `scripts/bench-git.lua` reports `compute_hunks` median **< 10 ms**
      for the 5 k-line buffer.
- [x] `:checkhealth beast.libs.git` clean (git binary, diff back-end,
      namespace, attached count).
- [x] Statuscolumn shows correct signs on a modified file with
      `gitsigns.nvim` disabled.
- [x] `]c` / `[c` navigate next / previous hunk, wrap at file end.
- [x] `<leader>gp` opens a floating preview that closes on `CursorMoved`.
- [x] `nvim_buf_get_extmarks` in the `beast_git_signs` namespace returns
      exactly one entry per signed line (no duplication).
- [x] Codemap regenerated; `docs/CODEMAP/libraries.md` includes the
      new `git` lib; INDEX.md lib count bumped 15 → 16.

# Completed

- **Date:** 2026-06-01
- **Commits:**
  - `e639279` — Phase 1: core engine + native hunk sign producer
  - `9124a05` — Phase 2: hunk navigation (`]c` / `[c`)
  - `f4fafa5` — Phase 3: hunk preview float (`<leader>gp`)
- **Bench (final):** 1k=0.29 ms, 5k=2.59 ms, 20k=18.82 ms — threshold 10 ms @ 5k PASS.
- **ADRs:** [022](../ADRs/022-native-git-library-replaces-gitsigns.md), [023](../ADRs/023-vim-text-diff-backend.md), [024](../ADRs/024-beast-git-signs-namespace.md).

# ADR Required

This dev spec involves architectural decision(s) that must be documented
as ADRs once committed:

- **Native git lib over `gitsigns.nvim` dependency** — port-the-design
  precedent (ADR-009 statusline, ADR-015 tabline, ADR-018 scroll).
  Records that we accept dropping blame, staging, word-diff, and
  rename-following in exchange for a ~500 LOC focused replacement.
- **`vim.text.diff` (with `vim.diff` fallback) as the diff engine** —
  records the decision to use Neovim's built-in diff (which gitsigns
  itself uses) instead of shelling out to `git diff`, why we don't use
  libgit2 / FFI, and how we feature-detect the API.
- **Distinct namespace `beast_git_signs` for coexistence** — records
  why we don't reuse the `gitsigns` namespace name (collision-by-design
  is bad) and how the statuscolumn classifier accommodates both.
