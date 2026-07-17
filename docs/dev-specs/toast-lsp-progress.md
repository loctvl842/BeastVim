# Dev Spec: Toast LSP Progress

> **Status:** Implemented (2026-06-10). See ADR-033 (`update`/`dismiss_id` API) and ADR-034 (native LSP progress adapter).
>
> Phase 1 — commit `96c9d5e` — generic toast `update(record)` + `dismiss_id(id)` + width-aware `ui.render`.
> Phase 2 — commit `21b784a` — `progress.lua` adapter, config block, codemap.

## Summary

Add live LSP progress notifications to the `toast` library, modeled on
`noice.nvim/lua/noice/lsp/progress.lua` but rendered as a single-line toast with
a unicode block bar (`[████████░░░░░░░░░░░░] 42%`). Progress events from
`vim.lsp.handlers["$/progress"]` are coalesced per `client_id + token` into a
sticky toast (`timeout = false`) that updates in place via a 100 ms throttled
timer, then auto-dismisses ~1 s after `kind == "end"`.

Implementation lives in a new `lua/beast/libs/toast/progress.lua` adapter, plus
two small generic additions to the toast core (`toast.update(record)` and
`toast.dismiss(id)`) so the adapter stays loosely coupled — no LSP knowledge
leaks into `init.lua`/`stack.lua`/`ui.lua`.

**Public API:**

```lua
-- Opt-in from beast.libs.lsp.setup() or user config
require("beast.libs.toast").setup({
    progress = {
        enabled = true,
        throttle = 100,        -- ms between in-place rerenders
        done_linger = 1000,    -- ms to keep the ✔ frame on screen
        bar_width = 20,
        spinner = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" },
        spinner_interval = 100, -- ms per frame
    },
})
```

## Requirements

### Functional

- Subscribe to `LspProgress` autocmd (Neovim 0.10+; project requires ≥ 0.11
  per `AGENTS.md`) — no pre-0.10 fallback.
- Coalesce events by `client_id .. "." .. token`; one toast per token.
- First `begin` event creates a sticky toast (`timeout = false`) with the LSP
  client name as `title` and an `INFO` level.
- `report` events update the same toast in place (message, percentage, spinner
  frame) without re-creating the window or re-running fade-in.
- `end` event clamps percentage to 100, renders a final `✔ title` frame, then
  dismisses the toast after `done_linger` ms.
- Rendered line shape (single line, no overlay extmarks):
  - With percentage: ` <client>  <title>  ⠹  [████████░░░░░░░░░░░░] 42%  <message>`
  - Without percentage: ` <client>  <title>  ⠹  <message>`
  - Done: ` <client>  <title>  ✔  done`
- Spinner frame derived from `vim.uv.hrtime()` modulo `#frames * interval` — no
  per-toast spinner state.
- Throttled rerender loop runs only while at least one token is active; idle
  timer is stopped (mirrors noice's `Util.interval` `enabled` predicate).
- Feature is opt-in via `config.progress.enabled` (default: `true`); when
  disabled, no autocmd or timer is created.
- Width may grow as `message` content changes — `ui.render` refreshes the float
  width via `nvim_win_set_config({ width = ... })` and re-runs `stack.reflow`.

### Non-Functional

- Zero allocations on the render path beyond the bar/spinner string concat.
- No external plugin dependencies (no `fidget.nvim`, no `noice.nvim` — native
  per `AGENTS.md` § "Prefer Native Primitives").
- Render throttle ≥ 100 ms — never re-render faster than 10 Hz regardless of
  LSP event rate.
- Adapter respects the existing toast lifecycle: it must use the public
  `toast.toast()`/`toast.update()`/`toast.dismiss(id)` API and must not reach
  into `state`/`stack`/`ui` directly.

### Out of Scope

- Multi-line progress toasts (toast is single-line by design).
- Grouping multiple progress tokens into one composite toast (one toast per
  token — keep it predictable).
- Cancellation UI (`$/cancelRequest`) — read-only display only.
- Overlay-extmark progress bar (noice's two-extmark trick) — unicode blocks
  are simpler and sufficient for a single-line toast.
- `:checkhealth` integration for progress (covered by toast's existing health).

## Research

### Repo Search

- Searched: `git grep -niE 'LspProgress|\$/progress|progress.*token|fidget'`
- Found:
  - No existing handler for `LspProgress` anywhere in `lua/beast/`.
  - `lua/beast/libs/toast/` (init, stack, ui, record, state, config) — generic
    transient notification stack. No update-in-place or sticky path today.
  - `lua/beast/libs/notify/` — persistent notification log (different shape;
    not a fit for live progress).
  - `lua/beast/libs/lsp/init.lua:80-90` — `M.setup()` is the natural wiring
    point for opting in (called once at startup).
  - `AGENTS.md` § *Shared Modules Registry* lists `view/`, `animate/`,
    `async/`, `util/`, `theme/` — none of them already wraps `LspProgress`.
- Reuse opportunity: **Adopt** the existing `toast` lib; **Extract first** two
  tiny generic helpers (`toast.update(record)` + `toast.dismiss(id)`) so the
  adapter doesn't touch internals.

### Package Search

- Searched: Neovim native APIs and the noice/fidget ecosystem.
- Found:
  - `vim.api.nvim_create_autocmd("LspProgress", ...)` — fires with
    `event.data = { client_id, params = lsp.ProgressParams }` on Neovim 0.10+.
  - `vim.lsp.get_client_by_id(id)` — for client name.
  - `vim.uv.new_timer()` + `vim.schedule_wrap` — throttle loop.
  - `vim.uv.hrtime()` — spinner frame source.
  - `noice.nvim/lua/noice/lsp/progress.lua` (reference only, not a dep) — 114
    lines, exactly the pattern we want.
  - `fidget.nvim` — heavy, opinionated UI; doesn't fit the toast model.
- Decision: **Use native** + **Build** a thin adapter (~120 lines) on top of
  the existing `toast` lib. Native LspProgress autocmd + `vim.uv` timer is the
  whole hook surface. Spec mirrors noice's structure but renders into our
  toast instead of noice's message router.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/toast/init.lua` | Modify | Add `M.update(record)` and `M.dismiss_id(id)` public helpers; keep existing `M.dismiss()` for "dismiss all". |
| `lua/beast/libs/toast/stack.lua` | Modify | Add `M.update(state, record)` that finds the view and re-runs `ui.render` + reflow; reuse existing `M.remove(state, id)` for `dismiss_id`. |
| `lua/beast/libs/toast/ui.lua` | Modify | `M.render(view)` recomputes width and applies `nvim_win_set_config({ width = ... })` when it changes. |
| `lua/beast/libs/toast/config.lua` | Modify | Add `progress` config block (enabled, throttle, done_linger, bar_width, spinner, spinner_interval) into the `defaults` table. |
| `lua/beast/libs/toast/progress.lua` | Create | New adapter: `LspProgress` autocmd → token table → throttled `vim.uv` timer → `Toast()` / `toast.update()` / `toast.dismiss_id()`. Exposes `M.setup()`. |
| `lua/beast/libs/toast/init.lua` (setup) | Modify | At end of `M.setup()`, call `require("beast.libs.toast.progress").setup()` when `config.progress.enabled` is true. |
| `docs/CODEMAP/libraries.md` | Modify | Update the `toast/` tree to list `progress.lua`. |

No changes needed in `lua/beast/libs/lsp/` — the progress adapter hooks into
the global `LspProgress` autocmd, which fires regardless of who registered the
server. Keeps the LSP lib and toast lib independent.

## Implementation Phases

### Phase 1: Generic toast update/dismiss API — minimum viable extraction

1. **Add `stack.update(state, record)`** (File: `lua/beast/libs/toast/stack.lua`)
   - Action: `function M.update(state, record)` — look up view via `state:find(record.id)`; if found, call `ui.render(view)` then `M.reflow(state)`. If not found, no-op.
   - Why: Enables in-place toast updates without exposing internals; mirrors `M.remove`'s shape.
   - Depends on: None.
   - Risk: Low.

2. **Refactor `ui.render` to refresh window width** (File: `lua/beast/libs/toast/ui.lua`)
   - Action: After computing `width, _ = r:dimensions()`, if `width ~= prev_width` (compare against `nvim_win_get_config(view.win).width`), call `pcall(nvim_win_set_config, view.win, { relative = "editor", anchor = "SE", row = current_row, col = vim.o.columns - config.padding_right, width = width, height = 1 })`. Pull `current_row` from `nvim_win_get_config`.
   - Why: Progress messages change length frame to frame; the float must grow/shrink to fit.
   - Depends on: None.
   - Risk: Medium — must preserve current `row`/`col` exactly, or reflow on the next update fixes it; verify reflow happens in `stack.update` (it does).

3. **Add `toast.update(record)` and `toast.dismiss_id(id)`** (File: `lua/beast/libs/toast/init.lua`)
   - Action:
     - `function M.update(record) stack.update(state, record) end`
     - `function M.dismiss_id(id) stack.remove(state, id) end`
   - Why: Public surface for any caller (progress adapter, future stream toasts) to update or selectively dismiss a toast.
   - Depends on: Step 1.
   - Risk: Low.

4. **Add a quick manual smoke** (File: `lua/beast/libs/toast/test.lua`)
   - Action: Append a `M.test_update()` that pushes one INFO toast with `timeout = false`, then on a 200 ms `vim.defer_fn` mutates `record.message` to a longer string and calls `Toast.update(record)`, then dismisses via `Toast.dismiss_id(record.id)` after 1500 ms.
   - Why: Lets us verify the update path without LSP wiring; pulled along by `:luafile` during dev.
   - Depends on: Step 3.
   - Risk: Low.

**Phase 1 lands as a usable, generic feature even without LSP wiring.**

### Phase 2: Progress adapter — wire LspProgress into toast

1. **Add `progress` config block** (File: `lua/beast/libs/toast/config.lua`)
   - Action: In `defaults`, add `progress = { enabled = true, throttle = 100, done_linger = 1000, bar_width = 20, spinner = { "⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏" }, spinner_interval = 100 }`.
   - Why: Centralised, frozen-by-metatable config per BeastVim § *Config Pattern*.
   - Depends on: None.
   - Risk: Low.

2. **Create `progress.lua` adapter** (File: `lua/beast/libs/toast/progress.lua`)
   - Action: Implement `M.setup()`:
     - Module-local `tokens = {}` keyed by `client_id .. "." .. token` → `{ record, value, kind, client_name }`.
     - Module-local `timer = vim.uv.new_timer()` (created on first event), stopped when `tokens` is empty.
     - `LspProgress` autocmd → `on_event(event.data)`: build `id`, merge `params.value` via `vim.tbl_deep_extend("force", entry.value or {}, params.value)`. If new, resolve client name via `vim.lsp.get_client_by_id` and create a sticky toast (`Toast(initial_line, "INFO", { title = client_name, timeout = false })`); cache the returned `Record` on the entry. Start the timer if not running.
     - `render_frame()` (called by timer, wrapped in `vim.schedule_wrap`): iterate `tokens`; for each, mutate `entry.record.message = format_line(entry)`; call `require("beast.libs.toast").update(entry.record)`. If `tokens` empties, `timer:stop()`.
     - `on_end(id)`: clamp percentage, render final `✔ title` frame, `vim.defer_fn(function() require("beast.libs.toast").dismiss_id(record.id); tokens[id] = nil end, config.progress.done_linger)`.
   - Why: Single owner of the LSP→toast pipeline; loosely coupled to toast core via the public API added in Phase 1.
   - Depends on: Phase 1 step 3, Phase 2 step 1.
   - Risk: Medium — autocmd lifecycle (augroup `beast_toast_progress`, `clear = true`) must be idempotent for `:source` reloads.

3. **Bar + spinner helpers** (File: `lua/beast/libs/toast/progress.lua`)
   - Action:
     - `local function bar(pct, width) local done = math.floor(pct/100*width + 0.5); return "[" .. string.rep("█", done) .. string.rep("░", width - done) .. "]" end`
     - `local function spinner() local frames = config.progress.spinner; local idx = math.floor(vim.uv.hrtime() / 1e6 / config.progress.spinner_interval) % #frames + 1; return frames[idx] end`
     - `local function format_line(entry)` — assembles the line shape from Requirements (handles `nil` percentage and `kind == "end"`).
   - Why: Pure helpers, easy to unit test.
   - Depends on: Step 2.
   - Risk: Low.

4. **Wire `progress.setup()` into `toast.setup()`** (File: `lua/beast/libs/toast/init.lua`)
   - Action: At end of `M.setup`, add `if config.progress and config.progress.enabled then require("beast.libs.toast.progress").setup() end`.
   - Why: Opt-in, lazy require — adapter is only loaded when enabled.
   - Depends on: Step 2.
   - Risk: Low.

5. **Update codemap** (File: `docs/CODEMAP/libraries.md`)
   - Action: Add `├── progress.lua ← LspProgress → in-place toast adapter` to the `toast/` tree (around lines 148–156).
   - Why: Per `.github/instructions/codemap-freshness.instructions.md`, codemap must stay current.
   - Depends on: Step 2.
   - Risk: Low.

## Testing Strategy

- Unit tests: `tests/` is currently empty for the toast lib, so no formal
  framework exists. Add manual probes inside `lua/beast/libs/toast/test.lua`:
  - `Toast.test_update()` (added in Phase 1.4) — verifies update + dismiss_id.
  - `Toast.test_progress()` (new in Phase 2) — fakes a sequence of
    `vim.api.nvim_exec_autocmds("LspProgress", { data = { client_id = 1, params = { token = "fake", value = { kind = ..., title = ..., percentage = ... } } } })` to exercise the full pipeline without an LSP server.
- Bench: not a hot path (events fire at human-perceivable rates, throttle caps
  at 10 Hz). No bench script required.
- Manual verification:
  1. Open a Lua file, ensure `lua_ls` is configured; observe a sticky toast in
     the bottom-right with `lua_ls   Indexing   ⠹  [████░░░░░░░░░░░░░░░░] 18%  scanning workspace` updating in place.
  2. Save the file repeatedly to trigger `null-ls` / formatter progress (if
     installed) — confirm multiple concurrent toasts stack correctly via the
     existing reflow.
  3. Wait for `kind == "end"` — toast switches to `✔ Indexing  lua_ls` for
     ~1 s, then fades out via existing `fade_out`.
  4. Disable via `require("beast.libs.toast").setup({ progress = { enabled = false } })`; reload Neovim; confirm no LspProgress autocmd registered (`:autocmd LspProgress` shows nothing under `beast_toast_progress`).

## Risks & Mitigations

- **Risk**: Many concurrent progress tokens (e.g. 3 LSPs all indexing on
  startup) flood the toast stack and obscure the buffer.
  → **Mitigation**: Existing `stack.reflow` already handles stacking; toasts
  are single-line so even 5 concurrent ones consume ~5 rows. If this becomes a
  problem, a follow-up spec can add a `progress.max_visible` cap. Out of scope
  for v1.

- **Risk**: Width churn (message text growing/shrinking each frame) causes
  visible jitter as the float resizes 10×/s.
  → **Mitigation**: Cap message at a stable inner width per frame; rely on
  existing `trim_to_width` in `ui.render` plus `max_width` config. If jitter
  persists, lock width to `max_width` for the lifetime of a progress toast in
  a follow-up — out of scope for v1.

- **Risk**: `LspProgress` autocmd fires in fast-event contexts on some servers,
  causing `nvim_open_win` to throw E5560.
  → **Mitigation**: Toast `init.lua` already guards with
  `vim.in_fast_event()` → `vim.schedule`. Reuse that path; the throttled timer
  also runs under `vim.schedule_wrap`, so all UI calls are main-loop only.

- **Risk**: Adapter holds stale `Record` references after a server crash.
  → **Mitigation**: On every frame, `vim.lsp.get_client_by_id(entry.client_id)`
  check; if `nil`, `dismiss_id(record.id)` and drop the token. Mirrors noice's
  `_update` guard.

## Success Criteria

- [ ] Open a Lua buffer with `lua_ls` running: a single-line toast appears in
      the bottom-right, updates in place at ≤ 10 Hz with a bar + spinner +
      percentage, then dismisses ~1 s after completion.
- [ ] `Toast.update(record)` and `Toast.dismiss_id(id)` are part of the public
      API and documented inline.
- [ ] Disabling via `setup({ progress = { enabled = false } })` results in no
      `beast_toast_progress` autocmd and no `vim.uv` timer.
- [ ] `:checkhealth beast.libs.toast` remains clean.
- [ ] Codemap (`docs/CODEMAP/libraries.md`) regenerated and the `toast/`
      tree lists `progress.lua`.
- [ ] No regression in existing toast behaviour — non-sticky toasts still
      auto-dismiss; `Toast.dismiss()` (all) still works.

## ADR Required

This dev spec involves architectural decisions that should be documented as
ADRs once committed:

- **Update-in-place toast lifecycle** — toast was originally a fire-and-forget
  transient stack; introducing `update(record)` and `dismiss_id(id)` turns
  records into mutable handles. Worth documenting the decision and the public
  contract (records returned by `Toast()` are now considered handles).
- **LSP progress UI strategy** — choosing native `LspProgress` + custom
  adapter over `fidget.nvim` / `noice.nvim`. Aligns with ADR-009-style "native
  over vendored" decisions; worth a short ADR referencing noice as the
  reference implementation we mirrored.

ADRs to be created during `/tec-implement`'s wrap-up, not now.

## Completed

- 2026-06-10 — Phase 1 + Phase 2 landed and verified via headless E2E test
  (begin → report → end → linger cleanup, plus same-token reuse during linger).
- ADRs: 033 (mutable handles), 034 (native progress, fidget/noice rejected).
