<!-- Generated: 2026-07-31 | Files scanned: 25 | Token estimate: ~280 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~40,847 across 273 lua files
- Libraries: 22 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-07-31 (packer UI: `x` deletes a plugin via `vim.pack.del`, "Deleted" section tracks removals this session)
