---
name: visibility-init
description: New lua/beast/visibility.lua global state module (hidden, gitignored) wired into Explorer, Finder, and the tabline via a BeastVisibilityChanged User autocmd
generated: 2026-07-29
---

> PM Spec: [docs/pm-specs/visibility-init.md](../pm-specs/visibility-init.md)

# Summary

Add `lua/beast/visibility.lua`, a single top-level state module holding two booleans (`hidden`, `gitignored`) with `toggle_hidden()`/`toggle_gitignored()` that each fire `vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", data = { key, value } })`. Wire Explorer and Finder to read this module instead of their own local flags, and add a `User BeastVisibilityChanged` listener in each so open panels refresh live. Add two clickable icons to the tabline beside the existing day/night button, and two global keymaps (`<leader>uh`, `<leader>ug`).

---

# Context

## Problem

Explorer and Finder each currently decide file visibility independently and disagree:

- **Explorer**: `show_hidden` toggle exists (`lua/beast/libs/explorer/config.lua`, default off, `H` key, buffer-local to the explorer window), but has **no gitignore filtering** — gitignored files/dirs (e.g. `node_modules/`) always show in the tree. Explorer *does* already compute per-node git-ignored status (`node.git_status.kind == "ignored"`, via `lua/beast/libs/explorer/git.lua`'s `git status --porcelain=v2 --ignored`), it's just never used to filter — only for badge coloring.
- **Finder**: hardcodes `--hidden` in its fd/rg/find invocations (`lua/beast/libs/finder/source/files.lua`, dotfiles always shown, no toggle), and never passes `--no-ignore` (gitignored files always excluded, no toggle) — the opposite defaults from Explorer, and neither is user-controllable.

### Solution

A new `lua/beast/visibility.lua` becomes the single source of truth for both booleans. Explorer's `config.lua` delegates its `show_hidden` read to this module (so ~15 existing call sites need no changes), and gains a gitignore filter in `tree.lua`'s `flat()` that reuses the git-ignored status Explorer already computes. Finder's `files.lua`, `live_grep/init.lua`, and the bigram `engine/builder.lua` all read the same module to build their command-line args instead of hardcoding `--hidden`. Every consumer (Explorer, Finder, the tabline) listens for `User BeastVisibilityChanged` and refreshes live — the same "single explicit invalidation signal" pattern already used elsewhere in the codebase (`BeastGitIndexChanged` in explorer, `BeastStatuslineGitChanged` in statusline, `BeastKeysChanged` in the key module).

**Decided**: Finder's live_grep bigram prefilter index (built once via `rg --files`, never includes gitignored files) will be force-rebuilt whenever the `gitignored` switch changes, so search stays correct rather than silently stale.

---

# Research

### Repo Search
- Searched for: `gitignore`, `--ignored`, `nvim_exec_autocmds`, `"User"` autocmd usage, `show_hidden`, `hidden` flags in finder sources.
- Found: Explorer already computes per-node git-ignored status (`beast/libs/explorer/git.lua`, `git status --porcelain=v2 --ignored`) but only uses it for badge coloring, never filtering. Finder's `files.lua`, `live_grep/init.lua`, and the bigram `engine/builder.lua` all hardcode `--hidden` and never pass a no-ignore flag — three separate places with the same hardcoded assumption. The codebase already has an established "fire a `User` autocmd, listeners registered from each lib's own `autocmds.lua`/setup" pattern used 3 times (`BeastGitIndexChanged`, `BeastStatuslineGitChanged`, `BeastKeysChanged`) — exactly the pattern proposed for `BeastVisibilityChanged`.
- Reuse opportunity: **Yes** — Explorer's existing `git_status.kind == "ignored"` field means gitignore filtering in Explorer needs zero new git calls, just a filter predicate. The `User` autocmd + augroup-scoped-listener idiom is directly reusable, not something to invent.

### Built-in / Existing Lib Check
- Checked: `beast.libs.key` (`Key.safe_set`, used for existing global toggles like `<leader>up`), `beast.libs.finder.state` (`pipeline.load`/`pipeline.run`, the existing re-query entry points on input change), `beast.libs.finder.source.live_grep.engine.index` (`M.build`, the existing full-rebuild entry point used on cwd switch), `docs/development/lib-conventions.md` §7 ("cache anything derived from expensive computation, invalidate via a single explicit `User` autocmd signal — never poll").
- Found: All of the above directly cover what's needed — no built-in Neovim API or new abstraction required.
- Decision: **Reuse** — every consumer wiring calls an existing entry point (`Key.safe_set`, `pipeline.load`/`run`, `engine.index.M.build`, `state.tree:_touch()` + `ui.render()`); the only genuinely new code is the ~40-line `beast/visibility.lua` module itself and the two new tabline section/highlight files (which mirror `toggle_button.lua` 1:1).

**Correctness nuance**: toggling `hidden` is always safe to leave the bigram index untouched, because the index builder already includes hidden files unconditionally today (`--hidden` hardcoded) — the index is already a safe *superset* of whatever `hidden=false` needs, and the final rg/ug call (not the prefilter) does the actual hidden-file exclusion. Toggling `gitignored` is different: the index was built by a `rg --files` call that structurally never saw gitignored files, so no post-hoc filtering can recover them — only a rebuild can. Only the `gitignored` toggle triggers `engine.index`'s rebuild path, not the `hidden` toggle.

---

# Architecture Changes

- `lua/beast/visibility.lua` (new) — core state module: `hidden`/`gitignored` booleans, `toggle_hidden()`/`toggle_gitignored()`, `setup(opts)`. Emits `User BeastVisibilityChanged` with `data = { key, value }` on every toggle. Follows the read-only-proxy `config.lua` idiom used by every existing lib (`methods` table + `cfg` table + `__index`/`__newindex` metatable), as a single top-level file like `lua/beast/option.lua`/`lua/beast/icon.lua` rather than a `libs/<name>/` folder.
- `lua/beast/init.lua` — eager `require("beast.visibility").setup(cfg.visibility)` near the existing `require("beast.option")` call (must exist before Explorer/Finder/Tabline, which are all lazy-loaded). Add `---@field visibility? Beast.Visibility.Config` to `Beast.Config`. Register `<leader>uh`/`<leader>ug` via `Key.safe_set(...)` next to the existing global toggles (`<leader>up`, `<leader>d`, etc. around line 387).
- `lua/beast/libs/explorer/config.lua` — `__index` special-cases `"show_hidden"` to read `require("beast.visibility").hidden` instead of the local `cfg.show_hidden` — every existing call site (`config.show_hidden`, ~15 places in `actions/*.lua`) keeps working with zero changes. Remove `defaults.show_hidden` and `methods.toggle_hidden()` (now dead).
- `lua/beast/libs/explorer/actions/show_hidden.lua` — delegate to `require("beast.visibility").toggle_hidden()` instead of `config.toggle_hidden()`. The `H` key inside Explorer becomes just another trigger of the shared global toggle.
- `lua/beast/libs/explorer/tree.lua` — `flat(opts)`: add a second filter predicate — skip a node when `not require("beast.visibility").gitignored and node.git_status and node.git_status.kind == "ignored"`. Read visibility directly (no new opts field, no call-site changes). Change `_flat_cache` key from a single boolean (`opts.show_hidden`) to a composite key incorporating both booleans.
- `lua/beast/libs/explorer/autocmds.lua` — add a `User BeastVisibilityChanged` listener (same shape as the existing `BeastGitIndexChanged` listener): `state.tree:_touch()` + `ui.render()` + `sticky.refresh()` (no git re-fetch needed, only re-filter).
- `lua/beast/libs/finder/source/files.lua` — in each `SUPPORTED[].args(cwd)`: make `--hidden` (fd/rg) conditional on `require("beast.visibility").hidden`; make `--no-ignore` (fd/rg) conditional on `.gitignored`; for the `find` fallback, add `-not -path '*/.*'` when hidden is off (find has no native gitignore support — gitignored toggle is a no-op for this fallback, matching the PM spec's "no rules to apply" edge case).
- `lua/beast/libs/finder/source/live_grep/init.lua` — same conditional treatment for `base_args`'s hardcoded `--hidden` (both the `rg` and `ug` branches); add the no-ignore equivalent flag when gitignored is on (confirm exact flag name for `ug` during implementation — ripgrep's is `--no-ignore`).
- `lua/beast/libs/finder/source/live_grep/engine/builder.lua` — `list_files()`: same conditional `--hidden`/no-ignore treatment on the `rg --files` enumeration call, so the index's survivor set matches current visibility.
- `lua/beast/libs/finder/source/live_grep/engine/index.lua` — on `gitignored` toggle specifically, force a rebuild of the current root's index (reuse the existing `M.build(root, opts, on_done)` path already used on cwd switch).
- `lua/beast/libs/finder/autocmds.lua` — in `M.mount(state)`, add a `User BeastVisibilityChanged` listener scoped to `state.augroup` (auto-torn-down on picker close) that re-triggers the active pipeline: `state.pipeline.load(state)` for match-pipeline sources (`files`, `buffers`, …) or `state.pipeline.run(state)` for the stream pipeline (`live_grep`).
- `lua/beast/libs/tabline/config.lua` — add `visibility_hidden_icon` and `visibility_gitignored_icon` defaults. **Decided during implementation**: one static glyph per switch (not on/off glyph pairs like the day/night button) — on/off is conveyed by highlight color alone, which is simpler and reads clearly for a boolean toggle.
- `lua/beast/libs/tabline/highlights.lua` — add `VisibilityOn`/`VisibilityOff` groups (mirroring the existing `ToggleButton` group; "on" brighter, "off" dimmed) — these carry the entire on/off signal since the glyph itself doesn't change.
- `lua/beast/libs/tabline/sections/visibility.lua` (new) — `M.width()`/`M.render()` for the two toggle icons, mirroring `sections/toggle_button.lua` exactly — two independent `%@v:lua.<fn>@...%X` click regions in one rendered string.
- `lua/beast/libs/tabline/context.lua` — add `visibility_width` to the per-render ctx (mirrors `toggle_button_width`), used by `sections/buffer_list.lua`'s `available` width calculation.
- `lua/beast/libs/tabline/init.lua` — insert `visibility.render()` into `parts` immediately before `toggle_button.render()`. Register `_G.beast_tabline_toggle_hidden`/`_G.beast_tabline_toggle_gitignored` click handlers calling into `beast.visibility`. Add one `User BeastVisibilityChanged` listener in `ensure_autocmds()` that calls `invalidate(); vim.cmd("redrawtabline")` — the single refresh path regardless of whether the toggle came from a keymap, the tabline click, or Explorer's `H` key.

## Implementation Phases

Each phase is independently mergeable once Phase 1 lands (Phases 2/3/4 don't depend on each other).

## Phase 1: Core module — `lua/beast/visibility.lua` (done)

1. **Create the module** (File: `lua/beast/visibility.lua`)
   - Action: `defaults = { hidden = false, gitignored = false }`; `methods.toggle_hidden()`/`toggle_gitignored()` flip `cfg.<key>` then `vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", data = { key = <key>, value = cfg[<key>] } })`; `methods.setup(opts)` merges opts over defaults via `vim.tbl_deep_extend`. Read-only proxy metatable identical in shape to `beast.libs.explorer.config`.
   - Why: Single source of truth; matches every other config module's shape.
   - Depends on: None
   - Risk: Low

2. **Wire into `lua/beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action: `require("beast.visibility").setup(cfg.visibility)` placed right after `require("beast.option")`. Add `---@field visibility? Beast.Visibility.Config` to `Beast.Config`. Add two `Key.safe_set("n", "<leader>uh", ...)` / `("<leader>ug", ...)` calls beside the existing global toggles, with `group = "Visibility"`.
   - Why: Matches the existing pattern for always-on global keymaps exactly.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Explorer integration (done)

1. **Delegate `show_hidden` reads/writes** (File: `lua/beast/libs/explorer/config.lua`)
   - Action: `__index` returns `require("beast.visibility").hidden` when `key == "show_hidden"`, before falling through to `cfg[key]`. Remove `show_hidden` from `defaults` and delete `methods.toggle_hidden`.
   - Why: Zero-diff for the ~15 existing `config.show_hidden` call sites.
   - Depends on: Phase 1
   - Risk: Low

2. **Delegate the `H` action** (File: `lua/beast/libs/explorer/actions/show_hidden.lua`)
   - Action: Replace `config.toggle_hidden()` with `require("beast.visibility").toggle_hidden()`.
   - Why: The in-explorer key becomes one more trigger for the shared global state.
   - Depends on: Step 1
   - Risk: Low

3. **Add gitignore filtering** (File: `lua/beast/libs/explorer/tree.lua`)
   - Action: In `flat(opts)`, skip nodes where `not require("beast.visibility").gitignored and node.git_status and node.git_status.kind == "ignored"`. Change `_flat_cache` from `table<boolean, ...>` to a table keyed by a composite string.
   - Why: Reuses Explorer's already-computed git-ignored status; no new git calls.
   - Depends on: Phase 1
   - Risk: Medium (cache-key change touches a hot render path; verify with `bench-explorer.lua`)

4. **Live refresh listener** (File: `lua/beast/libs/explorer/autocmds.lua`)
   - Action: Add a `User BeastVisibilityChanged` autocmd (same `state.augroup`, next to the existing `BeastGitIndexChanged` listener) calling `state.tree:_touch(); ui.render(); sticky.refresh()`, guarded by the same validity check used elsewhere in this file.
   - Why: Live update while Explorer is open in the background, no close/reopen needed.
   - Depends on: Steps 1, 3
   - Risk: Low

## Phase 3: Finder integration (done)

1. **`files` source flags** (File: `lua/beast/libs/finder/source/files.lua`)
   - Action: In each `SUPPORTED[].args(cwd)`, read `require("beast.visibility")` and conditionally include `--hidden` (fd/rg) and `--no-ignore` (fd/rg); add `-not -path '*/.*'` to the `find` fallback when hidden is off.
   - Why: Removes the two hardcoded assumptions that make Finder disagree with Explorer today.
   - Depends on: Phase 1
   - Risk: Low

2. **`live_grep` base args** (File: `lua/beast/libs/finder/source/live_grep/init.lua`)
   - Action: Same conditional treatment on `base_args`'s `--hidden`, plus the no-ignore equivalent for both the `rg` and `ug` branches.
   - Why: live_grep's own final search pass must respect the toggle even when the bigram prefilter is disabled or bypassed.
   - Depends on: Phase 1
   - Risk: Low (verify `ug`'s no-ignore flag name during implementation)

3. **Bigram builder + rebuild-on-gitignored-toggle** (Files: `lua/beast/libs/finder/source/live_grep/engine/builder.lua`, `.../engine/index.lua`)
   - Action: `list_files()` gets the same conditional `--hidden`/no-ignore treatment. In `index.lua`, on a `gitignored`-keyed `BeastVisibilityChanged` event, force a rebuild of the current root via the existing `M.build(root, opts, on_done)` path.
   - Why: Per the Research correctness nuance — only `gitignored` toggles can make the existing index miss files it structurally never scanned.
   - Depends on: Phase 1
   - Risk: Medium (touches the bigram engine's rebuild lifecycle; verify with `bench-finder-matcher.lua` + manual test on a fixture repo)

4. **Live requery listener** (File: `lua/beast/libs/finder/autocmds.lua`)
   - Action: In `M.mount(state)`, add a `User BeastVisibilityChanged` listener scoped to `state.augroup` that calls `state.pipeline.load(state)` (match pipeline) or `state.pipeline.run(state)` (stream pipeline).
   - Why: Refreshes an open Finder's results immediately, matching Explorer's live-refresh behavior.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 4: Tabline buttons (done)

1. **Icon + highlight defaults** (Files: `lua/beast/libs/tabline/config.lua`, `lua/beast/libs/tabline/highlights.lua`)
   - Action: Add `visibility_hidden_icon`, `visibility_gitignored_icon` config defaults (one static glyph each — decided during implementation to convey on/off via highlight color only, not a glyph swap); add `VisibilityOn`/`VisibilityOff` highlight groups mirroring `ToggleButton`.
   - Why: Simpler than on/off glyph pairs for a boolean toggle; the color alone reads clearly.
   - Depends on: None (can start in parallel with Phase 1)
   - Risk: Low

2. **New section** (File: `lua/beast/libs/tabline/sections/visibility.lua`, new)
   - Action: `M.width()`/`M.render()` mirroring `sections/toggle_button.lua`, rendering two adjacent click regions reading `require("beast.visibility").hidden`/`.gitignored` for on/off icon + highlight selection.
   - Why: Same file shape as the button it sits beside.
   - Depends on: Phase 1 Step 1
   - Risk: Low

3. **Wire into render + clicks + live refresh** (Files: `lua/beast/libs/tabline/context.lua`, `lua/beast/libs/tabline/sections/buffer_list.lua`, `lua/beast/libs/tabline/init.lua`)
   - Action: Add `visibility_width` to `context.lua`'s ctx (used by `buffer_list.lua`'s `available` calc); insert `visibility.render()` into `init.lua`'s `parts` right before `toggle_button.render()`; register the two `_G.beast_tabline_toggle_*` click handlers calling `beast.visibility`'s toggle functions; add one `User BeastVisibilityChanged` listener in `ensure_autocmds()` calling `invalidate(); vim.cmd("redrawtabline")`.
   - Why: Places the buttons exactly where the PM spec asks (beside day/night) and keeps them live regardless of toggle source.
   - Depends on: Steps 1, 2
   - Risk: Low

# Testing Strategy

- Headless tests: new `tests/test-visibility.lua` (no `test-explorer.lua`/`test-finder.lua` exist yet to extend) — covers `toggle_hidden`/`toggle_gitignored` flipping state and firing `BeastVisibilityChanged` with the right `data.key`/`data.value`. Run with `nvim --clean -u tests/test-visibility.lua`.
- Bench (mandatory per `DEVELOPMENT.md`, since this touches benched libs): `nvim --clean --headless -l scripts/bench-explorer.lua` and `nvim --clean --headless -l scripts/bench-finder-matcher.lua` + `scripts/bench-tabline.lua`. All must stay PASS with no regression.
- Manual: walk every scenario in `docs/pm-specs/visibility-init.md` (§Scenarios 1-5) end-to-end in a fixture repo with a `.gitignore`, dotfiles, and a gitignored directory. Additionally: with a live_grep search active, toggle gitignored and confirm the bigram-prefiltered results include newly-visible gitignored matches (validates the Phase 3 Step 3 rebuild, not just the requery).

# Success Criteria

- [x] Toggling hidden files anywhere (keymap, tabline button, or from within Explorer/Finder) is instantly reflected in both Explorer and Finder.
- [x] Toggling gitignored files anywhere is instantly reflected in both Explorer and Finder, including live_grep's prefiltered results.
- [x] `<leader>uh` and `<leader>ug` work regardless of which screen currently has focus.
- [x] The tabline shows two toggle icons beside the day/night button that always reflect current state and are clickable.
- [x] No component-specific "hidden files" or "gitignored files" setting remains — exactly one source of truth (`lua/beast/visibility.lua`).
- [x] `bench-explorer.lua`, `bench-finder-matcher.lua`, and `bench-tabline.lua` all still PASS.
- [x] `stylua --check lua/` clean.

---

## Completed

**2026-07-29** — All 4 phases implemented, reviewed, and verified end-to-end against real `fd`/`rg`/`ug`/`find` processes and a real headless-subprocess bigram-index build (not just unit-style assertions).

- `aebc553` feat(visibility): add global file-visibility state module
- `3e9e14d` feat(explorer): read shared visibility state for hidden/gitignored filtering
- `4d64373` fix(explorer): exclude .git from the tree unconditionally (discovered during Phase 2 verification — pre-existing gap, not part of the original plan; user asked to fix it immediately)
- `fbc2d68` feat(finder): read shared visibility state for hidden/gitignored filtering (includes the Phase 3 Task 3 proactive-rebuild listener, added after code review caught it missing from the first pass)
- `a391e98` feat(tabline): add hidden/gitignored toggle buttons beside day/night button (also commits this spec's docs, adds the previously-missing `tests/test-visibility.lua`, and reflects the color-only icon decision below)

**Notable deviations from the original plan, both explicitly decided rather than silently shipped:**
- Tabline buttons use one static glyph per switch with highlight color (bright/dim) conveying on/off, not the `_on`/`_off` glyph-pair mechanism originally specced (mirroring the day/night button literally) — user confirmed color-only after a code-reviewer flagged the silent substitution.
- `builder.lua`'s bigram-index file enumeration keeps `--hidden` unconditional (never made conditional on the `hidden` toggle) — this was a deliberate correction of an internal inconsistency between the dev spec's Architecture-Changes wording and its own Research section: only `gitignored` invalidates the index, so `hidden` must stay a safe superset there or a hidden-only toggle would silently miss files, exactly what this feature exists to prevent.

**Verification results:**
- `tests/test-visibility.lua`: 17/17 passed.
- `scripts/bench-explorer.lua`: PASS (exit 0), ~515-530µs mixed-scenario (pre-existing soft-target WARN noise at 500µs, confirmed via `git stash` unchanged from baseline ~520-522µs).
- `scripts/bench-finder-matcher.lua`: PASS, full_scan ~17-18ms (<80ms), subset ~16-17ms (<50ms).
- `scripts/bench-tabline.lua`: PASS (exit 0), ~117µs cold render (pre-existing soft-target WARN noise at 50µs, confirmed via `git stash` unchanged from baseline ~122µs).
- `stylua --check lua/` and the touched `scripts/`: clean throughout.
- Manual E2E: all 5 PM-spec scenarios walked against a real fixture git repo (dotfiles, `.gitignore`, gitignored `node_modules/`) with real `fd`/`rg`/`ug` processes — including the bigram-prefilter rebuild-on-toggle (confirmed proactive, before any query was issued) and a live-open Finder/Explorer/tabline all refreshing without reopen.

### Follow-up: tabline button legibility (2026-07-30)

Icon-only tabline buttons gave no hint what they did on first use. Two rounds of polish on top of Phase 4:

- `0017f6d` feat(tabline): add text labels to right-side toggle buttons — hidden/gitignored/dark-light buttons each gained a text label beside the icon (`toggle hidden`, `toggle gitignore`, `toggle dark/light`). The icon still switches color for on/off state (`VisibilityOn`/`VisibilityOff`); the label renders in a separate, constant dimmed color (`VisibilityLabel`) regardless of state. Labels collapse to icon-only automatically (`ctx.buttons_compact`, computed in `context.lua` by comparing the buffer list's natural width against available space) whenever showing them would force the buffer list to truncate — the buffer list always wins the space fight over button legibility.
- `08d011e` test(tabline): account for button width in edge-trim available calc — `tests/test-tabline-edge-trim.lua`'s own "available width" calculation never subtracted the right-side button reservation, silently drifting out of sync with what `buffer_list.lua` actually budgets for. Masked while buttons were a few columns wide; the label work above widened the gap enough to fail 9 of 46 assertions (confirmed pre-existing via `git stash` back to Phase 4, not a new regression). Fixed the calc and adjusted 3 buffer-count thresholds that assumed the old, smaller reservation.

**Verification**: `stylua --check` clean; `tests/test-visibility.lua` 17/17; `tests/test-tabline-edge-trim.lua` 46/46 (was 37/46 before the test fix); `scripts/bench-tabline.lua` unchanged from baseline via `git stash` A/B (~131-135µs cold, same pre-existing soft-target WARN noise as Phase 4).
