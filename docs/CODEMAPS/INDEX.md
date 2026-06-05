<!-- Generated: 2026-06-05 | Files scanned: 191 | Token estimate: ~545 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/tec-update-codemaps`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~24,500
- Libraries: 17 (explorer, finder, tabline, notify, toast, key, confirm, packer, buf, statusline, statuscolumn, treesitter, breadcrumb, indent, scroll, git, window) + shared: view.lua, animate.lua
- Shared modules: view.lua, animate.lua (now exposes `M.tween` primitive), util/, palette/
- Last updated: 2026-06-05
