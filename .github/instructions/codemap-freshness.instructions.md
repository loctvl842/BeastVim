---
description: "Use when creating a pull request, preparing a PR, committing changes, pushing code, finishing a feature branch, or starting significant implementation work on an unfamiliar codebase. Ensures codemaps stay fresh before code review."
applyTo: "docs/CODEMAPS/**"
---

# Codemap Freshness Check

## When starting work on a codebase

If `docs/CODEMAPS/` exists, read `docs/CODEMAPS/INDEX.md` first to orient yourself before diving into code. This saves time vs. scanning the project from scratch.

If `docs/CODEMAPS/` does not exist, suggest running `/tec-update-codemaps` before beginning — but don't block the user's request.

## Before creating a pull request or committing significant changes

1. Check if `docs/CODEMAPS/` exists. If not, run the `tec-update-codemaps` skill to generate it.
2. If codemaps exist, check the `<!-- Generated: ... -->` header date in each file.
   - If the date is older than 7 days, or if the current changes touch architecture (new lib, removed lib, new shared module, new dev spec landed), regenerate the affected codemaps with `/tec-update-codemaps`.
3. Stage the updated codemap files alongside the code changes so they are included in the same commit/PR.

Do NOT skip this step — stale codemaps cause confusion for reviewers and future agents.
