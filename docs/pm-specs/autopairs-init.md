---
name: autopairs-init
description: Automatic pairing for brackets and quotes while typing
generated: 2026-07-17
---

# Summary
Autopairs inserts matching closing characters while you type, so brackets and quotes stay balanced with less manual editing. It also makes backspace and enter smarter when your cursor is inside a pair.

---

# Problem

When writing code or Markdown quickly, users spend time manually adding matching `) ] } " ' \`` and fixing misbalanced text. This slows typing and creates avoidable syntax mistakes.

## Why now
This removes constant low-value editing friction and makes everyday typing smoother, especially in code blocks and structured text.

---

# Target Behavior

```
STATE 1 — Default insert behavior:
┌─────────────────────────────────────────┐
│ Cursor before typing:                  │
│   value = |                            │
│ User types: (                          │
│ Result:                                │
│   value = (|)                          │
└─────────────────────────────────────────┘
```

```
STATE 2 — Smart newline inside braces:
┌─────────────────────────────────────────┐
│ Before Enter:                           │
│   if (ok) {|}                           │
│ User presses: Enter                     │
│ Result:                                 │
│   if (ok) {                             │
│     |                                   │
│   }                                     │
└─────────────────────────────────────────┘
```

```
STATE 3 — Markdown fence expansion:
┌─────────────────────────────────────────┐
│ Filetype: markdown                      │
│ User types third backtick after ``      │
│ Result:                                 │
│   ```                                   │
│   |                                     │
│   ```                                   │
└─────────────────────────────────────────┘
```

---

# Scenarios

## 1 — Happy path: pair insertion and navigation

```
Step 1: User enters insert mode in a normal file buffer and types (
  The editor inserts () and places the cursor between them.

Step 2: User types text, then presses )
  If a closing ) is already ahead, the cursor moves over it instead of inserting another.

Step 3: User presses Backspace between ( and )
  Both characters are removed together.
```

## 2 — Edge case: do not pair in sensitive contexts

```
Step 1: User places cursor before a word/character where auto-pairing should be skipped.
  Typing an opener inserts only the typed character.

Step 2: User types inside a quoted/string-like region.
  Auto-pairing is suppressed; literal input is preserved.

Step 3: User continues typing normally outside that context.
  Pairing behavior resumes automatically.
```

## 3 — Cancellation path: temporary global disable

```
Step 1: User triggers the autopairs toggle keybinding.
  Autopairs turns off globally.

Step 2: User types brackets/quotes.
  Only literal typed characters are inserted (no auto-pair behavior).

Step 3: User triggers the toggle again.
  Autopairs turns back on and pairing behavior returns immediately.
```

---

# Behavior Rules

- Opening characters can auto-insert a matching closer with the cursor placed in the middle.
- If the next character is already the expected closer, typing the closer key jumps over it.
- Smart backspace removes both sides of a pair only when the cursor is exactly between them.
- Smart enter expands paired braces/brackets into a multi-line block with the cursor on the inner line.
- Markdown triple-backtick expansion only applies in Markdown buffers.
- Pairing can be disabled per buffer or globally, and disabled mode always inserts literal typed characters.

---

# Success Criteria

- [x] Typing openers like `(`, `{`, `[`, `"`, `'`, and `` ` `` in active contexts inserts balanced pairs with cursor-in-middle.
- [x] Pressing backspace or enter between a valid pair behaves as smart pair-aware editing, not plain single-character editing.
- [x] Users can toggle autopairs off and on and immediately see literal-vs-smart behavior change.
- [x] Markdown users can create fenced code blocks faster via backtick expansion behavior.

---

# Out of Scope

- Context-specific custom pair sets per language (beyond the built-in behavior) are not included in this spec.
- Advanced wrap-around selection workflows are deferred to a future follow-up feature.
