# ADR-014: Child Float Overlaying a Split, Lifecycle Owned by Parent

**Status:** Accepted

**Date:** 2026-05-06

**Evidence:** `lua/beast/libs/explorer/sticky.lua` (`StickyView`, `compute_pinned`, `M.refresh`, `M.close`); `lua/beast/libs/explorer/autocmds.lua` (`WinScrolled` / `CursorMoved` / `WinResized` / once-`WinClosed` registrations under `state.augroup`); `lua/beast/libs/explorer/init.lua` (`ensure_explorer` → `sticky.mount()`, `M.close` → `sticky.close()`); `lua/beast/libs/explorer/ui.lua` (sticky-owned `scrolloff`, `M.render` tail call); `docs/dev-specs/explorer-sticky-headers.md`

## Context

The explorer is a vertical split that can hold a deep tree. When the user scrolls past a directory or moves the cursor into a deeply-nested subtree, the ancestor directories disappear from view and the user loses context ("which `init.lua` is this?"). Adjacent libraries had two precedents for "small UI tied to a parent window":

- `explorer/prompt.lua` — a one-shot input float opened via `relative = "win"` for rename / create. Owned by the prompt's own keymaps; closes on confirm or `<Esc>`.
- `key/ui.lua` Action view — a persistent float over the key palette's main window (`relative = "win"`, `nvim_win_set_config` for resize), but its lifecycle is bespoke (key UI manages its own augroup).

Neither precedent was a *long-lived passive overlay* on a *split window* with its lifecycle deferred to the parent. We needed a third shape: a non-focusable float that lives as long as its parent does, refreshed on parent scroll / cursor / resize, and torn down by the parent's existing `WinClosed` once-handler.

## Decision

Adopt the following recipe for "child float over a split":

1. **View shape** — extend `Beast.View` with a tiny subclass:
   ```lua
   local View = require("beast.libs.view")
   ---@class Beast.Explorer.StickyView : Beast.View
   ---@field ns integer
   local StickyView = View:extend(function(obj, ns) obj.ns = ns end)
   ```
   Per [ADR-001](001-view-base-class-for-buf-win-pairs.md).

2. **Float geometry** — `relative = "win"`, `win = parent_win`, `row = 0`, `col = 0`, `width = parent_width`, `height = N`, `style = "minimal"`, `border = "none"`, **`focusable = false`**, **`noautocmd = true`**, `zindex = 30` (below `prompt.lua`'s `zindex = 50` so renames win conflicts).

3. **State location** — the float lives in the parent's state file
   (`state.sticky : Beast.Explorer.StickyView | nil`), nulled in
   `state.reset()`. The child module is stateless; only `state.lua` holds
   the handle (per AGENTS.md § *State Ownership*).

4. **Lifecycle delegation** — the parent's existing
   `state.augroup` registers the child's autocmds; the parent's
   once-`WinClosed` handler calls `child.close()`. The child does **not**
   create its own augroup.
   ```lua
   vim.api.nvim_create_autocmd("WinScrolled", { group = state.augroup,
     pattern = tostring(state.view.win), callback = sticky.refresh })
   vim.api.nvim_create_autocmd("CursorMoved", { group = state.augroup,
     buffer = state.view.buf, callback = sticky.refresh })
   ```

5. **Render coupling** — the child's `refresh()` is called at the tail of
   the parent's `ui.render()`, so every tree mutation propagates
   automatically. No additional event wiring.

6. **Cursor-under-float guard** — when the float covers the top N rows of
   the parent, the child sets `Util.wo(parent_win, "scrolloff", N)` on
   every refresh and resets to `0` on close. Built-in `scrolloff` keeps
   the cursor below the float on `gg`, `H`, `<C-u>`, and `focus_path`.
   The parent's static `scrolloff = 0` line in `ui.create` is removed
   so the child owns this option exclusively.

7. **Pin condition** — `compute_pinned()` walks the cursor node's
   ancestors and pins each one whose buffer row is `< top_row + N`.
   Because `N` is a function of the result, the loop iterates to a
   fixed point (monotonic in `≤ #ancestors + 1` steps).

## Alternatives Considered

- **Child augroup / WinClosed loop in the child module.** Rejected: would
  duplicate the parent's existing `state.augroup` lifecycle and create
  two teardown paths, exactly the bug class
  [ADR-007](007-confirm-as-vim-fn-confirm-drop-in.md) and the
  `prompt.lua` design avoided. Single owner = single shutdown.
- **Reserve the top N buffer rows for sticky lines (no float at all).**
  Rejected: would shift every tree row's buffer line number by N, break
  `state.current_node`'s `pos[1] - 1` arithmetic, and require keeping
  the sticky lines in sync with the underlying nodes mid-buffer
  (modifiable churn on every scroll). The float keeps line numbers
  stable.
- **Manage cursor-under-sticky with a `CursorMoved` callback that calls
  `winrestview`.** Rejected during dev-spec design: that fights the
  user's own scroll, flickers, and needs debouncing.
  `scrolloff = N` is the canonical Neovim primitive for "keep cursor
  away from top edge" — one option write per refresh, zero
  per-keystroke work.
- **Anchor the sticky to the topmost-visible node instead of the
  cursor.** Implemented first, rejected on user feedback: a sticky
  that tracks the viewport doesn't answer "where am I?" — it answers
  "what's at the top of the screen?". The cursor anchor is what
  matches the user's mental model.

## Rationale

1. **Single source of teardown.** Having the child's `WinClosed`-driven
   close run inside the parent's existing once-handler means there is
   exactly one place where lifecycle ends. This is the same pattern
   `prompt.lua` proves out (a buffer-scoped `WinLeave` autocmd that
   schedules cancel) — generalised to a long-lived overlay.
2. **No new lifecycle primitive.** `relative = "win"` + `noautocmd` +
   `focusable = false` + `zindex` is already documented in two
   precedents (`prompt.lua`, `key/ui.lua` Action). This ADR codifies
   the recipe rather than inventing a new one.
3. **Built-in scrolloff sidesteps a whole class of cursor-tracking
   bugs.** The dev-spec rubber-duck pass surfaced the
   "cursor lands under the float" risk; using Neovim's built-in
   primitive (rather than a CursorMoved callback fighting user
   intent) was the highest-signal mitigation.
4. **Fixed-point pin loop is bounded.** Pinning is monotonic — adding
   an entry can only ever cause more entries to qualify, never fewer
   — so the loop converges in `≤ #ancestors + 1` iterations
   (real-world ≤ 5 even on deep trees).
5. **Deferring to the parent's render coupling means zero invalidation
   bugs.** Every tree mutation (open / collapse / show_hidden / paste /
   focus_path) ends in `ui.render()`; the sticky refresh chains off
   that same call. There is no separate "did the tree change?" event
   to listen for.

## Consequences

- **Positive:**
  - Sticky shows ancestors of the cursor's node, with fixed-point pin
    selection — no duplicate rows, no missed rows.
  - Cursor never lands in rows hidden under the float
    (`scrolloff = N` enforces the invariant).
  - Float survives parent resize, mode change, colorscheme change
    (highlights are palette-driven and re-applied via the global
    ColorScheme reload pipeline).
  - Overlay teardown is automatic — parent's once-`WinClosed` handles
    it; no leaked `beast-explorer-sticky` buffers after `:q`.
- **Negative:**
  - The `relative = "win"` + cursor-anchored refresh fires `refresh()`
    on every `j`/`k`. Cost is bounded
    (O(depth), uses cached flat list), but components copying this
    pattern need to keep `refresh` cheap.
  - The pattern is currently only proven on a split parent. Floats
    parented to other floats may need adjustments
    (`zindex` ordering, `noautocmd` interaction with the parent's
    own autocmds).
- **Risks:**
  - If a future explorer-internal autocmd creates and closes the
    sticky during the same event tick, the once-`WinClosed` handler
    could fire on the *sticky's* close instead of the parent's.
    Mitigated by the float being non-focusable
    (`WinClosed` for the sticky doesn't trigger the parent's
    `pattern = state.view.win` filter).
  - `scrolloff` is a window-local option, but the user could override
    it via `:setlocal scrolloff=...`. Acceptable: the next refresh
    overwrites it, which is the desired behaviour.

## References

- Dev spec: `docs/dev-specs/explorer-sticky-headers.md`
- Code:
  - `lua/beast/libs/explorer/sticky.lua` — module body, `StickyView`, `compute_pinned`, `M.mount`/`refresh`/`close`
  - `lua/beast/libs/explorer/autocmds.lua` — `WinScrolled` / `CursorMoved` / `WinResized` / `VimResized` registrations, sticky teardown in once-`WinClosed`
  - `lua/beast/libs/explorer/init.lua` — `ensure_explorer` calls `sticky.mount()`; `M.close` calls `sticky.close()`
  - `lua/beast/libs/explorer/ui.lua` — `M.render` tails into `sticky.refresh()`; static `scrolloff = 0` removed
  - `lua/beast/libs/explorer/state.lua` — `state.sticky` field, nulled in `reset`
  - `lua/beast/libs/explorer/config.lua` — `sticky = true` default
  - `lua/beast/libs/explorer/highlights.lua` — `BeastExplorerStickyBg`, `BeastExplorerStickyBorder`
- Related ADRs:
  - [ADR-001](001-view-base-class-for-buf-win-pairs.md) — `View` base class (StickyView extends it)
  - [ADR-002](002-component-based-ui-architecture.md) — module-level state lives in `init.lua` / `state.lua`; child modules are stateless tables of functions
  - [ADR-003](003-readonly-config-metatable-pattern.md) — `config.sticky` flag follows the read-only proxy
  - [ADR-008](008-namespaced-highlight-groups.md) — `BeastExplorerSticky*` follows the namespaced pattern; reset on ColorScheme via the existing explorer entry in `M.highlight_modules`
