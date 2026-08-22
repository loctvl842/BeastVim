---
name: select-init
description: Themed floating replacement for vim.ui.select with search filtering and optional per-item tags
generated: 2026-08-09
---

> PM Spec: [docs/pm-specs/select-init.md](../pm-specs/select-init.md)

# Summary

Select is a new `lua/beast/libs/select/` library that replaces the native `vim.ui.select` prompt with a themed floating picker: a search box that filters items live, a bulleted marker on the highlighted row, and a footer of keybinding hints. It's wired in eagerly at startup by monkey-patching `vim.ui.select`, mirroring how `lua/beast/libs/input/` patches `vim.ui.input` — nothing in BeastVim `require()`s the module directly, since Neovim/LSP/plugin internals call the global `vim.ui.select(...)` themselves.

---

# Context

## Problem

`vim.ui.select` is currently unmodified native Neovim: a plain, unstyled floating list (or numbered command-line prompt) with no search filtering. BeastVim already has three precedents for themed floating replacements of native prompt UIs — `lua/beast/libs/confirm/` (`vim.fn.confirm`), `lua/beast/libs/input/` (`vim.ui.input`), and `lua/beast/libs/finder/` (its own prompt-driven picker, not a native override) — but nothing intercepts `vim.ui.select` itself, so callers like LSP code-action menus and git-action pickers still show the plain native UI.

### Solution

Add `lua/beast/libs/select/`, structured like `input/` (config/highlights/init/ui) plus two new pieces: `filter.lua` (a pure, headlessly-testable substring matcher, isolated the same way `input/position.lua` isolates its positioning decision) and `list.lua` (virtualized list rendering, adapted from `finder/ui/list.lua`'s row-drawing techniques but stripped of fuzzy-scoring, preview, and multi-select). `vim.ui.select` is monkey-patched to this module's `run()` during `beast.setup()`, eagerly, before any caller might invoke it. The footer hint row rides on Neovim's native floating-window `footer`/`footer_pos` config field (confirmed working on this codebase's `nvim-0.10`+ floor) — the same mechanism `input`/`confirm`/`finder` already use for `title`/`title_pos` — so no bespoke footer window or virt_lines hack is needed.

---

# Research

### Repo Search
- Searched for: `vim.ui.select`, `select`-named files/libs, existing telescope/dressing-style pickers, `footer`, `hint`, "to confirm"/"to close" row text, an existing simple/substring matcher utility.
- Found: No `vim.ui.select` override, no telescope dependency, and no `select`-named lib anywhere in `lua/` — confirmed via a dedicated Explore pass and independently by the PM-spec research. `lua/beast/libs/finder/` is the closest analog for a filterable list UI (prompt-buffer search box + virtualized list + right-aligned row highlights) but is considerably more complex than needed here (fuzzy scoring via `matcher.lua`/`score.lua`/`topk.lua`, async streaming pipelines, multi-pane preview) — none of that is reusable wholesale, only specific rendering techniques from `finder/ui/list.lua` and `finder/ui/input.lua`. No footer/hint-row UI element exists anywhere in the codebase (`confirm`, `input`, and `finder` all render title/border only, no footer) — grepping for "footer"/"hint" text patterns across `lua/beast/` returned zero hits. No shared simple-substring-matcher utility exists in `Util` or elsewhere.
- Reuse opportunity: Yes — reuse `input/init.lua` and `input/config.lua`'s exact structure (native-function-captured-at-load-time fallback, read-only config metatable, eager `setup()` wiring), `finder/ui/input.lua`'s prompt-buffer (`buftype=prompt` + `prompt_setprompt` + debounced `TextChangedI`/`TextChanged`) search-box pattern, and `finder/ui/list.lua`'s virtualized-viewport rendering plus its inline-virt_text-extmark technique for the current-row marker (`sel_prefix`/pad-for-other-rows) and its `right_align` virt_text technique for secondary row text (already proven in `finder/format.lua`'s `M.help_tags`).

### Built-in / Existing Lib Check
- Checked: `vim.ui.select` (native default implementation), `nvim_open_win`'s `footer`/`footer_pos` fields, `beast.libs.view` (`View`, `View.buf.new`, `View.win.wo`, `View.win.is_normal`), `beast.util.colors` (`Util.colors.build`/`lighten`/`blend`), `beast.libs.input`, `beast.libs.confirm`, `beast.libs.finder`.
- Found: Confirmed live in this repo's Neovim (`has("nvim-0.10")` → true; a floating window opened with `footer="test", footer_pos="left"` succeeds) — Neovim's native floating-window `footer`/`footer_pos` config renders text on the bottom border exactly like `title`/`title_pos` renders on the top border. This directly covers the PM spec's footer-hint-row requirement without any new window or virt_lines machinery. `View`/`Util.colors` cover all window/buffer/highlight primitives needed (see the shared-building-blocks report below); no gaps.
- Decision: **Use** the native `footer`/`footer_pos` option for the hint row (no new UI element needed) + **Reuse** `View`, `Util.colors`, and the `input`/`confirm`/`finder` structural patterns for everything else + **Build** only the genuinely new pieces: the lib's `run()`/monkey-patch entry point (contract differs from `input`/`confirm`), the plain substring filter (`finder/matcher.lua` is fuzzy-scoring, overkill per the PM spec's explicit "no fuzzy scoring" decision), and the simplified (no-preview, no-fuzzy) list renderer.

**Shared building blocks confirmed reusable** (from a dedicated deep-dive):
- `View(buf, win)` / `View:extend(init)` (`lua/beast/libs/view/init.lua`) — OOP wrapper for window/buffer pairs; `confirm/ui.lua`'s `MainView = View:extend(...)` pattern (main view holding a nested backdrop `View` instance) is the direct template for `select`'s multi-window (backdrop + input + list) dialog.
- `View.buf.new(filetype)` (`lua/beast/libs/view/buf.lua`) — scratch buffer creation (`"beast-select"`, `"beast-select-backdrop"` filetypes).
- `View.win.wo(win, key, val)` (`lua/beast/libs/view/win.lua`) — version-safe window-local option setter, used for `winhighlight`.
- `Util.colors.build("BeastSelect", {...})` / `Util.colors.lighten` / `Util.colors.blend` (`lua/beast/util/colors.lua`) — highlight-group construction, following the exact convention in `input/highlights.lua`/`confirm/highlights.lua`/`finder/highlights.lua`.
- `lua/beast/hl_reload.lua`'s `M.highlight_modules` registry and `require("beast").apply_highlights(...)` first-load hook — same wiring `confirm`/`input`/`finder` already use.

---

# Architecture Changes

- `lua/beast/libs/select/config.lua` (new) — `disabled` flag + `ui.backdrop` blend amount, mirrors `confirm/config.lua`'s read-only metatable pattern.
- `lua/beast/libs/select/highlights.lua` (new) — `BeastSelect*` highlight groups, mirrors `input/highlights.lua`/`finder/highlights.lua`.
- `lua/beast/libs/select/filter.lua` (new) — pure `M.matches(text, query)` substring predicate (case-folded, literal/plain find — no fuzzy scoring, per the PM spec's explicit decision).
- `lua/beast/libs/select/list.lua` (new) — virtualized list window: create/render/move/selected, current-row bullet marker (inline virt_text + pad technique from `finder/ui/list.lua`), optional right-aligned dim tag per row (Phase 2), empty-state message when filtered to zero items.
- `lua/beast/libs/select/ui.lua` (new) — dialog orchestration: backdrop window, input window (prompt buffer + debounced filter wiring, stitched border sharing the top edge), list window (stitched border sharing the bottom edge + native `footer`/`footer_pos` hint row), keymaps, `open()`/`close()`.
- `lua/beast/libs/select/init.lua` (new) — `run(items, opts, on_choice)` matching the native `vim.ui.select` contract, headless fallback (native function captured at module load, same technique as `input/init.lua`), `setup()`.
- `lua/beast/libs/select/health.lua` (new) — health checks mirroring `confirm/health.lua` (version check, module-loaded check, highlight-group presence, API-contract sanity).
- `lua/beast/init.lua` (modified) — add an eager `require("beast.libs.select").setup()` call next to the existing `require("beast.libs.input").setup()` line, with the same "must be eager, nothing requires this directly" comment.
- `lua/beast/hl_reload.lua` (modified) — add `"beast.libs.select.highlights"` to `M.highlight_modules`.
- `tests/test-select-filter.lua` (new) — headless tests for `filter.lua`'s `M.matches`, following `tests/test-input-position.lua`'s harness (manual `assert_eq` counter, `os.exit(failed == 0 and 0 or 1)`).

## Implementation Phases

## Phase 1: Core lib — flat picker wired into vim.ui.select
1. **Config module** (File: `lua/beast/libs/select/config.lua`)
   - Action: Create `disabled` and `ui = { backdrop = 60 }` fields with the same read-only metatable + `setup(opts)` merge pattern as `lua/beast/libs/confirm/config.lua`.
   - Why: Consistent headless/testing escape hatch and backdrop-dimming knob, matching `confirm`'s config shape.
   - Depends on: None
   - Risk: Low

2. **Highlights module** (File: `lua/beast/libs/select/highlights.lua`)
   - Action: Define `BeastSelect{Normal,Border,Backdrop,InputNormal,InputTitle,ListCursorLine,ListBullet,ListEmpty,Footer}` via `Util.colors.build`. Dim/secondary text uses `p.dimmed3` (matching `finder`'s `ListDir`/`Border` convention); the bullet marker uses `p.accent2` (matching `finder`'s `ListSelectionPrefix`); cursor-row background uses `Util.colors.blend(p.dimmed3, 0.3, p.dark1)` (matching `finder`'s `ListCursorLine` formula).
   - Why: Visual consistency with BeastVim's existing floating dialogs, reusing already-established color roles instead of inventing new ones.
   - Depends on: None
   - Risk: Low

3. **Substring filter** (File: `lua/beast/libs/select/filter.lua`)
   - Action: `M.matches(text, query)` — returns true if `query == ""` or `text:lower():find(query:lower(), 1, true)` succeeds (plain/literal find, not a Lua pattern). No class, no state — a pure function, since `select` (unlike `finder`) has no `cwd`/`buf`/live-stream context to carry.
   - Why: Implements the PM spec's explicit "flat list only, simple substring filter" decision without pulling in `finder/matcher.lua`'s fuzzy-scoring machinery.
   - Depends on: None
   - Risk: Low

4. **Headless filter tests** (File: `tests/test-select-filter.lua`, new)
   - Action: Exercise `M.matches` for empty query (always true), case-insensitivity, substring-not-prefix matches, and no-match cases. Follow `tests/test-input-position.lua`'s harness structure exactly (manual `assert_eq` counter, `os.exit`).
   - Why: Pure logic, cheap to verify headlessly without a real UI session.
   - Depends on: Step 3
   - Risk: Low

5. **List rendering** (File: `lua/beast/libs/select/list.lua`)
   - Action: `M.create(win_row, win_col, win_w, win_h, border)` opens the list window (`cursorline=false` — the bullet marker is the selection indicator, not Neovim's own cursorline, matching the PM spec's "bullet in the left margin" rule) with `winhighlight` mapping `Normal:BeastSelectNormal,FloatBorder:BeastSelectBorder,CursorLine:BeastSelectListCursorLine`. `M.render(view, items, format_item)` — virtualizes the viewport (only visible items touch the buffer, per `finder/ui/list.lua`'s `render_visible`), writes rows via one `nvim_buf_set_lines` call, and marks the current row with an inline virt_text extmark in a dedicated namespace (bullet glyph `●` + space; other rows get an equal-width blank pad so label columns stay aligned) — the exact technique `finder/ui/list.lua` uses for its `▌` selection prefix. When `#items == 0`, render a single dim, centered `"No matching items"` line (styled `BeastSelectListEmpty`) instead of leaving the buffer blank — `finder` has no precedent for this, so this is new. `M.move(view, delta)` / `M.set_cursor(view, idx)` / `M.selected(view)` mirror `finder/ui/list.lua`'s cursor-movement API, with cycling at the list boundaries.
   - Why: Implements PM spec STATE 1/2/5 and Scenarios 1, 2, 5 — the core list-with-filtering-and-selection behavior.
   - Depends on: Step 2
   - Risk: Medium (virtualized-viewport + extmark-in-separate-namespace bookkeeping is the trickiest part of the lib)

6. **Dialog orchestration** (File: `lua/beast/libs/select/ui.lua`)
   - Action: `M.open(items, opts, on_choice)` — creates a full-screen backdrop window (`zindex=100`, unfocusable, `winblend=config.ui.backdrop`, matching `confirm/ui.lua`'s backdrop), an input window (`zindex=101`, `buftype=prompt` via `vim.fn.prompt_setprompt`, top rounded border + title = `opts.prompt` or `"Select one of:"` (native default), bottom border stitched flat to seam with the list window — same jigsaw-border technique as `finder/ui/input.lua`/`finder/ui/list.lua`, minus the third preview pane), and a list window (`zindex=101`, blank top border seaming with the input window, rounded bottom/side borders, `footer = "Confirm enter   Cancel esc"`, `footer_pos = "left"` on the list window's `nvim_open_win` config — the native option confirmed working in Research). Wires the input buffer's debounced `TextChangedI`/`TextChanged` autocmd (same `Util.debounce` pattern as `finder/ui/input.lua`) to re-filter `items` via `filter.matches` and re-render the list. Buffer-local keymaps on the input buffer: `<C-j>`/`<Down>` and `<C-k>`/`<Up>` (insert mode) call `list.move`; `<CR>` (insert+normal) reads `list.selected(view)` and calls the caller's confirm path; `<Esc>` (insert+normal) and a `BufLeave` autocmd (once, matching `input/ui.lua`'s auto-cancel-on-focus-loss) call the caller's cancel path. `M.close(view)` closes all three windows.
   - Why: Implements PM spec STATE 1-2 chrome, Scenario 1 (happy path), Scenario 2 (filtering), and Scenario 6 (cancel).
   - Depends on: Steps 2, 3, 5
   - Risk: Medium (multi-window stitched-border layout + keymap wiring is the most involved single piece)

7. **Entry point + monkey-patch** (File: `lua/beast/libs/select/init.lua`)
   - Action: Capture `local native_select = vim.ui.select` at module load time (before `setup()` reassigns it), mirroring `input/init.lua`. `M.run(items, opts, on_choice)`: if `config.disabled` or `not vim.api.nvim_list_uis()[1]` (headless), call `native_select(items, opts, on_choice)`; otherwise normalize `opts` (default `format_item = tostring`, default `prompt = "Select one of:"` matching native behavior) and call `ui.open(items, opts, on_choice)`. `M.setup(opts)`: `require("beast").apply_highlights("beast.libs.select.highlights")`, `config.setup(opts)`, `vim.ui.select = M.run`. `M.meta = { name = "select", description = "Themed floating replacement for vim.ui.select" }`.
   - Why: The actual contract-matching entry point — the piece that makes this a genuine drop-in for every existing `vim.ui.select` caller.
   - Depends on: Step 6
   - Risk: Medium (global monkey-patch correctness; must exactly preserve `on_choice(item, idx)` semantics, including `idx` referring to the *original* `items` array index, not the filtered view's index)

8. **Health checks** (File: `lua/beast/libs/select/health.lua`)
   - Action: Mirror `confirm/health.lua`'s structure — Neovim version check, config-load check, module-loaded/`disabled`-state report, highlight-group presence check for each `BeastSelect*` group, and a note that headless fallback logic exists but can't be exercised live from `:checkhealth`.
   - Why: Matches the established per-lib health-check convention (`confirm` has one; its absence in `input` was flagged as a gap during input's own research) and gives users a diagnostic path if the picker misbehaves.
   - Depends on: Steps 1-7
   - Risk: Low

9. **Wire into startup** (File: `lua/beast/init.lua`, modified)
   - Action: Add `require("beast.libs.select").setup()` as an eager call directly beside the existing `require("beast.libs.input").setup()` line, with a comment mirroring `input`'s: "vim.ui.select replacement — must run eagerly, same rationale as vim.ui.input above."
   - Why: `vim.ui.select` is called by Neovim/LSP/plugin internals, never by BeastVim's own `require(...)` — there's no lazy-load trigger to hang this off of, exactly like `input`.
   - Depends on: Step 7
   - Risk: Low, but adds to the eager startup path — verify with `bench-startup.sh` per `DEVELOPMENT.md`.

10. **Register highlights for reload** (File: `lua/beast/hl_reload.lua`, modified)
    - Action: Add `"beast.libs.select.highlights"` to `M.highlight_modules`, alongside the existing `"beast.libs.confirm.highlights"` / `"beast.libs.input.highlights"` entries.
    - Why: Without this, `select`'s highlights would go stale on `:colorscheme` change — this exact omission was caught by code review during `input`'s own Phase 1 (see `input-init.md`'s "Completed" notes).
    - Depends on: Step 2
    - Risk: Low

## Phase 2: Data-driven tag + custom footer hints (BeastVim-internal extension surface)
1. **Tag rendering** (File: `lua/beast/libs/select/list.lua`, modified)
   - Action: `M.render` accepts an optional `format_tag(item)` function; when it returns a non-nil string for a row, append a `{ text = tag, hl = "BeastSelectListTag", right_align = true }`-shaped entry that's rendered as a `virt_text_pos = "right_align"` extmark (same technique as `finder/ui/list.lua`'s `apply_row_highlights`, already proven for `finder/format.lua`'s `M.help_tags`) — excluded from the literal buffer text so it never affects cursor/column math.
   - Why: Implements PM spec STATE 3 / Scenario 3.
   - Depends on: Phase 1 Step 5
   - Risk: Low (proven technique, just porting it)

2. **Tag in the call contract** (File: `lua/beast/libs/select/init.lua`, modified)
   - Action: Accept an optional `opts.format_tag(item): string|nil` field (a BeastVim-specific extension, undocumented to and unusable by third-party plugins that only know the native contract) and thread it through `ui.open` → `list.render`.
   - Why: Implements the PM spec's Behavior Rule that tags are opt-in and BeastVim-internal-only.
   - Depends on: Phase 2 Step 1
   - Risk: Low

3. **Custom footer hints** (File: `lua/beast/libs/select/ui.lua`, modified)
   - Action: Accept an optional `opts.footer_hints: { key: string, label: string }[]`; build the list window's `footer` string as the default `"Confirm enter   Cancel esc"` plus `"  " .. label .. " " .. key` for each extra hint, set once at `nvim_open_win` time (footer content is static per invocation, not live-updated).
   - Why: Implements PM spec STATE 4 / Scenario 4.
   - Depends on: Phase 1 Step 6
   - Risk: Low (same native `footer` mechanism as Phase 1, just richer content)

---

# Testing Strategy

- Headless tests: `tests/test-select-filter.lua` (new) — run via `nvim --clean --headless -l tests/test-select-filter.lua`.
- Bench: not a hot/looped path; no new `scripts/bench-*.lua` needed. Phase 1 adds an eager `require` to the startup path (like `input`/`confirm`/`notify`), so run `./scripts/bench-startup.sh` before/after per `DEVELOPMENT.md` to confirm no regression.
- Manual: walk through the PM spec's 6 scenarios in a real session (`LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim nvim`):
  1. Trigger an LSP code action on a diagnostic → picker appears centered, first item bulleted, arrow/Enter selects it.
  2. `:lua vim.ui.select({"a","ab","abc","xyz"}, {prompt="Filter test"}, print)` → type `ab`, confirm the list narrows to `ab`/`abc` live.
  3. `:lua vim.ui.select({"main","feature/x"}, {prompt="Branch", format_tag=function(i) return i=="main" and "current" or nil end}, print)` → confirm `main`'s row shows a right-aligned dim `current` tag.
  4. `:lua vim.ui.select({"main"}, {prompt="Branch", footer_hints={{key="ctrl+d", label="Delete"}}}, print)` → confirm the footer shows the extra hint alongside Confirm/Cancel.
  5. Type a query matching nothing → confirm the "No matching items" empty state appears.
  6. Esc from any of the above → confirm `on_choice` receives `nil` (observe via `print`'s output or a wrapping `on_choice` that asserts).

# Success Criteria

- [x] Any plugin calling `vim.ui.select` (LSP code actions, git integrations, etc.) automatically gets the new themed picker with no caller-side code changes.
- [x] Typing in the search field narrows the list live, matching against item labels.
- [x] The highlighted row shows a bullet marker, and pressing Enter returns that item (and its original-array index) to `on_choice`, matching native behavior.
- [x] Items with a caller-supplied tag show it right-aligned in dim text, separate from the label.
- [x] Callers that supply extra footer hints see them alongside the default Confirm/Cancel hints.
- [x] Filtering to zero results shows an empty-state message, not a blank list.
- [x] Esc cancels and returns nil, matching native `vim.ui.select`.
- [x] Visual style (border, colors, title, bullet marker) matches BeastVim's existing confirm dialog, input box, and finder search box.
- [x] `tests/test-select-filter.lua` passes headless.
- [x] `bench-startup.sh` shows no meaningful regression vs. baseline.
- [x] `:checkhealth beast.libs.select` reports no errors.

---

## Completed

**2026-08-09** — Both phases implemented and committed.

- `e9b2176` feat(select): add themed vim.ui.select replacement (Phase 1: core picker) (code review caught a real bug: a stale scroll offset wasn't re-capped after filtering shrank a long list, hiding matches — reproduced live via a scripted wezterm session (30 items, scroll to offset ~6, filter to 3 matches) before and after the fix; also fixed a debounce-timer leak on close and moved the dialog from dead-center to upper-middle positioning to match the PM spec)
- `6718495` feat(select): add data-driven tag and custom footer hints (Phase 2) (format_tag/footer_hints had been implemented a phase early during Phase 1 — reverted out of Phase 1 per code review, then re-added here as originally scoped; second review passed with only a variable-naming nit, fixed)

Verification: `tests/test-select-filter.lua` — 10/10 assertions pass headless. `stylua --check` clean throughout. `:checkhealth beast.libs.select` fully green. `bench-startup.sh` (warm, 10 runs): 29.5ms mean nvim-internal time, 43.4ms wall-clock (hyperfine) — no regression vs. `input`'s own recorded baseline (28.11ms). The interactive UI flow (open/filter/scroll/confirm/cancel/empty-state/tag/footer_hints) isn't headlessly testable — `:startinsert` doesn't take effect when driven synchronously from a headless `-c "lua ..."` script, a Neovim quirk, not a code bug — so it was verified end-to-end via real interactive sessions driven through `wezterm cli` (spawn a pane, send-text keystrokes, get-text to read the rendered screen), including the exact scroll+filter bug repro.
