---
name: indent-scope
description: Highlight indentation scope in the editor
generated: 2026-07-17
---

# Summary

Indent scope highlighting shows the current logical block around the cursor. It should track the active scope, update after movement, and keep the display lightweight.

---

# Target Behavior

- The current scope is visually indicated in the gutter/body.
- Scope detection can use tree-sitter first and fall back to indent rules.
- The highlight updates as the cursor moves.
- The feature can be turned on or off through config.

---

# Scenarios

## 1 — Cursor inside a block

```
Step 1: Move into a function or loop body.
  The active scope becomes visible.
Step 2: Move within the same block.
  The scope stays stable.
```

## 2 — Cursor changes scope

```
Step 1: Move into a nested block.
  The highlight updates to the new scope.
Step 2: Move out again.
  The previous scope clears.
```

## 3 — Tree-sitter unavailable

```
Step 1: A parser is missing or disabled.
  Indent-based detection is used instead.
Step 2: The UI still shows the current scope.
  The feature remains useful.
```

---

# Behavior Rules

- Scope highlighting should follow the visible cursor position.
- Tree-sitter is preferred when available.
- The feature should avoid unnecessary redraw work.
- A missing parser should not break the UI.

---

# Success Criteria

- [ ] The current scope is visibly highlighted.
- [ ] Tree-sitter can drive scope detection when available.
- [ ] Indent-based fallback still works.
- [ ] Cursor movement updates the scope cleanly.
