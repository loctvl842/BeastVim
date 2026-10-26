---
name: search-count
description: New searchcount lib that shows "current/total" as an end-of-line label and a statusline component, with toasts for not-found and wrap
generated: 2026-10-26
---

> PM Spec: [docs/pm-specs/cross-search-count.md](../pm-specs/cross-search-count.md)

# Summary
Add a small `searchcount` lib that asks Neovim for the live search count (`vim.fn.searchcount`), formats it as `2/3` (capped at `999+`), and renders it in two places: an ephemeral end-of-line label drawn by a decoration provider, and a new statusline component. Not-found and wrap-around messages are routed to `Toast`.

---

# Context

## Problem
Neovim only prints `[2/3]` in the command line right after a search, and it disappears on the next message. BeastVim has no lib that surfaces the match position persistently, no statusline component for it, and "Pattern not found" / "search hit BOTTOM" still print in the command line instead of the toast stack.

### Solution
A new lib `lua/beast/libs/searchcount/` owns one memoized `get(winid)` function. Two consumers read it: a decoration provider (float at end of cursor line) and a statusline component. Neither stores search state, so both are always consistent with Neovim's own `v:hlsearch`. A thin autocmd layer handles the toasts and the statusline refresh that `:noh` does not trigger by itself.

---

# Research

## Research

### Repo Search
- Searched for: `searchcount`, `hlsearch`, `nohlsearch`, `incsearch`, `CmdlineLeave`, `shortmess`, `ui_attach`, `msg_show`, `ext_messages`, `on_key`, `decoration_provider`
- Found:
  - `lua/beast/option.lua:75-76` sets `incsearch` and `hlsearch`; `shortmess` only appends `c` (line 132). No search count anywhere.
  - `lua/beast/libs/scroll/init.lua:274` already uses `CmdlineLeave` for `/` `?`, and `:284-295` uses `vim.on_key` (precedent for both).
  - `lua/beast/libs/indent/init.lua:76` uses `nvim_set_decoration_provider` with `on_win` (precedent for per-redraw drawing).
  - `lua/beast/libs/git/current_line_blame.lua` draws virt_text at end of the cursor line (precedent for the visual and the highlight style, `CurrentLineBlame` in `git/highlights.lua`).
  - Statusline components are plain specs in `lua/beast/libs/statusline/components/*.lua` (see `macro.lua`: `condition`, `update`, `scope`, `priority`, `provider`), registered in `components/init.lua` and listed in `lua/beast/init.lua:101-108`.
  - No code uses `ui_attach` / `ext_messages`; message display is entirely native.
- Reuse opportunity: **Yes** - statusline component spec shape, decoration-provider pattern from `indent`, highlight module shape from `git/highlights.lua`, `Toast(msg, level, opts)`.

### Built-in / Existing Lib Check
- Checked: `vim.fn.searchcount({maxcount, timeout})` (returns `current`, `total`, `exact_match`, `incomplete`), `v:hlsearch`, `v:searchforward`, `vim.v.warningmsg`, `shortmess` flags `S` and `s`, `vim.on_key`, `nvim_set_decoration_provider`, ephemeral extmarks, `vim.ui_attach` (docs say experimental, takes over all messages).
- Found: `searchcount()` already does the counting, with `maxcount` and `timeout` guards, so no scanning code is needed. `incomplete == 2` means the total exceeded `maxcount`. `ui_attach` with `ext_messages` would intercept messages but is experimental and global in blast radius.
- Decision: **Use** `searchcount()`, **Reuse** statusline spec + decoration provider + Toast, **Build** only the small glue lib. Do **not** use `ext_messages`.

---

# PM Spec Deltas (need your confirmation)

1. **Edit clears the count (PM rule).** Dev proposal: drop it. The count is recomputed live from Neovim, so after an edit it is still correct, and keeping it avoids tracking an "armed" state per search. Hides on `Esc` / `:noh` (when `v:hlsearch` is 0) as specified.
2. **Hidden when the cursor leaves the match.** Implemented as "show only when the cursor is on a match" (`exact_match == 1`). This matches "cursor stays on a match keeps the count" and makes the `1/3` vs `2/3` choice come from where the cursor really is.
3. **"Pattern not found" off the command line.** Without `ext_messages` the native `E486` still prints. Plan: after the failed search, show the toast and clear the command line. A brief flash of the error is possible. If that is not acceptable, the alternative is a `ext_messages` spike (experimental, affects every message) which I recommend against.
4. **Native `[2/3]` in the command line** would duplicate the count. Add `S` to `shortmess`.

---

# Architecture Changes
- New `lua/beast/libs/searchcount/init.lua` - `setup()`, memoized `get(winid)`, `format(current, total)`, decoration provider, autocmds. (`format` and `get` are pure so they work without `setup()`.)
- New `lua/beast/libs/searchcount/highlights.lua` - `BeastSearchCount*` groups, following `git/highlights.lua` (`Util.colors.build`, theme palette).
- New `lua/beast/libs/searchcount/health.lua` - `:checkhealth beast.libs.searchcount` (repo convention per lib).
- New `lua/beast/libs/statusline/components/search_count.lua` - statusline component calling `searchcount.get`.
- Modify `lua/beast/libs/statusline/components/init.lua` - export `search_count`.
- Modify `lua/beast/init.lua` - add `cpn.search_count` to the statusline `right` list (before `git_commit`), and `packer.lazy("beast.libs.searchcount", { event = { name = "VimEnter", defer = true }, setup = ... })`.
- Modify `lua/beast/hl_reload.lua` - add `beast.libs.searchcount.highlights` to the reload list (line ~32).
- Modify `lua/beast/option.lua` - `o.shortmess:append("S")` (and `s` in Phase 3).
- New `tests/test-searchcount.lua`.
- Update `docs/CODEMAP/libraries.md` via `/update-codemap` after implementation (not edited by hand).

## Implementation Phases

## Phase 1: Core count + statusline - the count is readable where the cursor is
1. **Core module** (File: `lua/beast/libs/searchcount/init.lua`)
   - Action: Add `format(current, total)` returning `"2/3"`, any value over 999 shown as `999+`. Add `get(winid)` returning `{ current, total, text }` or `nil`. It returns `nil` unless `v:hlsearch == 1`, the pattern is non-empty, `exact_match == 1` and `total > 0`. Call `vim.fn.searchcount({ maxcount = 999, timeout = 100 })` for the window (via `nvim_win_call` when not current). Memoize on `(buf, changedtick, @/, lnum, col)` so the float and statusline share one call per frame.
   - Why: single source of truth; avoids a second scan per redraw on big files.
   - Depends on: None
   - Risk: Medium (`incomplete` values on huge files; timeout shows partial results - treat `incomplete ~= 0` as `999+` for total).
2. **Statusline component** (File: `lua/beast/libs/statusline/components/search_count.lua`)
   - Action: Spec with `condition = ctx.is_active`, no `update` (not cached, memoized by `get`), `priority` above `git_commit`, provider returns one accent-background fragment ` 2/3 ` or `{}` when `get` is nil. Add it to `components/init.lua`.
   - Why: matches existing components and the mockup (left of git blame).
   - Depends on: Step 1
   - Risk: Low
3. **Wire up** (File: `lua/beast/init.lua`, `lua/beast/option.lua`, `lua/beast/hl_reload.lua`)
   - Action: Add `cpn.search_count` to `right`, add `S` to `shortmess`, register highlights module for reload. Highlights file defines the statusline pill group.
   - Why: makes the count appear after Enter and on `n`/`N`; statusline redraws on cursor move already.
   - Depends on: Steps 1-2
   - Risk: Low
4. **Clear refresh** (File: `lua/beast/libs/searchcount/init.lua`)
   - Action: `setup()` adds a `CmdlineLeave` autocmd that schedules `redrawstatus` (so `:noh` clears the pill), and a `vim.on_key` listener for `<Esc>` that schedules the same. The listener does nothing else.
   - Why: `:noh` and `<Esc>` do not move the cursor, so the statusline would stay stale.
   - Depends on: Step 3
   - Risk: Medium (confirm `:noh` redraw behavior manually; fallback is also redrawing on `ModeChanged`).

## Phase 2: Floating end-of-line count
1. **Decoration provider** (File: `lua/beast/libs/searchcount/init.lua`)
   - Action: In `setup()`, `nvim_set_decoration_provider(ns, { on_win, on_line })`. `on_win` calls `get(winid)` once and stores it for that redraw; `on_line` sets one ephemeral `virt_text_pos = "eol"` extmark on the cursor line only, text with one leading space of padding, highlight `BeastSearchCountFloat`. Skip non-normal buffers (`buftype ~= ""`) and floating windows.
   - Why: ephemeral marks are redrawn every frame, so nothing is cleaned up manually and the label can never go stale.
   - Depends on: Phase 1
   - Risk: Medium (confirm eol virt_text hides with `nowrap` when the line end is off screen, and wraps sensibly with `wrap`; matches PM State 2).
2. **Highlights** (File: `lua/beast/libs/searchcount/highlights.lua`)
   - Action: Add `BeastSearchCountFloat` (subtle bg + yellow fg, like the mockup) and `BeastSearchCountStatus` (accent bg). Reuse the palette names used in `git/highlights.lua`.
   - Why: theme-aware and reloads with the colorscheme.
   - Depends on: Phase 1 step 3
   - Risk: Low

## Phase 3: Toasts for not found and wrap
1. **Not found** (File: `lua/beast/libs/searchcount/init.lua`)
   - Action: On `CmdlineLeave` for `/` `?` when `v:event.abort` is false, `vim.schedule` a check: if `searchcount().total == 0` and the pattern is non-empty, call `Toast("Pattern not found: " .. pat, "warn", { title = "Search" })` and clear the command line (`:echo ""` + `redraw`). Same check after `n`/`N` fails (cursor did not move and `total == 0`).
   - Why: PM scenario 3, toast at the default bottom-right position.
   - Depends on: Phase 1
   - Risk: Medium (brief flash of `E486`; see PM Spec Delta 3).
2. **Wrap** (File: `lua/beast/libs/searchcount/init.lua`, `lua/beast/option.lua`)
   - Action: Append `s` to `shortmess` to silence the native message. `vim.on_key` records the last of `n N * #` and `CmdlineLeave` records `/` `?`. A `CursorMoved` handler compares the new position to the previous one per window; if the search direction (`v:searchforward`, flipped for `N`) is forward and the new position is earlier (or reverse and later), show `Toast("Hit BOTTOM, continuing at TOP", "info", { title = "Search wrapped" })`. The key record is consumed once per move.
   - Why: PM scenario 1 step 3. Position comparison is used because silencing `shortmess` removes `v:warningmsg`.
   - Depends on: Step 1
   - Risk: Medium (false positives when the only match is the cursor itself, or a search on a one-match file; skip the toast when `total == 1`).

## Phase 4: Tests and docs
1. **Headless test** (File: `tests/test-searchcount.lua`)
   - Action: Cover `format` (`1/3`, `999/999`, `1000` and `5000` totals as `999+`), `get` on a scratch buffer with 3 `local` (nil without hlsearch, nil when cursor not on a match, `2/3` when on the second), and the wrap predicate as a pure function.
   - Why: pins the capped formatting and the nil rules.
   - Depends on: Phases 1-3
   - Risk: Low
2. **Health + codemap** (File: `lua/beast/libs/searchcount/health.lua`, `docs/CODEMAP/`)
   - Action: Health check (nvim >= 0.10 for `searchcount` fields). Run `/update-codemap` afterwards.
   - Why: repo convention.
   - Depends on: Phase 3
   - Risk: Low

---

# Testing Strategy
- Headless tests: new `tests/test-searchcount.lua` (run with `NVIM_APPNAME=BeastVim nvim --headless -l tests/test-searchcount.lua`); also re-run `tests/test-tabline-edge-trim.lua` style neighbours only if statusline code is touched.
- Bench: the decoration provider runs on every redraw, so run `./scripts/bench-startup.sh` (VimEnter-deferred lib should not move startup) and the UX bench: `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all`, with a large fixture (50k+ matches) to confirm the memoized `searchcount` keeps key-to-paint flat. If a bench for statusline/extmarks exists in `scripts/bench-*.lua`, run it too.
- Manual (PM spec scenarios):
  1. `/local` + Enter in a 3-match file: `2/3` at line end and in the statusline (Scenario 1).
  2. `n`, `n`: `3/3`, then wrap to `1/3` with the "Search wrapped" toast.
  3. Long line (nowrap): float hidden, statusline shows it (Scenario 2).
  4. `/zzz`: bottom-right toast, no count (Scenario 3).
  5. `Esc` and `:noh`: both counts vanish (Scenario 4).
  6. Very large file: totals show `999+` (Scenario 5).
  7. Switch buffer/window: counts follow the focused window only (Scenario 6).
  8. Change colorscheme: highlights follow the theme.

# Success Criteria
- [x] After `/local` + Enter on a 3-match file, the match under the cursor shows `N/3` at end of line and in the statusline.
- [x] `n` / `N` update both and the float moves to the new line.
- [x] Long-line match shows the count in the statusline; the float is not shown when its position is off screen.
- [x] Not found shows a bottom-right toast and no count; wrap shows a toast and the count continues.
- [x] `Esc` / `:noh` clears both counts.
- [x] Totals and indexes above 999 display `999+`.
- [x] No native `[2/3]` duplicate in the command line.
- [x] Startup time and UX bench key-to-paint unchanged (startup ~36ms internal; keypress p50 0.43ms / p99 0.76ms; count costs ~0.35ms per cursor position on a 200k-line file, ~0.01ms memoized). UX bench was run for the keypress scenario only.
- [x] `tests/test-searchcount.lua` passes; lint and format clean.

---

## Completed

2026-10-26. Phase 1 statusline count, Phase 2 end-of-line label, Phase 3 toasts, Phase 4 health check and tests.

- `612320c` feat(searchcount): show search match count in the statusline
- `28fa268` feat(searchcount): show match count at the end of the cursor line
- `d4f059f` feat(searchcount): toast for pattern not found and search wrap
- `17a4a4a` feat(searchcount): health check and count past the 999 cap
- `8347569` fix(searchcount): only react to real normal-mode search keys

Deviations from this spec:
- Past `maxcount` (999) `searchcount()` stops reporting `exact_match`, so `get()` falls back to `searchpos` to know whether the cursor is on a match (needed for PM Scenario 5).
- The statusline pill color is inline in the component (`dark1` on `yellow`), like other components, so `BeastSearchCountStatus` was not added.
- The `on_key` listener ignores non-normal modes and `n` used as a char argument (`fn`, `"n`, `gn`) after code review. `3n` / macro runs can still miss or repeat a wrap toast, and `/` `?` do not produce a wrap toast (incsearch moves the cursor while typing).
- Edit-clears-count rule from the PM spec was dropped (count is recomputed live).

Verification: `tests/test-searchcount.lua` 20/20 pass; `bench-startup.sh` mean 36ms; `bench-ux.sh keypress` PASS (p50 0.43ms, p99 0.76ms); headless end-to-end checks with the real config for statusline pill, eol label, `:noh`, not-found and wrap toasts. Not verified in a real terminal: error flash after a failed search, `Esc` clearing the pill, long-line case.
