<!-- Generated: 2026-07-21 | Files scanned: 23 | Token estimate: ~265 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~39,947 across 271 lua files
- Libraries: 22 (added session) — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-07-21 (added session lib — save/restore per project dir + git branch, wired on VimEnter+defer)
