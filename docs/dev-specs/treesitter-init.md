---
name: treesitter-init
description: "Treesitter Library"
generated: 2026-05-13
---

# Dev Spec: Treesitter Library

## Summary

Build a `beast/libs/treesitter/` library that wraps Neovim 0.12's builtin tree-sitter support into a thin configuration layer. The library enables highlighting + folding per-filetype via `vim.treesitter.start()` and `vim.treesitter.foldexpr()`, manages parser installation declaratively (via the builtin `:TSInstall` / `vim.treesitter.install` API), and provides a scope-detection utility that other libs (e.g. indent) can consume. **No dependency on nvim-treesitter plugin.**

## Requirements

- Enable tree-sitter highlighting for all buffers with an available parser (opt-in per filetype or blanket enable)
- Enable tree-sitter folding (`foldmethod=expr`, `foldexpr=v:lua.vim.treesitter.foldexpr()`) as configurable default
- Declarative `ensure_installed` list — parsers are installed on first use if missing (non-blocking, async)
- Expose `treesitter.scope(bufnr, pos)` utility: returns the innermost scope node (function/if/for/loop/class) at a position — usable by the indent library for scope highlighting
- Provide a `:checkhealth` section confirming parser availability for configured filetypes
- Configurable: `ensure_installed`, `highlight.enable`, `fold.enable`, `scope_types` (node types considered "scope")
- Follow BeastVim library conventions (§ Config Pattern, § State Ownership)

## Out of Scope

- Indentation via treesitter (handled by `beast/libs/indent/` once scope is available)
- Custom query files / textobjects (future spec)
- Incremental selection
- nvim-treesitter plugin compatibility layer
- Playground / inspector UI

## Research

### Repo Search

- Searched for: `treesitter`, `tree_sitter`, `vim.treesitter`, `TSInstall`
- Found:
  - `lua/beast/libs/packer/test.lua` — references `nvim-treesitter` as a test plugin spec (not production)
  - `docs/dev-specs/indent-init.md` — Phase 2 describes scope detection via `vim.treesitter.get_parser()` and `:named_node_for_range()` — **not yet implemented**
  - No existing `beast/libs/treesitter/` directory
- Reuse opportunity: The scope detection planned in indent's Phase 2 should live in this new treesitter lib. Indent will `require("beast.libs.treesitter").scope()` instead of implementing its own.

### Package Search

- Searched: Neovim 0.12 native APIs
  - `vim.treesitter.start(bufnr, lang)` — enables highlighting for a buffer
  - `vim.treesitter.stop(bufnr)` — disables highlighting
  - `vim.treesitter.foldexpr()` — fold expression
  - `vim.treesitter.get_parser(bufnr, lang)` — get/create parser
  - `vim.treesitter.get_node({ bufnr, pos })` — node at position
  - `vim.treesitter.language.get_filetypes(lang)` / `vim.treesitter.language.get_lang(ft)` — ft↔lang mapping
  - `:TSInstall <lang>` — builtin parser installation (Neovim 0.12)
- Decision: **Use native** — all required APIs are builtin in Neovim 0.12. Zero plugins needed.

### nvim-treesitter Comparison (Why It's Deprecated)

| What nvim-treesitter provided | Neovim 0.12 builtin equivalent |
|---|---|
| Parser download + compile | `:TSInstall` / `vim.treesitter.install` |
| `highlight = { enable = true }` | `vim.treesitter.start()` (per-buf) |
| `indent = { enable = true }` | `vim.bo.indentexpr = "v:lua.vim.treesitter.foldexpr()"` |
| Fold queries | `vim.treesitter.foldexpr()` |
| Query file shipping (highlights, injections) | Bundled in Neovim runtime |
| Module system (playground, textobjects) | Separate plugins / native APIs |

The plugin was archived because Neovim absorbed its core features. What remains is:
1. Query files for niche languages (now in nvim runtime or community repos)
2. `indentexpr` (experimental, upstreamed)
3. Module orchestration — replaced by simple `FileType` autocmds

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/treesitter/init.lua` | Create | Public API: `setup(opts)`, `enable()`, `disable()`, `scope(bufnr, pos)` |
| `lua/beast/libs/treesitter/config.lua` | Create | Defaults, live cfg, `setup(opts)` (§ Config Pattern) |
| `lua/beast/libs/treesitter/scope.lua` | Create | Scope detection: walk up tree to scope-defining node |
| `lua/beast/libs/treesitter/health.lua` | Create | `:checkhealth` — verify parsers for `ensure_installed` list |
| `lua/beast/init.lua` | Modify | Add `packer.lazy("beast.libs.treesitter", ...)` |

## Implementation Phases

### Phase 1: Highlight + Fold — Minimum viable builtin treesitter config

1. **Create `config.lua`** (File: `lua/beast/libs/treesitter/config.lua`)
   - Action: Define defaults: `ensure_installed = {}`, `highlight = { enable = true }`, `fold = { enable = false }`, `scope_types` (default list of scope node types). Implement `setup(opts)` merging into live `cfg`.
   - Why: Foundation — all other modules read config
   - Depends on: None
   - Risk: Low

2. **Create `init.lua`** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: Implement `setup(opts)` → calls `config.setup(opts)`. Implement `enable()`:
     - Register `FileType` autocmd that calls `vim.treesitter.start()` on buffers where a parser is available (`pcall(vim.treesitter.get_parser, bufnr)` as probe).
     - If `config.cfg.fold.enable`, set `foldmethod=expr` + `foldexpr` on the window.
     - For `ensure_installed`: on `FileType`, if lang has no parser, trigger async install via `vim.treesitter.install` (or shell out to `tree-sitter` CLI if API not yet stable).
   - Implement `disable()`: remove autocmd, call `vim.treesitter.stop()` on active buffers.
   - Why: Core functionality — replaces entire nvim-treesitter highlight/fold setup
   - Depends on: Step 1
   - Risk: Medium (ensure_installed async flow depends on Neovim 0.12 API stability)

3. **Wire into BeastVim setup** (File: `lua/beast/init.lua`)
   - Action: Add `packer.lazy("beast.libs.treesitter", { event = "FileType", defer = true, setup = ... })` with config from `cfg.treesitter`.
   - Why: Lazy-load on first buffer with a filetype
   - Depends on: Step 2
   - Risk: Low

### Phase 2: Scope detection — Utility for indent + future consumers

1. **Create `scope.lua`** (File: `lua/beast/libs/treesitter/scope.lua`)
   - Action: Implement `M.get(bufnr, pos)`:
     - `vim.treesitter.get_node({ bufnr = bufnr, pos = pos })`
     - Walk up via `:parent()` until node type is in `config.cfg.scope_types`
     - Return `{ node = node, range = { start_row, end_row }, indent = indent_level }` or `nil`
   - Cache last result per window; invalidate on `CursorMoved` if node identity changed.
   - Why: Shared scope detection — indent lib Phase 2 and future textobjects consume this
   - Depends on: Phase 1 complete
   - Risk: Medium (language coverage — scope_types may need per-language overrides)

2. **Expose scope via init.lua** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: Add `M.scope(bufnr, pos)` that delegates to `scope.get()`. This is the public API other libs call.
   - Why: Clean API boundary — consumers don't need to know about scope.lua internals
   - Depends on: Step 1
   - Risk: Low

### Phase 3: Health check — Verify parser availability

1. **Create `health.lua`** (File: `lua/beast/libs/treesitter/health.lua`)
   - Action: Implement standard `:checkhealth beast.libs.treesitter` module:
     - Report Neovim version ≥ 0.12
     - For each lang in `ensure_installed`: check if parser is loadable
     - Report highlight status (enabled/disabled)
     - Report fold status
   - Why: Discoverability — user can verify their setup works
   - Depends on: Phase 1
   - Risk: Low

## Testing Strategy

- Unit tests: None initially (consistent with existing libs). Manual verification.
- Bench: Not applicable — treesitter highlighting is managed by Neovim core, not our code. The scope detection in Phase 2 should be `< 50 µs` per call (single tree walk).
- Manual verification:
  1. Open a Lua file → syntax highlighting via treesitter (not regex)
  2. `:InspectTree` → shows parsed tree (confirms parser loaded)
  3. Add `"rust"` to `ensure_installed`, open a `.rs` file → parser auto-installs
  4. Set `fold.enable = true` → folds appear at function boundaries
  5. `:checkhealth beast.libs.treesitter` → all green

## Risks & Mitigations

- **Risk**: `vim.treesitter.install` API may not be stable/public in Neovim 0.12 release → **Mitigation**: Fall back to shelling out `tree-sitter parse` + manual `.so` placement, or keep `:TSInstall` from the rewritten nvim-treesitter as an optional dep for install-only.
- **Risk**: Some filetypes have no builtin parser (e.g. niche DSLs) → **Mitigation**: `pcall` probe before `vim.treesitter.start()`; graceful no-op if parser unavailable.
- **Risk**: Scope detection `scope_types` list may not cover all languages → **Mitigation**: Start with a conservative list (`function`, `method`, `if_statement`, `for_statement`, `while_statement`, `class_definition`, `module`). Allow per-language overrides in config.

## Success Criteria

- [ ] Tree-sitter highlighting active on Lua, Python, TypeScript, Rust files without nvim-treesitter plugin
- [ ] `ensure_installed` parsers are available after first `FileType` trigger
- [ ] `scope()` returns correct scope node for cursor position in a Lua file
- [ ] `:checkhealth beast.libs.treesitter` reports all configured parsers as OK
- [ ] No `nvim-treesitter` in plugin list — fully native
- [ ] Codemap regenerated and committed alongside

## ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs once committed:

- Decision to drop nvim-treesitter plugin entirely in favour of Neovim 0.12 builtin APIs
- Scope detection lives in `beast/libs/treesitter/scope.lua` (shared utility) rather than inline in indent lib — establishes treesitter lib as the single owner of parser/tree interactions
