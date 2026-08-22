<!-- Generated: 2026-08-09 | Files scanned: 26 | Token estimate: ~340 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~42,850 across 292 lua files
- Libraries: 25 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, input, key, lsp, mason, notify, packer, scroll, select, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-08-09 (new `select` lib replaces native `vim.ui.select`: themed search-filterable picker with bullet marker, dynamic list resizing, empty state, native footer/footer_pos hint row, and opt-in format_tag/footer_hints extensions — eagerly wired same as `input`)
