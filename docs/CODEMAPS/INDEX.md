<!-- Generated: 2026-06-29 | Files scanned: 255 | Token estimate: ~185 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/tec-update-codemaps`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~35,000 across 246 lua files
- Libraries: 20 (finder gains opt-in engine/) — autopairs, breadcrumb, confirm, explorer, finder, git, indent, key, lsp, notify, packer, scroll, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-06-29
