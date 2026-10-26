---
name: message-ui
description: Enable Neovim 0.12 ui2 (no hit-enter prompts with cmdheight=0) and route errors and warnings such as E486 to Toast through a small per-kind router
generated: 2026-10-26
---

> PM Spec: none (infra change, no standalone PM spec). Motivated by [docs/pm-specs/cross-search-count.md](../pm-specs/cross-search-count.md): with `cmdheight=0`, a failed `/pattern` prints `E486` plus "Press ENTER or type command to continue", and the toast from the search-count lib cannot prevent it.

# Summary
Turn on Neovim's built-in message and cmdline UI (`require("vim._core.ui2").enable`) so no message ever triggers the legacy hit-enter prompt, then add a small router in a new `messages` lib that diverts selected message kinds (errors, warnings, search wrap) to `Toast` instead of the ui2 message window. The search-count lib then drops its own wrap/not-found heuristics and lets the router handle those messages.

---

# Context

## Problem
BeastVim runs with `cmdheight = 0` (`lua/beast/option.lua:70`), so every native message that does not fit the hidden command line becomes a hit-enter prompt. Nothing in the repo intercepts messages (`ui_attach`, `msg_show` and `ext_messages` are unused), so errors like `E486`, warnings like "search hit BOTTOM" and other output interrupt the user. The search-count lib's workaround (clear the command line after the fact) runs too late, because the prompt is already pending.

### Solution
`lua/beast/libs/messages/` enables ui2 once at startup (gated on Neovim 0.12+ and the module being present), with `msg.targets` set so errors and warnings land in the ephemeral message window. A router wraps ui2's `msg_show` handler: for message kinds and patterns listed in config it calls `Toast` and swallows the event; everything else falls through to ui2 unchanged. The cmdline also moves to ui2's cmdline window, which is a visible change the spec covers in the compatibility phase.

---

# Research

## Research

### Repo Search
- Searched for: `ui_attach`, `msg_show`, `ext_messages`, `ui2`, `_core`, `cmdheight`, `shortmess`, `vim.notify`, `hit-enter`, `lua/beast/libs/notify`, `lua/beast/libs/toast`, `lua/beast/libs/input`, `lua/beast/libs/confirm`, `lua/beast/libs/window/config.lua`
- Found:
  - `lua/beast/option.lua:70` `cmdheight = 0`, `:106` `laststatus = 3`, `:132` `shortmess` (`cSs` after the search-count work).
  - No `ui_attach` / `ext_messages` use anywhere. `lua/beast/libs/notify/init.lua` replaces `vim.notify` only; messages printed by Neovim itself are untouched.
  - `Toast(msg, level, opts)` (`lua/beast/libs/toast/init.lua`) is the notice mechanism and a global (`_G.Toast`, set in `lua/beast/init.lua:75`).
  - `input` and `select` libs replace `vim.ui.input`/`vim.ui.select`; `confirm` lib wraps confirmation dialogs. They are eager (`lua/beast/init.lua` "must run eagerly" comments), a precedent for enabling the message UI eagerly.
  - `lua/beast/libs/window/config.lua:17` already excludes `nofile` buftypes from auto-width, which covers the ui2 buffers (`buftype=nofile`, filetypes `cmd`, `msg`, `pager`, `dialog`). `indent` excludes `buftype ~= ""` (`libs/indent/init.lua`).
  - `lua/beast/libs/searchcount/init.lua` currently holds `after_search`, `is_wrap`, the `SEARCH_KEYS`/`CHAR_ARG_KEYS` heuristics and an `echo ''` hack, all there only because messages cannot be intercepted.
- Reuse opportunity: **Yes** - `Toast`, the lib layout (`config.lua` readonly, `health.lua`, `highlights.lua` if needed), `packer`/eager setup pattern in `lua/beast/init.lua`.

### Built-in / Existing Lib Check
- Checked: Neovim 0.12.6 `vim.ui_attach` docs ("experimental", `ext_messages` implies `ext_cmdline`), `:help ui-messages` (message kinds: `emsg`, `wmsg`, `echoerr`, `search_count`, `list_cmd`, `lua_error`, ...), `$VIMRUNTIME/lua/vim/_core/ui2.lua`, `ui2/messages.lua`, `ui2/cmdline.lua`, `:help ui2`, `deprecated.txt` (ui2 replaces hit-enter).
- Found:
  - `require("vim._core.ui2").enable({ msg = { targets = {...}, msg = { timeout } } })` externalizes messages and cmdline, removes the hit-enter prompt (overflow is "collapsed" with a `[+x]` indicator; `g<` opens a pager), and handles dialogs, `showmode`, `showcmd` and `ruler`. `targets` maps a message kind to `cmd`, `msg` or `pager`. It returns without effect when no UI is attached (headless).
  - ui2 dispatches events with `M.msg[event]` looked up at call time (`ui_callback` in `ui2.lua`), so replacing `require("vim._core.ui2.messages").msg_show` intercepts every message without re-implementing the cmdline.
  - There is no public per-message hook or "return true to cancel" for ui2's own handler; a second `ui_attach` namespace would receive events but cannot stop ui2 from also displaying them.
  - Writing our own `ext_messages` + `ext_cmdline` UI (what noice.nvim does) means also rendering the cmdline, wildmenu, dialogs and pager ourselves.
- Decision: **Use** ui2 for everything it already does, **Build** only a thin router around its `msg_show`. Do **not** write a custom cmdline/message UI. Accept that ui2 and its private modules are experimental; mitigate with a version gate, `pcall`, and a health check that reports when routing is inactive.

---

# Open Decisions (need your confirmation before implementation)

1. **Which messages become toasts.** Recommended default: kinds `emsg`, `echoerr`, `lua_error`, `rpc_error` and `wmsg` go to `Toast` (levels error/error/error/error/warn). Informational kinds (`echo`, `echomsg`, `lua_print`, `undo`, `quickfix`, file written) stay in ui2's ephemeral message window (4 s). Long output (`list_cmd`, `:messages`, `verbose`) stays in the ui2 pager. The alternative is "everything to Toast like noice", which makes `:ls`, `:set` and multi-line output awkward.
2. **Search messages.** `search_count` (`[2/3]`) is dropped (the search-count lib already shows the count). `wmsg` "search hit BOTTOM/TOP" becomes the "Search wrapped" toast. `E486` becomes "Pattern not found: <pat>".
3. **Cmdline look.** ui2's cmdline is a window at the bottom (relative to the statusline), not the native cmdline row. It is a visible change for `:` and `/`. Confirm acceptable or whether the cmdline needs themed highlights (`MsgArea`).
4. **Early messages.** ui2 enabled at `beast.setup()` time (before `VimEnter`). Messages emitted earlier still use the legacy path.

---

# Architecture Changes
- New `lua/beast/libs/messages/init.lua` - `setup()`: version/module gate, `ui2.enable(...)`, install router. Owns no state besides the saved original `msg_show`.
- New `lua/beast/libs/messages/config.lua` - readonly config: `ui2` options (`targets`, `msg.timeout`) and `routes` (ordered list of `{ kind, match?, level, title, text? }`; an entry with `drop = true` swallows the message).
- New `lua/beast/libs/messages/router.lua` - pure `resolve(kind, text) -> route|nil` plus the wrapper around `ui2.messages.msg_show` (flatten `content` chunks to text, call `Toast`, return without forwarding).
- New `lua/beast/libs/messages/health.lua` - reports Neovim version, ui2 present, router installed, `cmdheight`.
- Modify `lua/beast/init.lua` - eager `require("beast.libs.messages").setup(cfg.messages or {})` after `toast.setup` (needs `Toast`), near the other eager UI replacements.
- Modify `lua/beast/libs/searchcount/init.lua` - remove `after_search`, `is_wrap`, `SEARCH_KEYS`, `CHAR_ARG_KEYS`, the `on_key` search-key branch and the `echo ''` hack (keep the `Esc`/`CmdlineLeave` statusline redraw).
- Modify `lua/beast/option.lua` - drop the `s` shortmess flag (wrap now arrives as a `wmsg` event); keep `S`.
- Modify `tests/test-searchcount.lua` - remove the `is_wrap` and search-key tests moved to the router tests.
- New `tests/test-messages-router.lua` - pure router tests plus an `--embed` child-process test (see Testing Strategy).
- Update `docs/CODEMAP/` via `/update-codemap`.

## Implementation Phases

## Phase 1: Enable ui2 - no more hit-enter prompts
1. **Lib skeleton + enable** (File: `lua/beast/libs/messages/init.lua`, `config.lua`)
   - Action: `setup(opts)`: return early (and report via health) unless `vim.fn.has("nvim-0.12") == 1` and `pcall(require, "vim._core.ui2")`. Call `ui2.enable({ msg = { targets = { emsg = "msg", wmsg = "msg", echoerr = "msg" }, msg = { timeout = <config> } } })`. Config readonly, same shape as other libs.
   - Why: removes hit-enter for every message, which is the real cause of the E486 prompt.
   - Depends on: None
   - Risk: Medium (experimental API; cmdline changes appearance).
2. **Wire eagerly** (File: `lua/beast/init.lua`)
   - Action: call `messages.setup` right after `toast.setup(...)`.
   - Why: messages emitted during startup should not prompt; `Toast` must exist for Phase 2.
   - Depends on: Step 1
   - Risk: Medium (startup cost; verify with `bench-startup.sh`).
3. **Health** (File: `lua/beast/libs/messages/health.lua`)
   - Action: version, ui2 module present, `vim.o.cmdheight`, whether ui2 windows exist.
   - Why: repo convention; makes a silent version break visible.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: Router - errors and warnings as toasts
1. **Pure resolver** (File: `lua/beast/libs/messages/router.lua`)
   - Action: `resolve(kind, text)` walks `config.routes` in order and returns the first match (`kind` equal, optional Lua pattern on text). Default routes: `emsg|echoerr|lua_error|rpc_error` -> `Toast(text, ERROR)`; `wmsg` -> WARN; `emsg` matching `^E486: Pattern not found: (.*)` -> WARN "Pattern not found: %1" with title "Search"; `wmsg` matching `^search hit (%u+)` -> INFO "Search wrapped" ("Hit BOTTOM, continuing at TOP" / "Hit TOP, continuing at BOTTOM"); `search_count` -> `drop`.
   - Why: all logic that decides routing is pure and unit-testable.
   - Depends on: Phase 1
   - Risk: Low
2. **Wrap ui2's handler** (File: `lua/beast/libs/messages/init.lua`)
   - Action: replace `require("vim._core.ui2.messages").msg_show` with a wrapper: flatten `content` chunks (`chunk[2]`) into one string, call `router.resolve`; on a route call `Toast` (scheduled, since `msg_show` for internal messages runs in api-fast context) and return; otherwise call the saved original. Pass `replace_last`/`id` untouched to the original so progress/replace behavior of ui2 is preserved.
   - Why: only way to divert messages without writing a cmdline UI.
   - Depends on: Step 1
   - Risk: High (private, experimental module; keep the wrapper tiny and guarded with `pcall` so a router bug falls back to the original handler).
3. **Multi-line and spill** (File: `lua/beast/libs/messages/router.lua`)
   - Action: truncate toast text to the first N lines with a `[+x]` hint, mirroring ui2's spill; the full text remains available in `:messages` / `g<`.
   - Why: a stack trace as a toast must not cover the screen.
   - Depends on: Step 2
   - Risk: Low

## Phase 3: Simplify the search-count lib
1. **Remove heuristics** (File: `lua/beast/libs/searchcount/init.lua`, `lua/beast/option.lua`, `tests/test-searchcount.lua`)
   - Action: delete `after_search`, `is_wrap`, the search-key `on_key` branch, `SEARCH_KEYS`, `CHAR_ARG_KEYS`, the `echo ''`; remove `s` from `shortmess`; delete the tests for them. Keep the count, float, statusline component and `Esc`/`CmdlineLeave` redraw.
   - Why: the router now produces the not-found and wrap toasts reliably (also for `fn`, `3n`, macros and `/` search), fixing the known gaps recorded in `cross-search-count.md`.
   - Depends on: Phase 2
   - Risk: Medium (if the router is inactive on an old Neovim, those toasts silently disappear; the native messages come back through `s` removal, which is acceptable fallback behavior).

## Phase 4: Compatibility pass
1. **Special windows and options** (File: libs that special-case filetypes, e.g. `lua/beast/libs/statusline/util.lua` (`IGNORED_FILETYPES`), `lua/beast/libs/statuscolumn`, `lua/beast/libs/indent/config.lua`, `lua/beast/libs/window/config.lua`, `lua/beast/libs/tabline`)
   - Action: add filetypes `cmd`, `msg`, `pager`, `dialog` to the exclusion lists only where a lib misbehaves on those windows (check each; do not touch the ones that already skip `nofile`).
   - Why: ui2 buffers are real floating windows with filetypes, unlike native messages.
   - Depends on: Phase 1
   - Risk: Medium
2. **Theme** (File: `lua/beast/libs/messages/` or `lua/beast/theme/highlights.lua`)
   - Action: define `MsgArea` and message-window highlights from the palette so the cmdline and message window match the theme and reload with the colorscheme. Check the existing `hl_reload.lua` module list convention.
   - Why: otherwise ui2 shows default colors.
   - Depends on: Step 1
   - Risk: Low
3. **Interactions** (manual)
   - Action: verify `confirm`/`input`/`select` libs (ui2 dialog vs their own float), macro recording indicator (statusline `macro` component vs `showmode`), `:messages` and `g<`, the key-hint popup and cheatsheet while the cmdline is open, `laststatus=3` placement.
   - Why: these are the places a global message UI can regress.
   - Depends on: Phases 1-3
   - Risk: Medium

---

# Testing Strategy
- Headless tests:
  - New `tests/test-messages-router.lua` - pure `resolve()` table tests: E486 -> "Pattern not found: zzz"; `search hit BOTTOM, continuing at TOP` -> "Search wrapped"; `search_count` -> drop; unknown kind -> nil; a user-supplied route overrides the default.
  - Same file, an embedded child: `vim.fn.jobstart({ "nvim", "--embed", "--clean", "-u", "NONE" }, { rpc = true })`, `nvim_ui_attach(100, 30, {})`, enable the lib, `nvim_input("/zzz<CR>")` (and an `n` wrap), then read recorded `Toast` calls and assert no `hit-enter` state via `nvim_get_mode().blocking == false`. (Plain `--headless` has no UI, so ui2 does nothing there.)
  - Re-run `tests/test-searchcount.lua`.
- Bench: `./scripts/bench-startup.sh` (eager enable must not move startup beyond noise); `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all` (cmdline/message redraw path now Lua).
- Manual (scenarios from `cross-search-count.md` plus new):
  1. `/zzz` + Enter: warn toast "Pattern not found: zzz", no `E486` line, no "Press ENTER".
  2. `n` past the last match: "Search wrapped" toast; also via `fn`/`3n`/macros no false toasts.
  3. `:foo` (unknown command): error toast, no prompt.
  4. `:lua error("x")`: error toast.
  5. `:echo "hi"` and `:w`: ephemeral message window, auto-hides.
  6. `:ls`, `:messages`, `:set`: pager/collapsed with `[+x]`, `g<` opens the pager.
  7. Open `/` and `:` cmdlines: appearance, wildmenu, history, `q:`.
  8. Recording a macro (`qa`): indicator still shown.
  9. Confirm dialogs (`:q` with modified buffer) and `vim.ui.input`.
  10. Switch colorscheme: message/cmdline colors follow the theme.

# Success Criteria
- [x] A failed search shows a toast and never the "Press ENTER" prompt.
- [x] Wrap-around shows the "Search wrapped" toast for `n`, `N`, `*`, `#`, counted and macro-driven jumps, without false positives in insert mode.
- [x] Errors and warnings (`emsg`, `echoerr`, `lua_error`, `wmsg`) appear as toasts; informational messages appear in ui2's message window; long output in the pager.
- [x] No hit-enter prompt anywhere with `cmdheight=0`.
- [ ] The cmdline, wildmenu, dialogs, macro indicator, `confirm`/`input`/`select` libs and the key hint popup still work. (Not verified visually; needs a manual pass.)
- [x] `search-count` lib no longer contains search-key heuristics; its tests pass.
- [x] Startup and UX benches show no regression; `:checkhealth beast.libs.messages` is green on 0.12 and warns (not errors) on older versions.
- [x] Router tests and the embedded test pass; lint and format clean.

---

## Completed

2026-10-26. Phases 1-3 done (ui2 enabled, router, search-count cleanup); Phase 4 partly: ui2 window options and theme checked, interactions left for a manual pass.

- `05342e9` feat(messages): enable ui2 and route errors and warnings to toasts
- `eab8a29` refactor(searchcount): drop search-key heuristics, messages router handles toasts
- `b923bdf` fix(messages): a failed search that wraps shows only the not-found toast
- `d8608bb` feat(messages): theme the ui2 message and cmdline windows
- `ca33021` style(tests): apply stylua formatting
- `8a5fb3d` test(lsp): stub Util.colors.lighten used by lsp highlights

Deviations from this spec:
- Phases 1 and 2 landed in one commit (the router was small).
- A failed search that wraps emits "search hit BOTTOM" before E486, so routes gained `cancels`: the not-found toast supersedes a pending "Search wrapped" toast.
- Phase 4 found no filetype exclusions needed: ui2 windows have empty `statuscolumn`/`winbar`, no `number`, and `nofile` buftype. Only `MsgArea` needed a highlight (`link = Normal`).
- Informational messages (`echo`, `:ls`, written) stay in ui2 (msg window / pager) as recommended in the open decisions.

Verification: `tests/test-messages-router.lua` 19/19 (router rules + an embedded nvim with a UI: no hit-enter, E486 and `:nosuchcmd` become toasts, wrap-then-fail shows one toast); `tests/test-searchcount.lua` 12/12; `bench-startup.sh` mean 38ms (headless: ui2 is a no-op without a UI); `bench-ux.sh keypress` PASS with ui2 on (p50 0.48ms, p99 0.98ms); real-config embedded run: not-found, wrap, unknown command and `:lua error()` all toast, no blocking prompt.
Not verified: how the ui2 cmdline and message window look in a real terminal; `confirm`/`input`/`select` libs, macro indicator and key hint popup with the new cmdline; Neovim startup messages before `messages.setup`.
