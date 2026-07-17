---
name: treesitter-init
description: Manage built-in tree-sitter support
generated: 2026-07-17
---

# Summary

Tree-sitter support should be configured natively through Neovim instead of an external plugin. The library turns highlighting and folding on where parsers are available and can install missing parsers when requested.

---

# Target Behavior

- Built-in tree-sitter highlighting can be enabled per filetype.
- Folding can use tree-sitter as the fold expression source.
- Missing parsers can be installed from a declarative list.
- Scope information is available to other BeastVim libraries.

---

# Scenarios

## 1 — Open a supported file

```
Step 1: Open a file with a parser.
  Tree-sitter highlighting starts.
Step 2: Enable folding.
  Fold behavior follows tree-sitter.
```

## 2 — Missing parser

```
Step 1: Open a file without a parser.
  The library can request installation when configured.
Step 2: Reopen after install.
  The parser is now available.
```

## 3 — Scope lookup

```
Step 1: Ask for scope at a cursor position.
  The innermost relevant node is returned.
Step 2: Use it from another library.
  The call stays lightweight and shared.
```

---

# Behavior Rules

- The library should rely on built-in Neovim APIs.
- Missing parsers should not break the buffer.
- Scope detection should be reusable by other modules.

---

# Success Criteria

- [ ] Highlighting works without nvim-treesitter.
- [ ] Folding can be tree-sitter driven.
- [ ] Missing parsers can be installed from config.
- [ ] Scope lookup is available to consumers.
