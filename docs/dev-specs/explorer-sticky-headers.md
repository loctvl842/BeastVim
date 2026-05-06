# Dev Spec: Explorer Sticky Ancestor Headers

## Summary

Add a floating overlay on top of the explorer split that shows the ancestor
directories of the topmost visible node when those ancestors have scrolled out
of view. The overlay is a new `StickyView` (subclass of `Beast.View`) that lives
above the explorer window via `relative = "win"`, dynamically resizes its
height to match the number of pinned ancestors, and refreshes on
`WinScrolled` / tree mutations. It is purely visual — no click-to-jump in this
spec (deferred per design discussion).

## Requirements

- When the explorer is scrolled so that one or more ancestors of the topmost
  visible node are above `w0`, those ancestors render in a sticky float at the
  top of the explorer window, ordered from root → nearest parent.
- The root header (depth-0 uppercase basename) participates in the stack as
  the topmost pinned entry whenever the buffer is scrolled past line 1.
- The float's height equals the number of pinned ancestors. When zero, the
  float is closed (not just hidden), so it never steals a row of explorer
  content.
- The float's width matches the explorer split width and updates on
  `WinResized` / `VimResized`.
- The float is non-focusable (`focusable = false`, `noautocmd = true`) and
  does not intercept the cursor or trigger BufEnter/WinEnter.
- **The cursor never sits in the rows visually hidden under the sticky
  float.** The float overlays the top N rows of the explorer window
  (`row = 0..N-1`) without shifting buffer line numbers — so the rows
  `topline..topline+N-1` are still selectable, just invisible. After every
  refresh the explorer's effective `scrolloff` is set to `N` so the cursor
  is forced below the sticky stack on every motion (`gg`, `H`, `j`, `k`,
  `<C-u>`, etc.) and on `focus_path`.
- Sticky entries render with the directory icon (open glyph), the same
  `BeastExplorerDir` colour, and indentation that matches their depth so the
  hierarchy reads naturally.
- A subtle separator (underline on the last sticky row) marks where the
  sticky stack ends and real explorer content begins.
- Refresh runs on: `WinScrolled` (explorer window), `CursorMoved` (explorer
  buffer), after every `ui.render()`, and on `WinResized` / `VimResized`.
- Closes cleanly when the explorer is closed (no leaked float, no dangling
  autocmds).
- Configurable via `config.sticky` (boolean, default `true`).
- **Out of scope**: click/<CR> to jump to a pinned ancestor; horizontal
  scrolling; sticky for non-directory nodes; per-entry truncation rules
  beyond a simple right-truncate.

## Research

### Repo Search

- Searched for: `WinScrolled`, `nvim_open_win.*relative.*win`, `topline`,
  ancestor-walk patterns, existing float-over-split usage.
- Found:
  - `lua/beast/libs/explorer/prompt.lua:70` — already opens a child float over
    the explorer using `relative = "win", win = state.view.win`. Same
    positioning idiom is reusable.
  - `lua/beast/libs/key/ui.lua:211` and `lua/beast/libs/packer/ui.lua:911` —
    additional `relative = "win"` floats with `nvim_win_set_config` for
    dynamic resize. Confirms the supported pattern for dynamic geometry.
  - `lua/beast/libs/explorer/render.lua:25-48` — `build_prefix` already walks
    ancestors via `state.tree.nodes[node.parent]`. Same walk shape applies for
    the sticky stack.
  - `lua/beast/libs/explorer/state.lua` — flat list cached on `Tree.version`;
    cheap to map a buffer row to a node.
  - `lua/beast/libs/view.lua` — `View:extend(init)` is the canonical way to
    subclass with extra fields (already used by `ExplorerView`).
  - `lua/beast/util/init.lua:24` — `Util.create_scratch_buf(filetype)` covers
    the scratch-buffer setup; no `Buffer.new` re-implementation needed.
  - `AGENTS.md` § *Shared Modules Registry* — `Beast.View` is the required
    base for any buf+win pair. § *Known DRY Opportunities* — scratch buf was
    extracted; nothing else triggered.
- Reuse opportunity: **Adopt** — extend `Beast.View`, mirror the
  `relative = "win"` pattern from `prompt.lua` / `key/ui.lua`, walk ancestors
  the same way `render.build_prefix` does. No new shared module needed yet.

### Package Search

- Searched: native Neovim API for floats, scroll detection.
- Found:
  - `vim.api.nvim_open_win` with `relative = "win"` and `nvim_win_set_config`
    for resize.
  - `vim.fn.line("w0", win)` for the topmost visible buffer row.
  - `WinScrolled` autocmd — fires per-window with `match = winid`.
  - No third-party plugin needed; this is a thin layer over the Neovim float
    API.
- Decision: **Use native** — `nvim_open_win` + `WinScrolled`. Consistent with
  AGENTS.md preference for native primitives over plugin dependencies.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/explorer/sticky.lua` | **Create** | `StickyView` (subclass of `Beast.View`), `mount`, `refresh`, `close`, ancestor-pin computation, render. |
| `lua/beast/libs/explorer/state.lua` | **Modify** | Add `sticky: Beast.Explorer.StickyView \| nil` field to `Beast.Explorer.State`; null it in `M.reset()`. |
| `lua/beast/libs/explorer/config.lua` | **Modify** | Add `sticky = true` to `defaults` (boolean toggle for the feature). |
| `lua/beast/libs/explorer/init.lua` | **Modify** | Call `sticky.mount()` from `ensure_explorer()` after `keymaps.mount()`; call `sticky.close()` from `M.close()`. |
| `lua/beast/libs/explorer/ui.lua` | **Modify** | Call `sticky.refresh()` at the tail of `M.render()` so the overlay tracks every tree mutation. Remove the static `scrolloff = 0` so sticky owns it. |
| `lua/beast/libs/explorer/autocmds.lua` | **Modify** | Register `WinScrolled` (pattern = explorer winid) and `VimResized` / `WinResized` callbacks under the existing `state.augroup` to call `sticky.refresh()`. Also clear `state.sticky` in the existing `WinClosed` once-handler. |
| `lua/beast/libs/explorer/highlights.lua` | **Modify** | Add `Sticky` (background), `StickyBorder` (the underline separator) groups, palette-derived. |

## Implementation Phases

### Phase 1 — Sticky ancestor overlay (single phase)

The feature is a coherent unit; splitting would leave broken intermediate
states (a half-wired float). Phase 1 ships everything.

1. **Create `sticky.lua` module** (File: `lua/beast/libs/explorer/sticky.lua`)
   - Define `Beast.Explorer.StickyView : Beast.View` via
     `View:extend(function(obj, ns) obj.ns = ns end)` — buf, win, ns. Follows
     the existing `ExplorerView` pattern in `ui.lua`.
   - Module-level table `M` with three public functions:
     - `M.mount()` — idempotent: if `state.sticky` is valid, return; else
       create a scratch buf via `Util.create_scratch_buf("beast-explorer-sticky")`,
       call `nvim_open_win(buf, false, { relative = "win", win = state.view.win,
       row = 0, col = 0, width = explorer_width, height = 1, style = "minimal",
       border = "none", focusable = false, noautocmd = true, zindex = 30 })`,
       set `Util.wo(win, "winhighlight", "Normal:BeastExplorerStickyBg")`,
       store `state.sticky = StickyView(buf, win, ns)`.
       Immediately call `M.refresh()` and hide the float (height = 0 path)
       if there are no ancestors yet. Note: `nvim_open_win` requires
       `height >= 1`; treat "zero pinned" by closing the float entirely
       and re-opening on the next refresh that has ≥1 pinned entry.
     - `M.refresh()` — guard: bail if `not config.sticky`, if `state.view`
       invalid, or if `state.tree` nil. Compute pinned ancestors (see
       step 2). If empty → close the float (call `state.sticky:close()`
       and set `state.sticky = nil`). If non-empty → ensure float exists
       (call `M.mount()` if missing), then resize via `nvim_win_set_config`
       to current explorer width and height = `#pinned`, write lines and
       extmarks via the same shape used by `render.write` (no
       `nvim_buf_clear_namespace` of the explorer ns — sticky owns its
       own namespace).
     - `M.close()` — close `state.sticky` if valid, set to nil.
   - Why: The View pattern, `__call`-style mount, and stateless function
     table match `prompt.lua` / `render.lua` exactly (AGENTS.md § *The View
     Pattern*, § *Component Tables vs Classes*).
   - Depends on: None.
   - Risk: Low.

2. **Pin computation in `sticky.lua`** (File: `lua/beast/libs/explorer/sticky.lua`)
   - Action: Add a local `compute_pinned()` helper:
     ```
     local top_row = vim.fn.line("w0", state.view.win) -- 1-indexed buf row
     if top_row <= 1 then return {} end                -- root header visible
     local nodes = state.tree:flat({ show_hidden = config.show_hidden })
     local top_node = nodes[top_row - 1]               -- line 1 = root header
     if not top_node then return {} end
     -- Walk parents; collect dirs whose buffer row < top_row.
     -- Always include the root header (depth 0 uppercase) as the first entry
     -- since by definition top_row > 1 means line 1 is scrolled out.
     ```
     Output: a list `{ {label, depth, kind="root"|"dir"}, ... }` ordered
     root → nearest-parent. Use the same flat-index lookup that
     `state.current_node` uses (already proven, line 33-46 of
     `state.lua`).
   - Why: Single source of truth for the ancestor stack. O(depth) lookup,
     uses the cached flat list (no extra iteration over the tree).
   - Depends on: Step 1.
   - Risk: Low. Edge case: when `top_row` falls between renders the flat
     list may be slightly stale; guard with `if not top_node then
     return {} end`.

3. **Render lines + highlights for sticky** (File: `lua/beast/libs/explorer/sticky.lua`)
   - Action: For each pinned entry, build:
     `string.rep("  ", depth) .. icon .. " " .. name`
     - root entry uses uppercase basename, no icon (matches `render.build`
       line 60), highlighted as `BeastExplorerTitle`.
     - dir entries use `config.icon.dir_open`, name from `node.name`,
       highlighted as `BeastExplorerDir` (icon) + default fg (name).
     - Indent prefix highlighted as `BeastExplorerIndent`.
     - The last sticky row gets an extmark `{ end_col = #line, hl_group =
       "BeastExplorerStickyBorder", hl_mode = "combine", line_hl_group =
       nil }` with `underline = true` baked into the highlight group
       definition (see step 6).
   - Then `nvim_buf_set_lines` + extmarks the same way `render.write` does
     (modifiable toggle, pcall-wrapped).
   - Why: Visual parity with the explorer's own rendering. Reusing existing
     highlight groups keeps theming consistent.
   - Depends on: Step 2.
   - Risk: Low.

4. **Wire mount/close into `init.lua` and `ui.lua`** (Files:
   `lua/beast/libs/explorer/init.lua`, `lua/beast/libs/explorer/ui.lua`)
   - `init.lua`: in `ensure_explorer()`, after `autocmds.mount()`, add
     `require("beast.libs.explorer.sticky").mount()`. In `M.close()`, before
     `ui.close()`, add `require("beast.libs.explorer.sticky").close()`.
   - `ui.lua`: in `M.render()`, after the existing `render.write(...)` and
     before `if on_done then on_done() end`, add a call to
     `require("beast.libs.explorer.sticky").refresh()`. Use a local require
     at the top of the file to avoid a circular dependency at load time —
     sticky already requires `state` and `config`, not `ui`, so a top-level
     require in `ui.lua` is safe.
   - Why: Sticky lifecycle follows the explorer's. Refresh after every
     render keeps the overlay synced with tree mutations (open / collapse /
     show_hidden / paste).
   - Depends on: Step 1.
   - Risk: Low. Recheck for accidental circular imports during
     implementation.

5. **Scroll/resize autocmds in `autocmds.lua`** (File:
   `lua/beast/libs/explorer/autocmds.lua`)
   - Action: Inside `M.mount()`, register under the existing
     `state.augroup`:
     - `WinScrolled` with `pattern = tostring(state.view.win)` →
       `sticky.refresh()`.
     - `WinResized` and `VimResized` (no pattern) → `sticky.refresh()`.
     - In the existing once-`WinClosed` handler (lines 153-161), call
       `require("beast.libs.explorer.sticky").close()` before clearing
       `state.augroup`.
   - Why: Autocmd lifecycle stays in one place per AGENTS.md
     (§ *Autocmds*) — the existing `state.augroup` is the single owner.
     Reuses the proven once-`WinClosed` shutdown.
   - Depends on: Step 1.
   - Risk: `WinScrolled` fires often; pin computation is O(depth) and uses
     the cached flat list, so this is not a hot path. Verify with manual
     scrolling on a deep tree.

6. **Highlights for sticky** (File:
   `lua/beast/libs/explorer/highlights.lua`)
   - Action: Add to the `Util.colors.set_hl("BeastExplorer", { ... })`
     call:
     - `StickyBg = { bg = Util.colors.darken(p.dark1, 1) }` — a hair darker
       than the explorer normal so the float reads as "above" the content.
     - `StickyBorder = { fg = Util.colors.darken(p.dimmed5, 10),
       underline = true }` — same colour family as `WinBar`'s separator.
   - Why: Visually distinguishes the sticky stack from the live tree
     while keeping it palette-driven (matches the existing
     `BeastExplorerWinBar` shape).
   - Depends on: None.
   - Risk: Low.

7. **State + config wiring** (Files:
   `lua/beast/libs/explorer/state.lua`,
   `lua/beast/libs/explorer/config.lua`)
   - `state.lua`: add `sticky = nil` to the state table; null it in
     `M.reset()`. Update the `@class Beast.Explorer.State` annotation with
     `---@field sticky Beast.Explorer.StickyView|nil`.
   - `config.lua`: add `sticky = true` to `defaults`. Document inline.
   - Why: Module-level mutable state lives in the right places per
     AGENTS.md (§ *State Ownership*, § *Config Pattern*).
   - Depends on: None.
   - Risk: Low.

8. **Cursor-under-sticky guard via `scrolloff`** (Files:
   `lua/beast/libs/explorer/sticky.lua`,
   `lua/beast/libs/explorer/ui.lua`)
   - The overlay does NOT push down buffer content — it covers the top N
     window rows without changing buffer line numbers. So when the cursor
     is on one of those rows (e.g. after `gg`, `H`, `focus_path`, or
     scrolling up), it is hidden under the sticky and the user can't
     see what node is selected — `state.current_node()` still works, but
     visually the explorer looks like the wrong line is highlighted.
   - Action — `sticky.refresh()`:
     - When the float is created and after every height change, set
       `Util.wo(state.view.win, "scrolloff", N)` where N is the current
       sticky height. Built-in `scrolloff` keeps the cursor at least N
       rows below the topline on any motion, so the cursor naturally
       parks below the sticky stack for `gg`, `H`, `j`, `<C-u>`,
       `focus_path`'s `zz`, etc.
     - When the float is closed (N becomes 0), restore the explorer's
       baseline `scrolloff = 0` (the value `ui.create` originally set on
       line 73).
   - Action — `ui.lua`:
     - Remove the literal `vim.wo[win].scrolloff = 0` from `M.create`
       (line 73) so sticky owns this option without fighting the
       initial setup. `sticky.refresh()` will set it on its first run
       (to 0 if no ancestors are pinned, otherwise N).
   - Why: `scrolloff` is the canonical Neovim primitive for "keep the
     cursor away from the top edge". Reusing it sidesteps the need for a
     `CursorMoved` callback that calls `winrestview` (which would fight
     the user's own scroll, flicker, and need debouncing). One option
     write per refresh = no per-keystroke work.
   - Edge cases:
     - At buffer top (`topline == 1`), sticky is closed (N=0) by
       construction — `compute_pinned` returns `{}` when
       `top_row <= 1`. So scrolloff=0 is correct there.
     - When the cursor is on a line beyond the buffer's last + N rows,
       Neovim relaxes scrolloff at the bottom (built-in behaviour);
       harmless for the explorer.
     - On rapid expand/collapse the sticky height can change between
       renders; `refresh()` runs at the tail of `ui.render()` so
       scrolloff stays in sync.
   - Depends on: Steps 1–4.
   - Risk: Medium — the interaction between `scrolloff`, `WinScrolled`,
     and `winfixwidth` should be smoke-tested; a regression here would
     manifest as the cursor jumping unexpectedly. Manual verification
     (see Testing Strategy step 9) is the gate.

## Testing Strategy

- **Unit tests**: `tests/` is currently empty in the project; following the
  convention of adjacent specs (`explorer-highlights-palette.md`, etc.) this
  spec also relies on manual verification rather than introducing a test
  harness in a single feature spec. If a `tests/` harness lands later, a
  small case for `compute_pinned` (pure over a synthetic flat list) should
  be added — flagged here, not built here.
- **Bench**: Not a hot path in the bench-harness sense — `WinScrolled` is
  user-driven and pin computation is O(depth). No new bench script needed.
- **Manual verification**:
  1. `:lua require("beast").setup({})` then open the explorer on this repo.
  2. Navigate into `lua/beast/libs/explorer/` → expand a deep dir →
     scroll until the parent dirs leave the viewport.
  3. Confirm a float appears at the top with the ancestors stacked
     (root → parent), separator underline at the bottom, width matches
     the explorer.
  4. Scroll back to the top → confirm the float disappears entirely
     (window closed, not just hidden).
  5. Resize the explorer split (`:vert resize +5`) → confirm the float
     resizes to match.
  6. Toggle hidden files (`H`) → tree re-renders → sticky stack
     refreshes correctly.
  7. Close the explorer (`:q`) → confirm no leaked float in
     `:tabwin` and no errors.
  8. Set `sticky = false` in setup → confirm no overlay ever appears.
  9. **Cursor-under-sticky regression check**: scroll deep so 3+
     ancestors are pinned, then press `gg` and `H`. The cursor must
     land just below the sticky stack (visually on the first
     non-pinned row), not on a row hidden under the float. Repeat with
     `<C-u>`, `kkkk`, and `focus_path` (open a deeply-nested file from
     a non-explorer window — the explorer must scroll so the focused
     node sits below the sticky).

## Risks & Mitigations

- **Risk**: `WinScrolled` fires per keystroke during scroll, causing
  visible flicker. **Mitigation**: pin computation reuses the cached flat
  list; `nvim_win_set_config` with the same dimensions is a no-op. If
  flicker is observed, debounce with `vim.schedule`.
- **Risk**: `noautocmd = true` only suppresses autocmds at creation time;
  later `nvim_buf_set_lines` on the sticky buf could fire `TextChanged`.
  **Mitigation**: scratch buffers don't fire `TextChanged` for `nofile`
  + non-modifiable writes through `pcall`; pattern matches `render.write`
  which is proven.
- **Risk**: Circular require (`ui.lua` → `sticky.lua` → `state.lua` →
  `ui.lua`?). **Mitigation**: `sticky.lua` only requires `state`,
  `config`, and `view` (already loaded by `ui.lua`). No cycle.
- **Risk**: Float sits at `row = 0, col = 0` — could collide with
  prompt.lua's input float (also `row = 0, col = 0`-ish) when renaming.
  **Mitigation**: prompt.lua uses `zindex = 50`; sticky uses
  `zindex = 30`, so the prompt always wins. Manual repro: rename while
  scrolled deep — confirm prompt overlays the sticky.
- **Risk**: `scrolloff = N` could fight a user who explicitly wants the
  cursor at the very top (e.g. via `:1`). **Mitigation**: when sticky
  is at the top of the buffer (`top_row <= 1`), `compute_pinned`
  returns empty and scrolloff is reset to 0. The only case where
  `scrolloff > 0` is when the user has scrolled past the root header,
  which is precisely when hiding the cursor under the float would be a
  bug.
- **Risk**: `focus_path` calls `nvim_win_set_cursor` then `zz`. With
  `scrolloff = N`, `zz` still centres the cursor; if the centred row
  would put the cursor into the hidden zone (very small explorer
  height), Neovim's built-in scrolloff enforcement re-adjusts the
  topline. **Mitigation**: the existing `zz` in `focus_path` already
  handles short windows; verify in the manual test (Testing Strategy
  step 9).
- **Risk**: `nvim_open_win` fails when the explorer window has zero width
  on some race. **Mitigation**: `pcall` the open; on failure leave
  `state.sticky` nil and let the next refresh retry.

## Success Criteria

- [ ] When scrolled below line 1 in a deep tree, the floating overlay shows
      the root + each ancestor directory in order, with correct
      indentation.
- [ ] Overlay height equals the number of pinned ancestors; overlay
      disappears entirely when nothing is pinned.
- [ ] Overlay width tracks the explorer split width on resize.
- [ ] Overlay does not steal focus or fire BufEnter/WinEnter for the
      explorer's autocmds (cursor stays on the explorer line, no
      cursor-flip).
- [ ] **Cursor never lands in the rows hidden under the sticky float.**
      `gg`, `H`, `<C-u>`, manual scrolling, and `focus_path` all leave
      the cursor on a visually visible row (just below the sticky
      stack).
- [ ] Closing the explorer leaks no float window
      (`vim.api.nvim_list_wins()` post-close returns no
      `beast-explorer-sticky` buffer).
- [ ] `config.sticky = false` disables the feature entirely; no float is
      created.
- [ ] No regressions in existing explorer behaviour (rename float, create
      prompt, focus_path, paste-with-conflict prompt).

## ADR Required

This dev spec introduces an architectural pattern that is not yet
documented and is likely to be reused by future libraries (a child float
overlaying a split window, driven by `WinScrolled` + dynamic
`nvim_win_set_config` resize). On commit, an ADR should capture:

- Decision: child float over a split, owned by the parent library, with
  lifecycle delegated to the parent's existing `state.augroup` (rather
  than a separate augroup).
- Why `relative = "win"` + `noautocmd = true` + `focusable = false` is the
  canonical recipe.
- Reference to existing precedents (`prompt.lua`, `key/ui.lua`'s
  `Action` view) and how this generalises them.
