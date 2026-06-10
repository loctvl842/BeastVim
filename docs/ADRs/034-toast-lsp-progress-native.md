# ADR-034: Native LSP Progress in Toast (`fidget.nvim` / `noice.nvim` Rejected)

**Status:** Accepted

**Date:** 2026-06-10

**Evidence:** Dev spec `docs/dev-specs/toast-lsp-progress.md` (Phase 2); commit `21b784a` (Phase 2 — adapter + config + codemap); files: `lua/beast/libs/toast/progress.lua` (new, ~220 LOC), `lua/beast/libs/toast/config.lua` (progress defaults); related: ADR-009 (native statusline), ADR-018 (native scroll), ADR-022 (native git), ADR-025 (native key popup), ADR-029 (native LSP infra), ADR-032 (native autopairs), ADR-033 (toast records as handles).

## Context

BeastVim has no LSP progress UI. With native LSP infra now in place (ADR-029) and language servers attaching on startup (`lua_ls`, etc.), the long indexing pass at first open is invisible — users wonder if Neovim hung. We needed live progress feedback.

The reference implementation we studied was `noice.nvim/lua/noice/lsp/progress.lua` (114 LOC): one entry per `client_id.token`, throttled redraw via `Util.interval` at 10 Hz, deep-merge of `params.value` into a cached message, two-extmark overlay bar with text right-aligned inside, defer `close` 100ms after `kind == "end"`.

Phase 1 of the dev spec (ADR-033) had already added the generic `toast.update(record)` / `toast.dismiss_id(id)` API the adapter would need.

## Decision

Build `lua/beast/libs/toast/progress.lua` as a thin adapter on top of the existing toast lib:

- **Hook**: native `LspProgress` autocmd (Neovim ≥ 0.10) only — no `vim.lsp.handlers["$/progress"]` fallback. AGENTS.md requires ≥ 0.11.
- **State**: module-local `tokens = {}` keyed by `client_id .. "." .. token`. One toast per token (returned `Record` cached in the entry).
- **Throttle**: a single `vim.uv.new_timer()` ticking at `config.progress.throttle` ms (default 100 = 10 Hz). Starts on first event via idempotent `ensure_timer()`, stops in `tick()` when `tokens` is empty (mirrors noice's `enabled` predicate, no per-tick allocation).
- **Render**: single-line message string (no overlay extmarks):
  - Active w/ percentage: `Indexing  ⠹  [████████░░░░░░░░░░░░] 42%  scanning workspace`
  - Active w/o percentage: `Indexing  ⠹  scanning`
  - Done: `Indexing  ✔  done`

  Client name renders separately as the toast's `title` field.
- **Bar**: unicode blocks `█`/`░`, width 20. No extmark overlay — `ui.render` already paints a single text line, simpler to bake the bar into the message.
- **Spinner**: time-derived (`vim.uv.hrtime()` mod `#frames * spinner_interval`). No per-entry frame counter.
- **Lifecycle edges**:
  - Same-token reuse during `done_linger`: deferred dismiss gated on `cur.kind == "end"` AND `cur.record.id == stale_id` — if a fresh `begin` arrives for the same token id within the linger window, the new toast survives.
  - Fast-event / `vim_starting`: autocmd callback wraps `on_event` in `vim.schedule` when needed, so toast() never fails to return a record.
  - Dead client: `tick()` checks `vim.lsp.get_client_by_id` each frame and drops orphan tokens.
- **Opt-in**: gated on `config.progress.enabled` (default `true`) inside `toast.setup`. When disabled, no autocmd, no timer.

## Alternatives Considered

1. **`fidget.nvim`.** The widely-used dedicated LSP-progress plugin. Rejected — adds an external dependency for what is ~220 LOC of native code; its UI model (multiple per-task floats, custom history) is heavier than the single-line toast we want; styling diverges from BeastVim's palette/highlight contract (ADR-026).
2. **`noice.nvim`.** Excellent reference implementation but does far more than progress (cmdline, messages, popupmenu, signature). Rejected for the same reason every "native X" ADR rejected its plugin counterpart — we'd pay for an entire message router to use 114 lines of progress code.
3. **Add progress directly into the `notify` lib.** `notify` is the persistent log (history-oriented); progress is transient and overwrites itself. Mixing would either pollute history with 100 frames per indexing pass or require dedup logic the toast model already provides via `update(record)`.
4. **Two-extmark overlay bar (noice's approach).** Render an empty 20-char span, paint `hl_group_done` on the left N cells and `hl_group` on the rest, overlay text on top. Rejected — `toast/ui.lua` paints exactly one text line; adding extmark overlay would be a layout regression. Unicode blocks render perfectly in any font on the project's target terminals and need zero highlight wiring.
5. **One composite toast for all in-flight tokens.** E.g. `lua_ls: 3 tasks` with a stacked bar. Rejected for v1 — predictability matters more (one toast = one task), and the existing `stack.reflow` already handles multiple concurrent toasts cleanly.
6. **Per-token spinner state.** Rejected — adds a counter to every entry and a "which-frame-am-I-on" computation. Time-derived (`hrtime / interval mod n`) is stateless and visually identical at 10 Hz.

## Rationale

1. **The slice is small.** ~220 LOC including luadoc, banners, and the test smoke. Below the threshold where pulling a plugin pays off (precedent: ADRs 009, 018, 022, 025, 029, 032).
2. **Leverages Phase 1 primitives.** `toast.update` / `toast.dismiss_id` (ADR-033) do the heavy lifting; the adapter is mostly event-merge logic and the format string.
3. **One responsibility per file.** `progress.lua` only knows about LSP events and toast records — no float code, no highlight code, no animation code. If we later add e.g. shell-command progress, it gets its own ~80-line adapter against the same toast API.
4. **Throttle correctness matters.** The dev spec's "≥ 10 Hz cap" guarantee is enforced by tracking `timer_running` explicitly so re-arming the timer on every event no longer resets the throttle window (fixed during tec-review).
5. **No new plugin entry in `lua/beast/plugins/init.lua`.** Zero dependency footprint.

## Consequences

**Positive:**
- Live progress feedback for any LSP that emits `$/progress` — `lua_ls`, `pyright`, `rust-analyzer`, `tsserver`, etc. — with zero per-server configuration.
- Throttled to 10 Hz, idle timer stops, dead-client cleanup — no background cost when no LSP is busy.
- Matches BeastVim's "native over vendored" trajectory; consistent with the existing notify/toast split.
- Codemap stays compact (one new row).

**Negative / Tradeoffs:**
- Custom format means we don't get noice's two-extmark bar look. The unicode-block bar reads fine in any terminal and matches the toast's single-line aesthetic, but it is *slightly* less polished than the overlay approach.
- Multiple concurrent indexes (3 LSPs all starting at once) produce 3 stacked toasts. Acceptable — single-line, takes 3 rows max. If it becomes a problem, a `progress.max_visible` follow-up can cap it.
- The adapter holds a forward-declared `ensure_timer` local — a small style wart but the cleanest way to express the `on_event → ensure_timer → tick` cycle in one file without splitting helpers across modules.

## Follow-ups (Not in Scope)

- `:checkhealth beast.libs.toast` could surface progress-adapter state (active tokens, timer status). Not required for v1.
- Per-server filtering (e.g. ignore progress from a chatty linter) would live as a `progress.filter = function(client, value): boolean` config knob if desired.
- Cancellation UI (`$/cancelRequest`) is out of scope — read-only display only.
