---
name: lsp-init
description: Native LSP setup, server registration, and diagnostics policy
generated: 2026-07-17
---

# Summary

LSP gives BeastVim a built-in way to turn on language servers, keep diagnostics consistent, and manage LSP-related keymaps in one place. It helps future language setups attach cleanly without each one having to solve the same startup work.

---

# Problem

Users need language servers to attach reliably and consistently across filetypes, but the editor should not depend on a separate LSP framework. The configuration and attach flow need to stay centralized so language-specific setups are easy to add later.

## Why now

This gives BeastVim a native LSP base for editing, diagnostics, and future language extensions.

---

# Target Behavior

```
Lua file opens
  → language server attaches
  → diagnostics appear
  → LSP keymaps work
```

```
STATE 1 — Registered server:
  A language server can be enabled from the editor configuration.

STATE 2 — Attached buffer:
  The current file gets LSP diagnostics and LSP actions.

STATE 3 — Multiple servers:
  Different filetypes can use different servers without extra UI setup.

STATE 4 — Debugging:
  The user can inspect which servers are registered and attached.
```

---

# Scenarios

## 1 — Opening a supported file

```
Step 1: The user opens a file type with an LSP server configured.
  The server attaches automatically.

Step 2: The file produces diagnostics.
  The editor shows them with the configured style.
```

## 2 — Using LSP actions

```
Step 1: The user triggers an LSP-related keymap.
  The editor runs the mapped action for the current buffer.

Step 2: The server supports the action.
  The keymap works only where it is valid.
```

## 3 — Checking setup

```
Step 1: The user asks for LSP status.
  The editor shows which servers are registered and attached.

Step 2: The user adjusts configuration.
  Future attachments use the updated settings.
```

---

# Behavior Rules

- LSP should attach through the editor's native LSP system.
- Diagnostics should use a consistent BeastVim style.
- LSP keymaps should only appear where the server supports them.
- The user should be able to inspect current LSP state.
- The base library should not require an external LSP framework.

---

# Success Criteria

- [ ] Supported files attach an LSP server automatically.
- [ ] Diagnostics use the configured BeastVim style.
- [ ] LSP actions only appear when the server supports them.
- [ ] The user can inspect registered and attached LSP state.

---

# Out of Scope

- Per-language server catalogs
- External LSP package managers
- Formatter UI
