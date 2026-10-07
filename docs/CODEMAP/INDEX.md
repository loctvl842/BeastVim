<!-- Generated: 2026-10-08 | Files scanned: 30 | Token estimate: ~324 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~43,364 across 298 lua files
- Libraries: 25 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, input, key, lsp, mason, notify, packer, scroll, select, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Colorschemes: repo-root colors/ (monokai-pro + classic/light/machine/octagon/ristretto/spectrum)
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-10-08 (theme split into per-kind palette sources + `colors/` filters; indent scope handles python/wrapped headers and comments; statuscolumn no longer overrides expr folds; finder colorschemes grouped beastvim > builtin > plugin)
