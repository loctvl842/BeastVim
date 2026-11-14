<!-- Generated: 2026-11-14 | Files scanned: 331 | Token estimate: ~258 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~47,789 across 331 lua files
- Libraries: 28 - autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, input, key, lsp, mason, messages, notify, packer, review, scroll, searchcount, select, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Colorschemes: repo-root colors/ (monokai-pro + classic/light/machine/octagon/ristretto/spectrum)
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-11-14
