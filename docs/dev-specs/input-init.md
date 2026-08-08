---
name: input-init
description: Cursor-anchored floating replacement for vim.ui.input with centered fallback
generated: 2026-08-09
---

> PM Spec: [docs/pm-specs/input-init.md](../pm-specs/input-init.md)

# Summary

Input is a new `lua/beast/libs/input/` library that replaces the native `vim.ui.input` prompt with a themed floating box. It anchors to the cursor (preferring above, flipping below when there's no room) when the current window is a normal editable buffer, and falls back to a centered, near-top overlay otherwise. It's wired in eagerly at startup by monkey-patching `vim.ui.input`, since — unlike `confirm` — there's no explicit call site to hang a lazy trigger off.

---

# Context

## Problem

`vim.ui.input` is currently unmodified native Neovim: a plain single-line command-line prompt. BeastVim already has two precedents for themed floating replacements of native prompt UIs — `lua/beast/libs/confirm/` (drop-in for `vim.fn.confirm`) and `lua/beast/libs/finder/ui/input.lua` (the finder's prompt-buffer search box) — but nothing intercepts `vim.ui.input` itself, so callers like `vim.lsp.buf.rename()` still show the plain bottom-of-screen prompt.

### Solution

Add `lua/beast/libs/input/`, structured like `confirm/` (init/config/ui/highlights), plus a new `position.lua` that isolates the cursor-vs-centered decision as a pure, headlessly-testable function. `vim.ui.input` is monkey-patched to this module's `run()` during `beast.setup()`, eagerly (not lazily), so the override exists before any caller — including Neovim's own LSP rename path — might invoke it.

---

# Research

### Repo Search
- Searched for: `vim.ui.input`, `vim.ui.select`, `dressing.nvim`, `noice.nvim`, `snacks.nvim`, `screenpos`, `winline`, `relative = "cursor"`, `vim.fn.input(`
- Found: No existing override of `vim.ui.input`/`vim.ui.select` anywhere in BeastVim. The explorer's rename/create prompts (`lua/beast/libs/explorer/prompt.lua`) use a fully separate, bespoke inline-float input system tied to explorer tree row/col (`open_float`, `M.overlay`, `M.inline`) — they don't go through `vim.ui.input` at all, so they're unaffected and out of scope here. `lua/beast/libs/image/init.lua:94-103` and `:182-193` already compute a window's absolute screen row/col via `vim.fn.screenpos` + `nvim_win_get_position` — the exact technique needed to detect "not enough room above the cursor."
- Reuse opportunity: Yes — reuse the `screenpos`-based screen-coordinate technique from `image/init.lua`, the `View` buf/win wrapper, the prompt-buffer (`buftype=prompt` + `prompt_setprompt`) and extmark-highlighting pattern from `lua/beast/libs/finder/ui/input.lua:41-116`, and the headless-fallback / `disabled`-flag config pattern from `lua/beast/libs/confirm/{init,config}.lua`.

### Built-in / Existing Lib Check
- Checked: `vim.ui.input`/`vim.ui.select` (native defaults only), `nvim_open_win`'s `relative="cursor"` + `anchor` params, `vim.fn.getcompletion` / `'completefunc'` (native command-line completion contract), `vim.fn.screenpos`/`vim.fn.winline()`, `beast.libs.view`, `beast.libs.confirm`, `beast.libs.finder/ui/input.lua`.
- Found: `nvim_open_win`'s `relative="cursor"` already handles positioning a float at the cursor natively (the `anchor` param — `"NW"` vs `"SW"` — decides whether it grows down or up); we only need to decide *which* anchor to use and *whether* cursor-relative applies at all, not hand-compute row/col ourselves. `vim.fn.screenpos`/`winline()` (already used in `image/init.lua`) is sufficient to detect insufficient room above. External reference `/Users/loctvl842/Documents/GitDepot/dressing.nvim/lua/dressing/input.lua` was inspected for how to bridge `opts.completion` to Neovim's completion contract (`completefunc` → `vim.fn.getcompletion`, `dressing/input.lua:226-267`) and `opts.highlight` to buffer highlights (`dressing/input.lua:203-224`) — it informs the approach but isn't vendored (this is a pure-Lua config with no package manager).
- Decision: **Build** — nothing in BeastVim or Neovim core already provides a themed, cursor-aware `vim.ui.input` replacement. The pieces it needs (cursor-relative floats, screen-space math, prompt buffers, extmark highlighting) already exist individually as patterns in `confirm/`, `finder/`, and `image/`, and get composed into a new `lua/beast/libs/input/` lib rather than duplicated.

---

# Architecture Changes

- `lua/beast/libs/input/config.lua` (new) — `disabled` flag, mirrors `confirm/config.lua`'s read-only metatable pattern exactly.
- `lua/beast/libs/input/highlights.lua` (new) — `BeastInput*` highlight groups, mirrors `confirm/highlights.lua`.
- `lua/beast/libs/input/position.lua` (new) — pure decision function: cursor-anchored (with above/below flip) vs. centered fallback.
- `lua/beast/libs/input/ui.lua` (new) — floating window creation/render: prompt buffer, completion bridging, highlight-callback application, confirm/cancel keymaps.
- `lua/beast/libs/input/init.lua` (new) — `run(opts, on_confirm)` matching the native `vim.ui.input` contract, headless fallback, `setup()`.
- `lua/beast/init.lua` (modified) — add an eager `require("beast.libs.input").setup()` call near the other eager libs (`notify`, `image.viewer`, around line 71-85).
- `tests/test-input-position.lua` (new) — headless tests for `position.lua`'s resolve function.

## Implementation Phases

## Phase 1: Core lib — centered-fallback box, confirm/cancel, wired into vim.ui.input
1. **Config module** (File: `lua/beast/libs/input/config.lua`)
   - Action: Create a `disabled` flag with the same read-only metatable + `setup(opts)` merge pattern as `lua/beast/libs/confirm/config.lua`.
   - Why: Consistent headless/testing escape hatch across the two prompt libs.
   - Depends on: None
   - Risk: Low

2. **Highlights module** (File: `lua/beast/libs/input/highlights.lua`)
   - Action: Define `BeastInput{Normal,Border,Title,Placeholder}` groups using `Util.colors.build`, mirroring `confirm/highlights.lua`.
   - Why: Visual consistency with the rest of BeastVim's floating UI family.
   - Depends on: None
   - Risk: Low

3. **Centered-fallback UI** (File: `lua/beast/libs/input/ui.lua`)
   - Action: Implement `M.create(opts)` opening a rounded-border floating window positioned in the upper area of the screen (`relative="editor"`, row near 1/4 of `vim.o.lines` rather than dead-center like `confirm`'s modal), `buftype=prompt` via `prompt_setprompt`, title set to `opts.prompt`. Pre-fill `opts.default` with cursor placed at the end (`startinsert!`). `<CR>` reads the buffer line (stripping the prompt prefix, like `finder/ui/input.lua:120-133`) and calls `on_confirm`; `<Esc>`/`BufLeave` calls `on_confirm(nil)`.
   - Why: Smallest working replacement — implements PM spec Scenario 3 (no anchor) and Scenario 4 (cancel) end to end.
   - Depends on: Steps 1-2
   - Risk: Medium (prompt-buffer + floating-window edge cases)

4. **Entry point + monkey-patch** (File: `lua/beast/libs/input/init.lua`)
   - Action: `run(opts, on_confirm)` validates `on_confirm`, normalizes `opts`, and — mirroring `confirm/init.lua`'s `vim.api.nvim_list_uis()[1]` check — falls back to a plain `vim.fn.input`-based flow when headless. Otherwise calls `ui.create(opts)` and lets its keymaps invoke `on_confirm` directly (callback-based, not a blocking `getcharstr` loop like `confirm`'s `run_modal_loop`, since `vim.ui.input` is async). `setup()` registers highlights via `require("beast").apply_highlights(...)`, calls `config.setup(opts)`, and assigns `vim.ui.input = M.run` (falling back to the native implementation when `config.disabled`, same as `confirm`'s `__call` metatable does for `vim.fn.confirm`).
   - Why: The actual contract-matching entry point.
   - Depends on: Steps 1-3
   - Risk: Medium (global monkey-patch correctness)

5. **Wire into startup** (File: `lua/beast/init.lua`)
   - Action: Add `require("beast.libs.input").setup()` as an eager call alongside the other eager libs (`require("beast.libs.notify").setup(...)`, `require("beast.libs.image.viewer").setup(...)` around line 71-85) — explicitly NOT via `packer.lazy`'s `module` trigger.
   - Why: `confirm` can use a `module` lazy trigger because every caller explicitly does `require("beast.libs.confirm")`. Nothing calls `require("beast.libs.input")` directly — Neovim/LSP internals call the global `vim.ui.input(...)` — so the patch must exist before startup finishes, unconditionally.
   - Depends on: Step 4
   - Risk: Low, but this adds to the eager startup path — verify with `bench-startup.sh` per `DEVELOPMENT.md`.

## Phase 2: Cursor-anchored positioning with above/below flip
1. **Position resolver** (File: `lua/beast/libs/input/position.lua`)
   - Action: `M.resolve(box_height)` returns `{ mode = "cursor", anchor = "SW"|"NW" }` or `{ mode = "center" }`. Rule: if the current buffer's `buftype ~= ""` or the current window is itself floating (`nvim_win_get_config(0).relative ~= ""`), return `{mode="center"}` (no meaningful anchor — covers PM Scenario 3). Otherwise compute the cursor's absolute screen row via `vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))` (same technique as `image/init.lua:94-103`) and compare against `box_height` plus border rows: enough room above → `anchor="SW"` (grows upward, PM Scenario 1); not enough room → `anchor="NW"` (grows downward, PM Scenario 2).
   - Why: Isolates the trickiest, most decision-heavy logic into a pure, headlessly-testable function, keeping `ui.lua` simple.
   - Depends on: None (new file)
   - Risk: Medium (screen-space edge cases near window/screen boundaries)

2. **Wire position into ui.create** (File: `lua/beast/libs/input/ui.lua`, modified)
   - Action: Call `position.resolve(box_height)` before `nvim_open_win`. If `mode=="cursor"`, open with `relative="cursor", anchor=<anchor>` and let Neovim's own cursor-relative placement handle row/col (matching `dressing.nvim`'s technique at `dressing/input.lua:316-323`, `dressing/util.lua:69-75`). If `mode=="center"`, use Phase 1's centered-fallback geometry unchanged.
   - Why: Implements PM spec Scenarios 1-3 fully.
   - Depends on: Phase 1 step 3, Phase 2 step 1
   - Risk: Medium

3. **Headless position tests** (File: `tests/test-input-position.lua`, new)
   - Action: Exercise `position.resolve()` with a normal buffer window at cursor rows near the top / middle / bottom of the window (asserting the anchor flip), and with a non-empty `buftype` / a floating current window (asserting `mode=="center"`). Follow the structure of `tests/test-finder-status.lua`.
   - Why: This decision logic is pure and cheap to verify headlessly without a real UI session.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Completion and highlight parity
1. **Completion bridging** (File: `lua/beast/libs/input/ui.lua`, modified)
   - Action: When `opts.completion` is set, set `vim.bo[buf].completefunc`/`omnifunc` to a Lua function dispatching to `vim.fn.getcompletion(base, opts.completion)` (handling `custom`/`customlist` funcref forms per `:help command-completion`, using `dressing/input.lua:226-267` as reference), and map `<Tab>` to trigger completion (`<C-x><C-u>` / `<C-n>` depending on pum state, like `dressing`'s `trigger_completion`).
   - Why: Native parity for `opts.completion` — implements PM spec STATE 4 / Scenario 5.
   - Depends on: Phase 1-2
   - Risk: Medium (completion source edge cases)

2. **Highlight callback** (File: `lua/beast/libs/input/ui.lua`, modified)
   - Action: On `TextChanged`/`TextChangedI`, call `opts.highlight(text)` and apply the returned `{start, end, hl_group}` triples as extmarks in the prompt buffer, clearing previous extmarks first — mirrors the extmark-highlighting pattern already used for the prompt prefix in `finder/ui/input.lua:76-82`. Function form only (BeastVim configs pass Lua functions; the vimscript-funcref string form isn't a real-world need here).
   - Why: Native parity for `opts.highlight`.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: `tests/test-input-position.lua` (new) — run via `nvim --clean --headless -l tests/test-input-position.lua`.
- Bench: not a hot/looped path like the finder matcher, so no new `scripts/bench-*.lua` is needed. Phase 1 does add an eager `require` to the startup path (like `confirm`/`notify`), so run `./scripts/bench-startup.sh` before/after per `DEVELOPMENT.md` to confirm no regression.
- Manual: walk through the PM spec's 5 scenarios in a real session (`LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim nvim`):
  1. LSP rename on a symbol mid-screen → box appears above, pre-filled, edit + Enter returns the new name.
  2. LSP rename on a symbol near the top of the window → box flips to below the cursor.
  3. `:lua vim.ui.input({prompt="Commit message"}, print)` run with a non-buffer current window (e.g. a terminal or floating window) → centered, near-top overlay.
  4. Esc from any of the above → `on_confirm` receives `nil`.
  5. `:lua vim.ui.input({prompt="File", completion="file"}, print)` → completion dropdown works via `<Tab>`; a quick ad-hoc `opts.highlight` function → typed text is colored live.

# Success Criteria

- [ ] Renaming a symbol shows the input anchored above the word under the cursor.
- [ ] When there's no room above, the input flips to below the cursor instead of overlapping code or the window edge.
- [ ] Prompts with no meaningful buffer context appear as a centered, near-top overlay instead of anchoring arbitrarily.
- [ ] Cancelling with Esc returns nil to the caller, matching native `vim.ui.input`.
- [ ] Completion and highlight callbacks work exactly as documented for native `vim.ui.input`.
- [ ] Visual style (border, colors, title) matches BeastVim's existing confirm dialog and finder search box.
- [ ] Every existing caller of `vim.ui.input` in BeastVim (LSP rename being the primary real-world one) continues to work without changes to its own code.
- [ ] `tests/test-input-position.lua` passes headless.
- [ ] `bench-startup.sh` shows no meaningful regression vs. baseline.
