<!-- Generated: 2026-08-02 | Files scanned: 25 | Token estimate: ~290 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~41,436 across 277 lua files
- Libraries: 22 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-08-02 (treesitter: native `indentexpr` consuming `indents.scm` captures — no core Neovim equivalent existed; gated per-buffer on a compiled indents query being present)
