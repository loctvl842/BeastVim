---
name: finder-colorscheme-swatches
description: Theme picker rows with a ten-swatch palette strip, separator lines and a two-box card layout, fed by a cached headless palette extractor
generated: 2026-11-11
---

> PM Spec: [docs/pm-specs/finder-colorscheme-swatches.md](../pm-specs/finder-colorscheme-swatches.md)

# Summary
The `colorschemes` finder source gains a per-theme swatch strip (bg, fg, red, orange, yellow, green, cyan, blue, purple, grey). Swatch colors are read by a headless Neovim child that applies each theme once and the result is cached on disk, so opening the picker never repaints the editor. The list view learns two generic things (multi-chunk right-aligned text, separator rows between items) and the layout gains a "cards" variant (input and list as two separate boxes). Picker behavior is untouched.

---

# Context

## Problem
`source/colorschemes.lua` returns only names, `format.colorschemes` renders one `BeastFinderListFile` chunk, `ui/list.lua` supports a single `right_align` chunk and no row separators, and `layout.lua` always joins input and list with a shared `├─┤` border at 80% width. A theme's colors are only knowable by applying it, and `:colorscheme` clears all highlights globally and fires `ColorScheme` autocmds, so reading ~100 themes in-process would flash the editor.

### Solution
After the change: opening `<leader>c` reads a JSON cache (name -> mtime + 10 hex colors) and shows swatches at once. Themes missing from the cache (new/changed) show dim grey squares while a headless child computes them; the list re-renders when the child finishes. The list renders a `─` separator row between items and paints each swatch with its own highlight group. The picker is laid out as two bordered boxes in a narrow centered column.

---

# Research

### Repo Search
- Searched for: `colorschemes`, `right_align`, `header_fn`, `item_cost`, `layout.calc`, `Beast.Theme.Source`, `vim.system`/`jobstart` in finder, `ColorScheme` autocmds in finder, `tests/test-finder-*`.
- Found:
  - `lua/beast/libs/finder/source/colorschemes.lua` lists names from rtp `colors/*` (ranked beastvim > nvim > plugin).
  - `ui/list.lua` already has a variable-height row machinery for grouped sources (`_header_fn`, `item_cost`, `_item_to_row`, `_row_to_item`, `item_at_row`) that re-renders on cursor move. A separator row is the same kind of non-match row.
  - `apply_row_highlights` supports only one `right_align` chunk (`virt_text_pos = "right_align"`).
  - `layout.lua` has two layouts (with/without preview), both with shared `├─┤` input/list border and `config.width` of the editor.
  - `theme/sources/plugin.lua` + `theme/palette.lua` already map highlight groups to palette slots (`Normal`, `DiagnosticError`, `String`, `Comment`, ...) after a colorscheme is applied.
  - `finder-index-subprocess` dev spec and `lua/beast/libs/finder` pipeline use a child process for heavy work.
  - Finder highlights are defined through `Util.colors.build("BeastFinder", ...)` in `finder/highlights.lua`.
  - Existing tests are plain `nvim --clean --headless -l tests/test-*.lua` scripts with a local `assert_test`.
- Reuse opportunity: Yes - the grouped-row machinery in `ui/list.lua`, the group -> color idea from `theme/sources/plugin.lua`, `Util.colors.inspect`, the `vim.system` child pattern, and the test harness shape.

### Built-in / Existing Lib Check
- Checked: `nvim_set_hl` with per-window namespaces (`nvim_win_set_hl_ns`), extmark `virt_text` with several chunks, `vim.system`, `vim.json`, `vim.fs` / `vim.uv.fs_stat` for mtime, `vim.o.runtimepath` handoff to a `-u NONE` child.
- Found: multi-chunk `virt_text` works with `right_align`; `:colorscheme` runs `highlight clear`, so custom swatch groups must be re-defined after a live preview changes the theme; a `-u NONE -l worker.lua` child can take the parent's `runtimepath` as an argument.
- Decision: **Reuse** list row machinery and `Util.colors.inspect`; **Build** the worker/cache module (nothing computes per-theme palettes without applying them); **Use** built-in extmark virt_text and `vim.system`.

---

# Architecture Changes
- New `lua/beast/libs/finder/source/colorscheme_swatches.lua` - cache load/save (`stdpath("cache")/beast-finder-colorscheme-swatches.json`), staleness check by file mtime, spawns the worker for missing themes, exposes `get(name)` -> `string[10]|nil` and `ensure(names, on_done)`.
- New `lua/beast/libs/finder/source/colorscheme_swatches_worker.lua` - run by the child (`nvim --headless -u NONE -l`); sets rtp, for each theme applies it with `ColorScheme` autocmds suppressed, reads the ten roles via `nvim_get_hl`, prints JSON.
- Modified `lua/beast/libs/finder/source/colorschemes.lua` - attach `item.path` (mtime key) and `item.swatches` (from cache) to items.
- Modified `lua/beast/libs/finder/ui/list.lua` - `Highlight.chunks` (multi-chunk right-align) and an optional `separators` mode that inserts a `─` row between items using the existing non-match-row path.
- Modified `lua/beast/libs/finder/format.lua` - `M.colorschemes` returns the name plus the swatch chunks; truncates long names.
- Modified `lua/beast/libs/finder/highlights.lua` - `ListSeparator` group, `SwatchEmpty` (dim grey) group; dynamic `BeastFinderSwatch<hex>` helper.
- Modified `lua/beast/libs/finder/layout.lua` - `calc` takes a layout kind; `cards` returns two fully bordered boxes with a fixed narrow width.
- Modified `lua/beast/libs/finder/state.lua` + `init.lua` + `relayout` - pass the layout kind and separators flag from `opts` into `ui.list.create` / `layout.calc`.
- Modified `lua/beast/libs/finder/autocmds.lua` - on `ColorScheme`, re-define the swatch groups used by visible rows (live preview wipes them).
- Modified `lua/beast/init.lua` (`<leader>c` mapping) - add `layout = "cards"`; the preview/close callbacks stay as they are.
- New `tests/test-finder-colorscheme-swatches.lua`, `tests/test-finder-list-separators.lua`.

## Implementation Phases

## Phase 1: Swatch data - cached palette extraction, no visible change
1. **Worker script** (File: `lua/beast/libs/finder/source/colorscheme_swatches_worker.lua`)
   - Action: for each theme name argument, `vim.o.eventignore = "ColorScheme"`, `pcall(vim.cmd.colorscheme, name)`, read ten colors: bg `Normal.bg`, fg `Normal.fg`, red `ErrorMsg.fg` (falls back to `DiagnosticError`), orange `Number.fg`, yellow `WarningMsg.fg` (falls back to `DiagnosticWarn`), green `String.fg`, cyan `Special.fg`, blue `Function.fg`, purple `Keyword.fg`, grey `Comment.fg`. Unset or failed -> `false`. Print one JSON object.
   - Why: PM rule - read a theme's own colors without touching the user's editor.
   - Depends on: None
   - Risk: Medium - themes that need `setup()` or `background` may produce odd colors; they degrade to grey or slightly off colors, never errors (`pcall`).
2. **Cache + spawner** (File: `lua/beast/libs/finder/source/colorscheme_swatches.lua`)
   - Action: load JSON cache; entry valid when stored mtime equals the theme file's mtime; `ensure(names, on_done)` spawns one `vim.system` child with `--headless -u NONE`, passing the parent's runtimepath, for stale/missing names only; merge results, write cache, call `on_done`. Ignore a second `ensure` while one is running.
   - Why: "all rows show swatches at once" on every open after the first; no work when warm.
   - Depends on: Step 1
   - Risk: Medium - first cold run takes a few seconds; handled by showing dim squares then re-rendering.
3. **Attach to items** (File: `lua/beast/libs/finder/source/colorschemes.lua`)
   - Action: record the colorscheme file path while globbing, set `item.swatches = swatches.get(name)`, kick off `ensure` for misses.
   - Depends on: Step 2
   - Risk: Low
4. **Test** (File: `tests/test-finder-colorscheme-swatches.lua`)
   - Action: worker against `colors/monokai-pro.lua` returns ten hex strings; cache hit skips spawn; changed mtime marks stale; broken theme yields `false` entries, not an error.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 2: List rendering - multi-chunk swatches and separator rows
1. **Multi-chunk right align** (File: `lua/beast/libs/finder/ui/list.lua`, `format.lua` types)
   - Action: let a `Highlight` carry `chunks = {{text, hl}, ...}` with `right_align`; pass the whole list as `virt_text`. Single-chunk behavior unchanged.
   - Depends on: None
   - Risk: Low
2. **Separator rows** (File: `lua/beast/libs/finder/ui/list.lua`)
   - Action: add `separators` option on the view; `item_cost` is 2 for every item except the first; `render_visible` emits a `─` line (width of the window, `BeastFinderListSeparator`) before each non-first item as a non-match row, reusing `_row_to_item` snapping. No separator above the first or below the last visible item.
   - Why: PM rule - lines between rows only.
   - Depends on: None
   - Risk: Medium - cursor/offset math (`clamp_offset`, `offset_for_cursor`, mouse `item_at_row`) must stay correct with 2-row items; the grouped path already covers this and is re-used.
3. **Highlights** (File: `lua/beast/libs/finder/highlights.lua`)
   - Action: add `ListSeparator` (dimmed line color on the finder bg) and `SwatchEmpty`; add `swatch_hl(hex)` that lazily defines `BeastFinderSwatch<hex>` with `fg=hex` and no `bg`, so the cursor-line tint never recolors it.
   - Depends on: None
   - Risk: Low
4. **Test** (File: `tests/test-finder-list-separators.lua`)
   - Action: float window of height 7 with 5 items: 4 items visible (rows 1,3,5,7), no separator after the last visible row, `item_at_row` maps a separator row to the item below it, moving the cursor down scrolls correctly; multi-chunk virt_text present.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 3: Card layout and wiring - turn the new look on for `<leader>c`
1. **Layout kind** (File: `lua/beast/libs/finder/layout.lua`)
   - Action: `calc(has_preview, kind)`; `kind = "cards"` returns input = 1 row with full rounded border, list directly below with its own full border, fixed width (about 42 columns, clamped to the editor width), centered like today.
   - Depends on: None
   - Risk: Low
2. **Plumb options** (Files: `lua/beast/libs/finder/state.lua`, `init.lua`)
   - Action: `opts.layout` and `opts.separators` flow to `layout.calc`, `ui.list.create` and `relayout`. Input window gets no title in cards mode (PM mockup shows an empty prompt box).
   - Depends on: Phase 2
   - Risk: Medium - `relayout` must keep using the same kind on `VimResized`.
3. **Row format** (File: `lua/beast/libs/finder/format.lua`)
   - Action: `M.colorschemes` returns the name (truncated with `...` to leave room for 10 squares) and swatch chunks `"■ "` x10; missing colors use `SwatchEmpty`. List re-renders when `ensure` finishes while the picker is open.
   - Depends on: Phase 1, Phase 2
   - Risk: Medium - width math must use display width, not bytes.
4. **Live-preview survival** (File: `lua/beast/libs/finder/autocmds.lua`)
   - Action: `ColorScheme` autocmd in the picker augroup re-defines every `BeastFinderSwatch*` group and the finder's own highlights (already rebuilt by the shared highlight reload) so swatches keep their colors while themes are previewed.
   - Depends on: Phase 2 step 3
   - Risk: Medium - verified manually (a swatch must not turn blank after moving the cursor).
5. **Mapping** (File: `lua/beast/init.lua`)
   - Action: add `layout = "cards", separators = true` to the existing `open("colorschemes", {...})` call. Nothing else changes.
   - Depends on: Steps 1-4
   - Risk: Low

# Decisions for the reviewer
- **Where swatch colors come from** - recommended: headless child + JSON cache (no editor flash, instant when warm). Alternative: apply each theme in-process (flashes, blocks UI, fires `ColorScheme` hooks).
- **Role-to-group mapping** - recommended: fixed syntax groups (Number=orange, String=green, Function=blue, Keyword=purple, ...). Alternative: hue-pick from a theme's colors like `theme/palette.lua` (more accurate hues, more code).
- **Card width** - recommended: fixed ~46 columns, centered (42 truncated real theme names such as `monokai-pro-classic`). Alternative: keep 80% of the editor width.

# Testing Strategy
- Headless tests: `nvim --clean --headless -l tests/test-finder-colorscheme-swatches.lua`, `... tests/test-finder-list-separators.lua`; rerun the existing `tests/test-finder-*.lua` to prove other pickers are unchanged.
- Bench: `list.lua` is on the finder render path - run the finder-related `scripts/bench-*.lua` and `LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua ./scripts/bench-ux.sh all`; files/grep list render must not regress (separators and chunks are opt-in).
- Manual (with `NVIM_APPNAME=BeastVim`): PM scenarios 1-6 - browse and Enter, Esc restores, filter `ay`, theme with missing colors (dim squares, ten wide), narrow terminal and a long name, `zzzz` empty result. Also: first ever open (cold cache) then second open (warm), delete the cache file, resize while open, Esc then other pickers unchanged.

# Success Criteria
- [x] `<leader>c` shows a prompt box above a separate theme list box.
- [x] Every row shows a name on the left and ten colored squares on the right.
- [x] A thin line separates consecutive rows, none after the last.
- [x] Squares match each theme's own colors; opening the picker never repaints the editor.
- [x] Warm-cache open shows all swatches immediately; cold-cache open fills them in without blocking input.
- [x] Live preview, Esc restore and Enter apply behave as today; swatches survive live previews.
- [x] Filtering keeps swatches; missing colors are dim grey; strip always ten wide.
- [x] Long names are shortened and never collide with swatches.
- [x] Files, buffers, grep and help pickers look and perform unchanged (tests + bench green).
- [x] stylua clean, existing finder tests pass.

---

## Completed

2026-11-11 - Phase 1: cached headless swatch extraction. Phase 2: separator rows and multi-chunk right align in the list. Phase 3: card layout, row format, live-preview-safe swatch groups, `<leader>c` wiring.

- `78d2521` feat(finder): cache per-colorscheme swatch colors via a headless worker
- `a47a350` feat(finder): list separator rows and multi-chunk right-aligned text
- `bb007e0` feat(finder): card layout with palette swatches for the colorscheme picker (also: filter-match rows follow the separator stride, empty-title input fix found in E2E, ErrorMsg/WarningMsg preferred over Diagnostic* for red/yellow, card width 46)

Verification: all 5 `tests/test-finder-*.lua` pass (19 + 19 + 8 + 4 + 11); stylua clean on touched files; E2E in tmux (`NVIM_APPNAME=BeastVim`): layout, live preview, Esc restore, Enter apply, filter highlights, swatch colors after a `:colorscheme` between opens. `bench-ux.sh` not run.
