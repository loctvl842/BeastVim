---
name: lsp-init
description: Native LSP setup, server registration, and diagnostics policy
generated: 2026-06-07
---

> PM Spec: [docs/pm-specs/lsp-init.md](../pm-specs/lsp-init.md)

# Summary

LSP is the native infrastructure layer for registering language servers, attaching them to buffers, and keeping diagnostics and keymaps consistent. It wraps Neovim's built-in LSP APIs without adding a separate framework.

---

# Context

## Problem

The editor needs a single place to handle LSP setup, diagnostics policy, per-server attachment, and LSP keymaps. The current code already does this natively, so the spec should describe the shipped infrastructure rather than the original framework-style plan.

### Solution

Keep LSP as a thin policy layer over `vim.lsp.config`, `vim.lsp.enable`, and `LspAttach`. Server registration, capabilities, diagnostics, and debugging commands should all flow through the same lib.

---

# Research

### Repo Search
- Searched for: `vim.lsp`, `LspAttach`, `on_attach`, `vim.lsp.config`, `vim.lsp.enable`, `register`
- Found: `lua/beast/libs/lsp/*` already implements the current native LSP infrastructure and `lua/beast/util/root.lua` consumes LSP attach state for root detection.
- Reuse opportunity: Yes — reuse the existing LSP modules, diagnostics config, and keymap helpers.

### Built-in / Existing Lib Check
- Checked: `vim.lsp.config`, `vim.lsp.enable`, `LspAttach`, `client:supports_method`, `vim.diagnostic.config`
- Found: Neovim 0.12 already provides the complete LSP lifecycle used here.
- Decision: **Reuse** — the lib is a native policy layer, not a plugin wrapper.

---

# Architecture Changes

- `lua/beast/libs/lsp/init.lua` — public API and server registration.
- `lua/beast/libs/lsp/config.lua` — diagnostics and fold options.
- `lua/beast/libs/lsp/capabilities.lua` — merged capability contributors.
- `lua/beast/libs/lsp/attach.lua` — `LspAttach` dispatcher.
- `lua/beast/libs/lsp/keys.lua` — buffer-local LSP keymaps.
- `lua/beast/libs/lsp/diagnostics.lua` — diagnostic policy setup.
- `lua/beast/libs/lsp/health.lua` — health checks and debugging info.

## Implementation Phases

## Phase 1: Core LSP policy — registration and attach flow
1. **Config and diagnostics** (File: `lua/beast/libs/lsp/config.lua`, `lua/beast/libs/lsp/diagnostics.lua`)
   - Action: Keep diagnostics style and LSP policy defaults in one place.
   - Why: All servers should share the same visual baseline.
   - Depends on: None
   - Risk: Low

2. **Capabilities and attach dispatch** (File: `lua/beast/libs/lsp/capabilities.lua`, `lua/beast/libs/lsp/attach.lua`, `lua/beast/libs/lsp/keys.lua`)
   - Action: Merge capability contributions, dispatch `LspAttach`, and bind server-specific keymaps when supported.
   - Why: This is the core behavior users rely on.
   - Depends on: Step 1
   - Risk: Medium

3. **Public API** (File: `lua/beast/libs/lsp/init.lua`)
   - Action: Expose setup, register, capabilities, add_capabilities, and on_attach.
   - Why: The rest of BeastVim needs a single entry point.
   - Depends on: Step 2
   - Risk: Medium

## Phase 2: Debugging surface — health and inspection
1. **Health checks** (File: `lua/beast/libs/lsp/health.lua`)
   - Action: Report registered servers, attached clients, and capability contributors.
   - Why: LSP setup should be easy to inspect.
   - Depends on: Phase 1
   - Risk: Low

---

# Testing Strategy

- Headless tests: none currently targeted for this lib.
- Bench: none; setup is infrequent rather than hot-path work.
- Manual: open a supported file, confirm a server attaches, inspect diagnostics, and verify LSP keymaps only appear when supported.

# Success Criteria

- [ ] Supported files attach an LSP server automatically.
- [ ] Diagnostics use the configured BeastVim style.
- [ ] LSP actions only appear when the server supports them.
- [ ] The user can inspect registered and attached LSP state.
- [ ] The base library does not require an external LSP framework.
