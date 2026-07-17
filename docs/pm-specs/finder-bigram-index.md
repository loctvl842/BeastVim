---
name: finder-bigram-index
description: Prefilter live_grep with a persistent bigram index
generated: 2026-07-17
---

# Summary

The finder should prefilter `live_grep` with a persistent bigram index so the first search keystroke can avoid scanning every file. The index should remain correct and only prune candidates, never matches.

---

# Target Behavior

- The index builds in the background on first use.
- Queries are narrowed using literal bigrams from the input.
- The final search still uses ripgrep to verify results.
- The index stays fresh as files change.

---

# Scenarios

## 1 — First search

```
Step 1: Open live grep.
  The index builds lazily.
Step 2: Type a query.
  Candidate files are reduced before ripgrep runs.
```

## 2 — Query with regex characters

```
Step 1: Type a regex-heavy query.
  Literal bigrams are extracted carefully.
Step 2: Run the search.
  Correct results still appear.
```

## 3 — File changes

```
Step 1: Edit files on disk.
  The index receives freshness updates.
Step 2: Search again.
  The candidates stay current.
```

---

# Behavior Rules

- Prefiltering must never cause false negatives.
- Empty or regex-only queries should fall back safely.
- The index should stay bounded in memory.

---

# Success Criteria

- [ ] First search becomes faster on large repos.
- [ ] Search results remain identical to plain ripgrep.
- [ ] The index stays fresh as files change.
