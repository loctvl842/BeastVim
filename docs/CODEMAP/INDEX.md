<!-- Generated: 2026-09-04 | Files scanned: 27 | Token estimate: ~365 -->

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
- Last updated: 2026-09-04 (explorer's active-file indicator switched from a `BeastExplorerActiveFile` background tint to a configurable `┃` left-gutter marker glyph — `config.icon.active_file`; plus small prior fixes: create-prompt connector alignment across re-render, root filetype detection)
