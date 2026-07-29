<!-- Generated: 2026-07-28 | Files scanned: 24 | Token estimate: ~270 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~40,382 across 271 lua files
- Libraries: 22 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-07-28 (session restores explorer tree state: root, expanded folders, focus)
