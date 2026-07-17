---
name: treesitter-init
description: Treesitter parser management and auto-install
generated: 2026-05-13
---

> PM Spec: [docs/pm-specs/treesitter-init.md](../pm-specs/treesitter-init.md)

# Summary

Tree-sitter is now handled natively through Neovim. The lib owns parser setup, highlighting, folding, and shared scope lookup for other BeastVim modules.

---

# Context

## Problem

Neovim already ships the core tree-sitter APIs, so the project should not depend on `nvim-treesitter` for basic parsing and highlighting behavior.

### Solution

Use built-in tree-sitter APIs for parser startup, parser installation, and scope lookup, then expose the behavior through a small BeastVim lib.

---

# Research

### Repo Search
- Searched for: `treesitter`, `tree_sitter`, `vim.treesitter`, `TSInstall`
- Found: the live `lua/beast/libs/treesitter/` implementation and the indent scope consumer.
- Reuse opportunity: Yes — share parser and scope logic from one lib.

### Built-in / Existing Lib Check
- Checked: `vim.treesitter.start`, `vim.treesitter.stop`, `vim.treesitter.foldexpr`, `vim.treesitter.get_node`, `vim.treesitter.language.get_lang`
- Found: the required APIs are builtin.
- Decision: **Reuse** — keep the feature native.

---

# Architecture Changes

- `lua/beast/libs/treesitter/init.lua` — public setup, enable/disable, scope.
- `lua/beast/libs/treesitter/config.lua` — config defaults and merge.
- `lua/beast/libs/treesitter/scope.lua` — shared scope lookup helper.
- `lua/beast/libs/treesitter/health.lua` — parser availability checks.

## Implementation Phases

## Phase 1: Native parser setup
1. **Config module** (File: `lua/beast/libs/treesitter/config.lua`)
   - Action: Store the live configuration and defaults.
   - Why: The rest of the lib reads from it.
   - Depends on: None
   - Risk: Low

2. **Core setup** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: Enable highlighting and folding when parsers are available.
   - Why: This is the primary user-facing behavior.
   - Depends on: Step 1
   - Risk: Medium

## Phase 2: Shared scope lookup
1. **Scope helper** (File: `lua/beast/libs/treesitter/scope.lua`)
   - Action: Find the innermost scope node for a buffer position.
   - Why: Other libs can reuse the parser tree work.
   - Depends on: Phase 1
   - Risk: Medium

2. **Public scope API** (File: `lua/beast/libs/treesitter/init.lua`)
   - Action: Expose `scope(bufnr, pos)` from the top-level module.
   - Why: Keep consumers off internal modules.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Health check
1. **Health module** (File: `lua/beast/libs/treesitter/health.lua`)
   - Action: Report parser availability for configured filetypes.
   - Why: Users need a simple validation path.
   - Depends on: Phase 1
   - Risk: Low

# Testing Strategy

- Manual: open supported filetypes, confirm highlighting and folding.
- Manual: ask for scope at a cursor position and confirm it returns a useful node.

# Success Criteria

- [x] Highlighting works without nvim-treesitter.
- [x] Folding can be tree-sitter driven.
- [x] Missing parsers can be installed from config.
- [x] Scope lookup is available to consumers.
