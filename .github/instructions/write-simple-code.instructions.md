---
description: "Use when writing new code, implementing features, or generating code. Prevents over-engineering and unnecessary complexity."
---

# Write Simple Code

When writing code, follow these rules:

1. **Clarity over cleverness** — if a new team member can't understand it in 30 seconds, it's too complex
2. **No nested ternaries** — use if/else or a lookup instead
3. **Functions under 50 lines** — split longer functions into focused helpers with descriptive names
4. **Max 3 levels of nesting** — use guard clauses and early returns to flatten
5. **No speculative abstractions** — don't build for hypothetical future requirements
6. **Name things fully** — `userProfile` not `usr`, `validationErrors` not `errs`
7. **One responsibility per function** — if you need "and" to describe it, split it
8. **Prefer standard library** — don't write custom code when the language has a built-in
9. **Remove dead code** — don't comment out, delete it. Git remembers.
10. **Match project patterns** — read neighboring code first and follow the same style
