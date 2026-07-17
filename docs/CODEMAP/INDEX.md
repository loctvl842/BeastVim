<!-- Generated: 2026-07-17 | Files scanned: 22 | Token estimate: ~257 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~39,947 across 269 lua files
- Libraries: 21 (added image) — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, notify, packer, scroll, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-07-17 (image inline viewer is wired eagerly; setup flow now reflects eager notify/toast/image and current lazy trigger set)
