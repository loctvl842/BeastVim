<!-- Generated: 2026-09-05 | Files scanned: 27 | Token estimate: ~365 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~43,060 across 293 lua files
- Libraries: 25 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, input, key, lsp, mason, notify, packer, scroll, select, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-09-05 (explorer's active-file indicator now layers a configurable `┃` left-gutter marker glyph — `config.icon.active_file`, `BeastExplorerActiveFile` — on top of the existing `BeastExplorerActiveFileBg` row tint, instead of replacing it; plus prior: clipboard copy/cut marker switched from an inline `(copy)`/`(cut)` name suffix to a right-aligned badge glyph — `config.icon.clip`)
