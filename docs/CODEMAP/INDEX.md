<!-- Generated: 2026-08-09 | Files scanned: 25 | Token estimate: ~330 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~42,150 across 279 lua files
- Libraries: 24 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, input, key, lsp, mason, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-08-09 (new `input` lib replaces native `vim.ui.input`: cursor-anchored positioning with above/below flip, centered near-top fallback for non-buffer contexts, and full `completion`/`highlight` parity — eagerly wired since nothing `require()`s it directly for a lazy trigger to hang off)
