---
name: lsp-infra-hardening
description: Harden the native LSP infrastructure
generated: 2026-07-17
---

# Summary

The native LSP infrastructure should be reliable and predictable across setup, client attach, and status handling. This keeps the rest of the editor's LSP features stable.

---

# Target Behavior

- LSP setup is consistent.
- Client attach behavior is predictable.
- Status and progress handling remain reliable.
- Existing LSP functionality keeps working.

---

# Scenarios

## 1 — Start an LSP client

```
Step 1: Open a supported file.
  The client attaches correctly.
Step 2: Use LSP features.
  The editor behaves normally.
```

## 2 — Show progress

```
Step 1: The client reports progress.
  The UI can surface it.
Step 2: Continue editing.
  LSP behavior stays stable.
```

## 3 — Reload config

```
Step 1: Refresh LSP setup.
  The infrastructure stays sane.
Step 2: Keep editing.
  No regressions appear.
```

---

# Behavior Rules

- LSP setup should be stable.
- Client attach paths should remain predictable.
- Progress/status handling should remain reliable.

---

# Success Criteria

- [ ] LSP setup remains reliable.
- [ ] Client attach behavior stays predictable.
- [ ] Progress and status continue working.
