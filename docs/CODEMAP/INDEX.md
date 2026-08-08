<!-- Generated: 2026-08-08 | Files scanned: 25 | Token estimate: ~300 -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/update-codemap`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~41,690 across 279 lua files
- Libraries: 23 — autopairs, breadcrumb, confirm, explorer, finder, git, image, indent, key, lsp, mason, notify, packer, scroll, session, starter, statuscolumn, statusline, tabline, toast, treesitter, view, window
- Shared modules: view/ (instance + .buf + .win submodules), animate.lua, async.lua, util/, theme/, visibility.lua (global hidden/gitignored state)
- Profiler: lua/beast/profile.lua (per-fn count/total/self stats)
- Last updated: 2026-08-08 (finder: `auto_select` LSP sources now pre-flight before opening the picker — single-result jumps never render a picker window; new `finder/status.lua` + statusline `finder_lsp` component show a checking spinner while the pre-flight request is in flight; multi-result opens reuse the pre-flight's fetched items instead of re-querying the source)
