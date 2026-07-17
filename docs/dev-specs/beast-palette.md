---
name: beast-palette
description: "Beast Palette — Theme-Extracted Color Socket"
generated: 2026-05-01
---

# Summary

Create a shared `Beast.Palette` module that extracts a canonical set of colors (accent1–6, dimmed1–5, background, text, dark1–2) from the currently applied Neovim colorscheme using `Util.colors.inspect`. All Beast libs will reference this palette for custom highlights instead of hardcoding hex values or relying solely on `link`. This makes Beast's UI consistent across any colorscheme.

# Requirements

- Palette shape matches monokai-pro structure: `dark2`, `dark1`, `background`, `text`, `accent1`–`accent6`, `dimmed1`–`dimmed5`
- Colors extracted from standard highlight groups (DiagnosticError, String, Normal, etc.) via `Util.colors.inspect`
- Sane fallback defaults if a highlight group is missing (e.g., in a minimal colorscheme)
- Palette refreshes on `ColorScheme` autocmd so theme switching works
- Libraries can read `Palette.accent1` etc. at any time
- Replaces the ad-hoc `bars/palette.lua` pattern with a centralized solution

# Research

### Repo Search
- Searched for: `palette`, `Util.theme`, `Util.colors.inspect`
- Found: `lua/beast/plugins/bars/palette.lua` — does theme extraction but is heirline-specific. Uses `Util.theme.inspect` (which appears to be an alias for `Util.colors.inspect` but the module `util/theme.lua` doesn't exist — likely a stale reference).
- Reuse opportunity: **Yes** — the extraction logic in `bars/palette.lua` is the exact pattern we want to generalize. The mapping of highlight groups → palette fields can be lifted directly.

### Package Search
- Searched Neovim ecosystem: color palette extraction plugins
- Found: No standalone palette extraction library. Colorscheme plugins (monokai-pro, tokyonight, catppuccin) define their own palettes internally but don't expose a universal extraction API.
- Decision: **Build** — we already have `Util.colors.inspect`; we just need to wire it into a canonical palette shape.

# Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/palette.lua` | **Create** | Central palette module with extraction + refresh |
| `lua/beast/init.lua` | **Modify** | Register `_G.Palette` and hook ColorScheme autocmd |
| `lua/beast/libs/*/highlights.lua` | **Modify (later)** | Migrate hardcoded values to use Palette (Phase 2) |

# Implementation Phases

### Phase 1: Core Palette Module — Single source of truth for theme colors

1. **Create `lua/beast/palette.lua`** (File: `lua/beast/palette.lua`)
   - Action: Define `Beast.Palette` type with all fields (dark2, dark1, background, text, accent1–6, dimmed1–5). Implement `M.get()` that extracts from highlight groups using `Util.colors.inspect`. Provide hardcoded fallback defaults. Add `M.refresh()` to re-extract.
   - Why: Centralizes color extraction; any lib can `require("beast.palette").get()`
   - Depends on: None
   - Risk: Low

   Extraction mapping (from bars/palette.lua pattern):
   ```
   dark2       ← inspect("StatusLine").bg
   dark1       ← inspect("CursorLine").bg
   background  ← inspect("Normal").bg
   text        ← inspect("Normal").fg
   accent1     ← inspect("DiagnosticError").fg
   accent2     ← inspect("DiagnosticWarn").fg
   accent3     ← inspect("String").fg
   accent4     ← inspect("DiagnosticOk").fg
   accent5     ← inspect("Structure").fg
   accent6     ← inspect("Boolean").fg
   dimmed1     ← inspect("Pmenu").fg
   dimmed2     ← inspect("WinBar").fg
   dimmed3     ← inspect("Comment").fg
   dimmed4     ← inspect("WinSeparator").fg
   dimmed5     ← inspect("Pmenu").bg
   ```

2. **Register palette globally + ColorScheme autocmd** (File: `lua/beast/init.lua`)
   - Action: Add `_G.Palette = require("beast.palette")` in setup. Create autocmd on `ColorScheme` event that calls `Palette.refresh()` and then reloads all Beast lib highlights (re-calls each lib's `highlights.lua`). This is necessary because highlight definitions depend on Palette values which are only valid after a colorscheme is applied.
   - Why: Palette must be available early and auto-refresh + re-apply all Beast highlights on theme change
   - Depends on: Step 1
   - Risk: Medium — must ensure all libs expose a way to reload highlights

### Phase 2: Migrate Beast Libs to Palette + Highlight Reload

3. **Make each lib's highlights.lua a callable function** (Files: `lua/beast/libs/*/highlights.lua`)
   - Action: Wrap each `highlights.lua` body in a function (e.g. `M.apply()`) so it can be re-invoked on ColorScheme change. Replace hardcoded hex values (e.g. `bg = "#000000"`) with `Palette.get().dark2` or similar. Keep `link`-based highlights as-is.
   - Why: Highlights must reload after colorscheme loads (palette values only valid then). Making them callable enables the ColorScheme autocmd to re-apply all Beast highlights.
   - Depends on: Phase 1
   - Risk: Low

4. **Central highlight reload in ColorScheme autocmd** (File: `lua/beast/init.lua`)
   - Action: In the ColorScheme autocmd handler, after `Palette.refresh()`, call each lib's highlight apply function (e.g. iterate a registry of highlight modules).
   - Why: Ensures all Beast lib highlights are re-computed with fresh palette values whenever the theme changes
   - Depends on: Step 3
   - Risk: Low

# Testing Strategy

- Manual verification: Switch between colorschemes (`:colorscheme tokyonight`, `:colorscheme monokai-pro`) and confirm `Palette.get()` returns different values
- Manual verification: Open Beast libs (explorer, confirm, key) and verify visual consistency
- Manual verification: `:lua vim.print(Palette.get())` shows all fields populated

# Risks & Mitigations

- **Risk**: Some minimal colorschemes don't define all expected highlight groups → **Mitigation**: Hardcoded fallback defaults for every field; `inspect()` already returns nil gracefully
- **Risk**: `ColorScheme` autocmd fires before highlights are fully applied → **Mitigation**: Wrap refresh in `vim.schedule` to defer one tick
- **Risk**: Stale references if libs cache palette values at require time → **Mitigation**: Document that libs must call `Palette.get()` at render time, not cache at load time
- **Risk**: Highlights defined before colorscheme loads show wrong colors → **Mitigation**: All Beast highlights are (re)applied in the ColorScheme autocmd, guaranteeing they always use fresh palette values

# Success Criteria

- [ ] `Palette.get()` returns a complete table with all 15 fields
- [ ] Values change when colorscheme changes

- [ ] Beast lib backdrop colors are theme-aware (not hardcoded `#000000`)
- [ ] Switching colorscheme re-applies all Beast highlights with updated palette
- [ ] No visual regression in existing UI components

# ADR Required

This dev spec involves architectural decisions that should be documented as ADRs before or during implementation:
- Introduction of a shared `Beast.Palette` as the canonical color source for all libs
- Standardized highlight group → palette field mapping
