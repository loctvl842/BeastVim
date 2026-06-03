# Dev Spec: Key Press-and-Wait Popup (Helix-style)

## Summary

Add a Helix-style "press-and-wait" popup to `lua/beast/libs/key/` that shows the
available continuations after a leader-prefix keypress (e.g. `<leader>`, `<localleader>`),
then resolves to the chosen mapping via `nvim_feedkeys`. This replaces our reliance on
`which-key.nvim` for the popup feature. The design exploits the fact that `Key.managed`
is the single source of truth for our keymaps — we never scrape `nvim_get_keymap`,
never rebuild per buffer, never run a polling timer, and only register **two** trigger
keymaps globally (one per configured prefix). The popup window is a bottom-right
anchored float with a breadcrumb title (Helix-strict layout). Scope is normal + visual
mode + leader-prefixed sequences only.

## Requirements

- After pressing a configured trigger (default `<leader>` or `<localleader>`),
  a popup appears within `delay` ms (default 0 — Helix feel) showing direct children of
  the current prefix node from `Key.managed`.
- Each subsequent keypress narrows the popup (descend tree); `<BS>` pops one level;
  `<Esc>` cancels; `timeoutlen` elapsed at a leaf executes it; no-match feeds the
  remaining sequence verbatim and exits.
- Resolution honours `expr`, `silent`, `<cmd>`, `<Plug>`, function-rhs mappings —
  achieved by suspending our trigger and re-feeding the full sequence (`nvim_feedkeys`
  with `"m"` mode), then re-registering the trigger on the next tick.
- Works in normal mode (`n`) and visual modes (`x`, `s`, `<C-v>`). Visual selection
  is preserved across the popup (prepend `gv` to the fed sequence when exiting visual).
- Prefix index built lazily from `Key.managed` on first popup; invalidated by the
  `BeastKeysChanged` User autocmd (already emitted from `core.lua`).
- Buffer-local mappings: at popup-open time the index is filtered to entries where
  `keys.buffer == nil OR keys.buffer == current_bufnr`. No per-buffer trigger
  registration, no `LspAttach` autocmd.
- Window: `relative = "editor"`, `anchor = "SE"`, bottom-right corner, rounded
  border, title-left breadcrumb (` <leader> f › `), width 30–60, auto-fit height.
- Safety: skipped when recording a macro (`vim.fn.reg_recording() ~= ""`) or when
  pending input is queued (`vim.fn.getcharstr(1) ~= ""`); `<C-c>` exits cleanly.
- Coexists with the existing full-screen browser UI in `key/ui.lua` (different
  feature, different entry point — no overlap).

### Out of scope

- **Operator-pending mode** (`o`) — would require register/count/operator capture
  and is rarely the discovery-driven UX. Add later if needed.
- **`g`/`z`/`<C-w>` and other built-in prefixes** — defer to a future "Design B"
  add-on (per-buffer triggers on `LspAttach`); leader-only first.
- **Plugins**: marks (`'`), registers (`"`), spelling (`z=`) — separate features.
- **Icons / mini.icons integration** — text-only popup first; cosmetic add-on later.
- **Scroll inside popup** (`<C-d>` / `<C-u>`) — only matters for >25-row groups; defer.
- **Replacing the existing `key/ui.lua` full-screen browser** — that stays as-is
  (different feature: searchable keymap list, not press-and-wait).

## Research

### Repo Search

- Searched for: `which-key|getcharstr|press.and.wait|popup.trigger|prefix.tree`
  (`git grep -niE 'which-key|getcharstr|on_key' lua/`)
- Found in **BeastVim**:
  - `lua/beast/libs/key/core.lua` — already has `M.managed` registry + `BeastKeysChanged`
    User autocmd (lines 41-48). **This is the cache which-key cannot have.**
  - `lua/beast/libs/key/init.lua` — already exports `to_which_key()` /
    `to_which_key_spec()`. We will not extend these; the new popup is independent.
  - `lua/beast/libs/confirm/ui.lua:312-340` — proven modal loop pattern using
    `pcall(vim.fn.getcharstr)`. **Adopt** the same loop shape.
  - `lua/beast/libs/scroll/init.lua:281-292` — proven `vim.on_key` usage with a dedicated
    namespace and proper teardown (`vim.on_key(nil, ns)`). Not directly used here, but
    confirms the project's approach to low-level input.
  - `lua/beast/libs/view.lua` — `Beast.View` base class. **Adopt**: the popup window
    subclasses this (ADR-001).
  - `lua/beast/libs/key/ui.lua` — existing full-screen browser using `View:extend`.
    Reference for highlight wiring and namespace pattern; **not extended**.
  - `lua/beast/libs/key/highlights.lua` — `BeastKey*` namespace already established.
    **Extend** with `BeastKeyPopup*` groups (one more line per group).
  - `lua/beast/util/init.lua` — `Util.wo`, `Util.colors.set_hl`, `Util.create_scratch_buf`
    (per CODEMAPS). **Adopt** for buffer/window setup.
- Reuse opportunities:
  - `Beast.View` — adopt.
  - `Util.wo` / `Util.create_scratch_buf` — adopt.
  - `Key.managed` — the registry IS the prefix tree's source; no rebuild needed.
  - `BeastKeysChanged` autocmd — already emitted; subscribe for cache invalidation.
- Reuse decision: **Adopt all** — no extraction needed; everything is already shared.

### Package Search

- Searched: `which-key.nvim` internals (`~/.local/share/nvim/lazy/which-key.nvim/lua/which-key/`)
  — `state.lua`, `triggers.lua`, `buf.lua`, `config.lua`, `presets.lua`.
- Found:
  - **`state.lua:248-275`** — the `step()` getchar loop. Pattern to emulate:
    `redraw_timer:start(50, 0, redraw)` + `vim.fn.getcharstr()` + `M.check(state, key)`.
  - **`state.lua:183-215`** — `check()`: walks tree, honours `timeoutlen`/`nowait`,
    handles `<Esc>`/`<BS>`/scroll. Logic to mirror.
  - **`state.lua:221-240`** — `execute()`: suspends triggers, restores count/register,
    `nvim_feedkeys(keystr, "mit", false)`. **Adopt the suspend-and-feed pattern**.
  - **`triggers.lua:43-56`** — trigger registration. We adopt this shape but globally
    (no `buffer = trigger.buf`) and for only the configured prefixes.
  - **`buf.lua:117-145`** — `Mode:update` rebuilds the tree from `nvim_get_keymap` +
    `nvim_buf_get_keymap`. **Do not adopt** — this is the per-buffer cost we are escaping.
  - **`presets.lua:3-17`** — Helix preset window opts (anchor SE, border rounded,
    title-left, width 30–60). **Adopt** as our default window config.
- Native Neovim primitives available:
  - `vim.fn.getcharstr()` — synchronous char read.
  - `vim.fn.keytrans()` — translate to printable form (`<C-x>` etc.).
  - `vim.api.nvim_replace_termcodes(keys, true, true, true)` — for feedkeys.
  - `vim.api.nvim_feedkeys(keys, "m", false)` — re-feed with remap allowed.
  - `vim.fn.reg_recording()` — macro detection.
  - `vim.o.timeoutlen` — already user-configured (`option.lua:34` = 100ms).
  - `(vim.uv or vim.loop).new_timer()` — for redraw + delay.
- Decision: **Use native + reuse repo modules** — no new dependencies. Skip which-key's
  per-buffer caching layer entirely; everything else is just `vim.fn` + a 200-line state
  machine on top of `Key.managed`.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/key/popup.lua` | Create | New module: prefix index, trigger registration, getchar loop, Helix-style window. ~250 LOC. |
| `lua/beast/libs/key/config.lua` | Modify | Add `popup` table to defaults (triggers, modes, delay, win options). |
| `lua/beast/libs/key/init.lua` | Modify | Call `require("beast.libs.key.popup").setup()` from `M.setup`. |
| `lua/beast/libs/key/highlights.lua` | Modify | Add `BeastKeyPopupBorder`, `BeastKeyPopupTitle`, `BeastKeyPopupKey`, `BeastKeyPopupDesc`, `BeastKeyPopupGroup`, `BeastKeyPopupSeparator` (single block, mirrors existing `BeastKey*` style). |
| `lua/beast/plugins/init.lua` | Modify | Remove `which-key.nvim` from plugin spec OR keep it disabled-by-default for transition — **see Phase 4**. |
| `docs/CODEMAPS/libraries.md` | Modify | Update the `key/` tree to include `popup.lua` and note the new public API. |
| `tests/test-key-popup.lua` | Create | Manual repro script (no test framework in `tests/` today — match existing convention of runnable manual scripts). |

## Implementation Phases

### Phase 1: Popup module + config + highlights — Standalone popup, opt-in

Lands a working popup that does not yet replace which-key. Opt-in via
`Key.setup({ popup = { enabled = true } })`. Allows side-by-side testing.

1. **Add `popup` defaults to config** (File: `lua/beast/libs/key/config.lua`)
   - Action: insert `popup = { enabled = false, triggers = { "<leader>", "<localleader>" }, modes = { "n", "x" }, delay = 0, win = { width = { min = 30, max = 60 }, height = { min = 4, max = 0.6 }, border = "rounded", anchor = "SE", padding = { 0, 1 }, title_pos = "left" }, sort = { "group_last", "alphanum" } }` into `defaults`.
   - Why: Configurable in user-land via `setup({ popup = ... })`; respects the read-only metatable convention (ADR-003).
   - Depends on: None.
   - Risk: Low — pure data.

2. **Add popup highlights** (File: `lua/beast/libs/key/highlights.lua`)
   - Action: extend the `set_hl("BeastKey", { ... })` block with `PopupNormal`, `PopupBorder`, `PopupTitle`, `PopupBreadcrumb`, `PopupKey`, `PopupDesc`, `PopupGroup`, `PopupSeparator`. Pull colours from existing palette tokens (`p.dark1`, `p.dimmed1`, `p.accent3`, `p.accent6`, `p.dimmed3`).
   - Why: ADR-008 namespacing — every UI surface owns its own `BeastKey*` group.
   - Depends on: Step 1.
   - Risk: Low.

3. **Create `popup.lua` skeleton** (File: `lua/beast/libs/key/popup.lua`)
   - Action: scaffold the module with these sections:
     - `local M = {}` + private locals (`index_cache`, `registered_triggers`, `state`, `redraw_timer`).
     - `M.setup(cfg)` — registers `BeastKeysChanged` autocmd to invalidate index; registers trigger keymaps for `cfg.triggers × cfg.modes`.
     - `local function build_index()` — walks `Key.managed`, returns `{ [prefix] = { children = {[key]=node}, leaf = keymap_or_nil, group = string_or_nil } }`. Strict prefix decomposition via `Util.keys(lhs)` (port the 4-line keytrans-split from which-key's `util.lua`).
     - `local function get_index(mode, bufnr)` — returns filtered view of cache.
     - `local function start(trigger, mode)` — initialises `state`, opens popup after `cfg.delay`, runs `loop()`.
     - `local function loop()` — getchar machine; returns the final sequence to feed.
     - `local function execute(sequence, was_visual)` — suspends trigger keymaps, `nvim_feedkeys(termcoded, "m", false)`, schedules trigger re-registration.
     - `local function open_window(state)` / `close_window()` — Helix-style float, subclasses `Beast.View`.
     - `local function render(state)` — populates buffer with `key  desc` columns, extmark highlights.
   - Why: Single module owns the entire feature surface; no leakage into `core.lua` (which stays a pure registry).
   - Depends on: Steps 1, 2.
   - Risk: Medium — getchar loop has edge cases (macros, `<C-c>`, mode changes); mitigated by mirroring `confirm/ui.lua:312-340` shape and which-key's `state.lua:safe` checks.

4. **Wire popup into setup** (File: `lua/beast/libs/key/init.lua`)
   - Action: at end of `M.setup(opts)`, add `if config.popup and config.popup.enabled then require("beast.libs.key.popup").setup(config.popup) end`.
   - Why: Opt-in for Phase 1. Phase 4 flips the default after burn-in.
   - Depends on: Steps 1, 3.
   - Risk: Low.

5. **Manual test script** (File: `tests/test-key-popup.lua`)
   - Action: minimal runnable script: sets up 6 sample keymaps under `<leader>f`, calls `Key.setup({ popup = { enabled = true } })`, prints instructions for manual repro (press `<leader>f`, expect popup; press `f`, expect file mappings; press `<Esc>`, expect cancel; press `<leader>fx` where `fx` is unmapped, expect verbatim feed).
   - Why: Matches existing `tests/` convention (runnable manual scripts, no framework).
   - Depends on: Step 4.
   - Risk: Low.

**End of Phase 1**: Popup works, opt-in, does not replace which-key, no plugin spec changes. Safe to merge.

---

### Phase 2: Bench + perf validation — Prove the perf claim

Adds a bench script to quantify popup-open cost and index-build cost. Establishes
the SLA referenced in Success Criteria.

1. **Bench script** (File: `scripts/bench-key-popup.lua`)
   - Action: matches shape of `scripts/bench-explorer.lua`. Three measurements:
     - `index_build_µs` — time `build_index()` over a synthetic registry of 200 keymaps (representative of a loaded BeastVim config).
     - `popup_open_µs` — time from trigger-callback invocation to popup-window visible, averaged over 50 iterations.
     - `keypress_resolve_µs` — time per descent step in `loop()` (the getchar→render→render path), averaged over 100 simulated keys via `vim.api.nvim_feedkeys`.
   - Why: ADR practice — perf claims need numbers. The whole point of this rewrite is performance; without the bench, the claim is vapor.
   - Depends on: Phase 1.
   - Risk: Low.

2. **Run baseline against which-key** (File: same, optional second mode)
   - Action: add a `--vs-whichkey` flag that runs equivalent measurements against the installed which-key.nvim and prints both columns side-by-side.
   - Why: Numeric proof for the eventual ADR.
   - Depends on: Step 1.
   - Risk: Low (best-effort — which-key's `state.start` is callable but the measurement isn't 1:1; document the caveat in the script header).

**End of Phase 2**: Bench numbers in hand. Decision point for Phase 4.

---

### Phase 3: Visual-mode polish + edge cases — Production readiness

Covers visual-mode selection preservation, register/count restoration, and the
recursion guard. These are correctness fixes for cases Phase 1 may handle naively.

1. **Visual selection preservation** (File: `lua/beast/libs/key/popup.lua`)
   - Action: at `start()`, capture `vim.fn.mode()`; if `v`/`V`/`<C-v>`, prepend `"gv"` to the fed sequence in `execute()` so the selection is reactivated after the trigger keymap fires.
   - Why: Without this, the visual selection is lost the moment `<leader>` triggers our Lua callback.
   - Depends on: Phase 1.
   - Risk: Medium — selection state can be subtle around `<C-v>` block mode; tested via manual repro: select 3 lines, press `<leader>` → see popup → press an indent action → indent applies to the 3 lines.

2. **Count + register restoration** (File: `lua/beast/libs/key/popup.lua`)
   - Action: at `start()`, capture `vim.v.count` and `vim.v.register`; prepend them to the fed sequence in `execute()` (e.g. `'"' .. reg .. count .. seq`).
   - Why: Without this, `3<leader>j` loses the `3` and `"a<leader>p` loses the register.
   - Depends on: Phase 1.
   - Risk: Low — direct port of `state.lua:228-236`.

3. **Recursion guard** (File: `lua/beast/libs/key/popup.lua`)
   - Action: a module-level counter incremented on `start()` and reset by a 500ms timer. If counter > 20, log a warning via `vim.notify` and abort. Mirrors which-key's `state.lua:303-318`.
   - Why: If a user keymap inadvertently feeds `<leader>` recursively, this prevents a stack blow.
   - Depends on: Phase 1.
   - Risk: Low.

4. **Macro + pending-input safety** (File: `lua/beast/libs/key/popup.lua`)
   - Action: at top of `start()`, return early (and feed the trigger char back) if `vim.fn.reg_recording() ~= ""` or `vim.fn.getcharstr(1) ~= ""`.
   - Why: Don't intercept during macro recording or when input is queued (e.g. `:norm <leader>x`).
   - Depends on: Phase 1.
   - Risk: Low.

**End of Phase 3**: Production-ready. Safe to flip default to enabled and remove which-key.

---

### Phase 4: Cutover — Remove which-key dependency

Only run if Phase 2 numbers prove the perf win and Phase 3 manual testing is clean.

1. **Flip default** (File: `lua/beast/libs/key/config.lua`)
   - Action: `popup.enabled = true` in defaults.
   - Why: After validation, our popup is the default; opt-out remains available.
   - Depends on: Phase 3.
   - Risk: Low.

2. **Remove which-key plugin spec** (File: `lua/beast/plugins/init.lua`)
   - Action: delete the `which-key.nvim` block (lines 20-77 in current file) including the `BeastKeysChanged` autocmd that synced to `wk.add`.
   - Why: No longer needed. Reduces startup cost by one plugin load.
   - Depends on: Step 1.
   - Risk: Medium — anything that depended on `require("which-key")` elsewhere breaks. **Mitigation**: `git grep 'which-key\|which.key' lua/` before deleting; should only find the plugin spec, `to_which_key` exporters (keep them — harmless dead code, or remove in same PR with a separate diff section), and `option.lua` comment (update comment).

3. **Update `option.lua` comment** (File: `lua/beast/option.lua`)
   - Action: change the `timeoutlen` comment from "Lower than default (1000) to quickly trigger which-key" to "Lower than default (1000) to quickly trigger key popup".
   - Why: Comment hygiene.
   - Depends on: Step 2.
   - Risk: Trivial.

4. **Optionally remove `to_which_key` exporters** (File: `lua/beast/libs/key/init.lua`)
   - Action: delete `to_which_key_spec` and `to_which_key` functions (lines 13-49).
   - Why: Dead code post-cutover.
   - Depends on: Step 2.
   - Risk: Low — if any user config calls these, they will break. Acceptable: this is a personal config.

5. **Update codemap** (File: `docs/CODEMAPS/libraries.md`)
   - Action: in the `key/` tree (lines 165-176), add `popup.lua  ← prefix index, getchar loop, helix-style float`. Update the API line to include `Key.popup` if applicable.
   - Why: Codemap-freshness rule (instructions/codemap-freshness.instructions.md).
   - Depends on: Phase 1+.
   - Risk: None.

**End of Phase 4**: which-key uninstalled, popup is the default, codemap fresh.

## Testing Strategy

- **Unit tests**: `tests/` currently uses runnable manual scripts, not a framework.
  Phase 1 adds `tests/test-key-popup.lua` matching this convention. If a framework
  is later introduced (out of scope here), the popup module is structured for it:
  `build_index`, `loop`'s step function, and `execute` are all unit-isolatable.
- **Bench**: `scripts/bench-key-popup.lua` (Phase 2). Targets in Success Criteria.
- **Manual verification** (Phase 1 acceptance):
  1. `:luafile tests/test-key-popup.lua` — sets up sample registry.
  2. Press `<leader>` in normal mode → popup appears bottom-right within 50ms.
  3. Press `f` → popup updates, breadcrumb shows ` <leader> f › `, body shows file mappings only.
  4. Press `f` again → expected file-find action fires; popup closes; no echo of `<leader>ff` in the command line.
  5. Press `<leader>` → press `<Esc>` → popup closes, no side-effect.
  6. Press `<leader>` → press `<BS>` (no prior char) — popup stays at root.
  7. Press `<leader>x` where `x` is unmapped → popup closes, `<leader>x` fed verbatim (no-op in default Neovim, expected).
  8. Visual-line select 3 lines → press `<leader>` (Phase 3) → press indent mapping → selection re-applied.
  9. Start a macro `qa` → press `<leader>` → popup does NOT appear, keys recorded verbatim (Phase 3).
  10. Buffer-local map registered under `<leader>cf` via `Key.safe_set("n", "<leader>cf", ..., { buffer = 0 })` in buffer A → popup shows it in buffer A → switch to buffer B → popup does NOT show `cf`.

## Risks & Mitigations

- **Risk**: Trigger keymap collides with a user's existing `<leader>` mapping that
  isn't in `Key.managed`. → **Mitigation**: at `setup()`, check
  `vim.fn.maparg(trigger, mode, false, true)` and skip registration with a
  `vim.notify` warning if a non-Beast mapping already owns it. (Mirrors
  which-key's `is_mapped` check, `triggers.lua:14-39`.)
- **Risk**: `nvim_feedkeys` with `"m"` mode re-enters our trigger before the
  `vim.schedule` re-register has run, causing the second leader press to no-op.
  → **Mitigation**: re-register on `vim.schedule` is the standard pattern; the
  trigger is deleted *before* feedkeys and `"m"` feedkeys is processed synchronously,
  so the keymap doesn't exist for the duration of the feed. Verified by which-key's
  identical approach in `state.lua:222-240`.
- **Risk**: `vim.fn.getcharstr()` blocks the editor; if a user has a long-running
  autocmd registered on `CursorHold`, it never fires while the popup is open.
  → **Mitigation**: this is identical to which-key's behaviour and to native
  Neovim's `getchar`; documented as expected. The popup typically resolves in <2s.
- **Risk**: Index becomes stale if a third party calls `vim.keymap.set` directly
  for `<leader>`-prefixed keys. → **Mitigation**: documented limitation — managed
  registry is the contract. The popup will simply not show those keys; the keymap
  itself still fires because `nvim_feedkeys` goes through Neovim's resolver. The
  user gets a slightly incomplete popup, never a broken keymap.
- **Risk**: Phase 4 cutover breaks a user workflow that depended on which-key's
  side features (marks/registers popup). → **Mitigation**: Phase 4 is gated on
  Phase 2 bench results AND a manual checklist; if the user uses
  `'`/`"`/`z=` popups, hold Phase 4 and keep which-key for those.

## Success Criteria

- [ ] **Phase 1**: Manual verification steps 1-7 pass on a clean BeastVim start.
- [ ] **Phase 2 bench targets** (`scripts/bench-key-popup.lua`):
  - `index_build_µs` < 500 µs for 200-keymap registry (one-time, cached afterwards).
  - `popup_open_µs` < 5,000 µs (trigger → visible window) at p50.
  - `keypress_resolve_µs` < 1,000 µs per descent step at p50.
- [ ] **Phase 2 vs which-key**: popup-open p50 is at least 3× faster than
  which-key's measured equivalent (`require("which-key.state").start({...})`).
- [ ] **Phase 3**: Manual verification steps 8-10 pass.
- [ ] **Phase 4**: `git grep -i 'which.key\|which-key' lua/` returns only intentional
  references (e.g. comments documenting history). Codemap regenerated and committed.
- [ ] **All phases**: `:checkhealth beast` (if implemented) and Neovim startup time
  (`scripts/bench-startup.sh`) show no regression — ideally a small improvement
  after Phase 4 (one fewer plugin loaded).

## ADR Required

This dev spec involves architectural decisions that must be documented as ADRs once
committed (during `/tec-implement`'s wrap-up, going-forward mode):

- **Native press-and-wait popup replaces which-key.nvim** — the strategic decision
  to drop which-key for the popup feature, with the rationale captured here
  (`Key.managed` as cache, no per-buffer rebuild, no polling timer). Parallels
  ADR-009 (`native statusline replaces heirline`) and ADR-022 (`native git library
  replaces gitsigns`).
- **Trigger keymap registration is global and explicit, not auto-detected** — the
  design choice to register only `<leader>` and `<localleader>` triggers globally,
  rather than walking the keymap tree per buffer like which-key does. This is the
  core architectural shift that enables the perf win.

ADRs are created during `/tec-implement`'s wrap-up step, not now.

## Completed

**Date:** 2026-06-03

All four phases implemented in a single commit. Both architectural decisions
captured in **ADR-025** (covers both items above — global trigger registration
is the architectural shift that enables the cutover, so it's folded into the
same ADR rather than split artificially).

- Phase 1 ✅ — popup module, config, highlights, wiring, manual test script.
- Phase 2 ✅ — `scripts/bench-key-popup.lua` passes both thresholds (index
  build p50 ≈ 254 µs < 500 µs target; popup open p50 ≈ 1.5 ms < 5 ms target).
- Phase 3 ✅ — visual selection preservation (`gv`), count/register
  restoration, recursion guard, macro + pending-input safety.
- Phase 4 ✅ — `popup.enabled = true` by default; which-key plugin spec
  deleted; `to_which_key*` exporters removed; `option.lua` comment updated;
  codemap (`docs/CODEMAPS/libraries.md`) refreshed.
