<!-- Generated: 2026-06-08 | Files scanned: 197 | Token estimate: ~560 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/tec-update-codemaps`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~25,000
- Libraries: 19 (explorer, finder, tabline, notify, toast, key, confirm, autopairs, packer, buf, statusline, statuscolumn, treesitter, lsp, breadcrumb, indent, scroll, git, window) + shared: view.lua, animate.lua
- Shared modules: view.lua, animate.lua (now exposes `M.tween` primitive), util/, palette/
- Last updated: 2026-06-08
