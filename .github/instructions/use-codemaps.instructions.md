---
description: "Use when answering questions about project structure, architecture, code navigation, where to find things, how components connect, or when starting implementation work. Read codemaps first to orient before scanning code."
---

# Use Codemaps for Context

Before scanning the codebase to answer architecture or navigation questions, check if `docs/CODEMAPS/INDEX.md` exists. If it does:

1. Read `docs/CODEMAPS/INDEX.md` first to get the project overview
2. Check the `<!-- Generated: YYYY-MM-DD ... -->` header date — if older than 7 days, warn the user: "Codemaps are stale (last updated DATE). Run `/tec-update-codemaps` to refresh them."
3. Read the relevant codemap file (backend.md, frontend.md, data.md, etc.) based on the question
4. Use the codemap as your starting point — it has file paths, call chains, and dependency info
5. Only scan actual source files if the codemap doesn't have enough detail

If `docs/CODEMAPS/` does not exist, suggest running `/tec-update-codemaps` before proceeding, but don't block the user's question.

This saves time vs. searching the entire codebase from scratch.
