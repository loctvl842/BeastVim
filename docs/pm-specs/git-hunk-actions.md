---
name: git-hunk-actions
description: Add stage, reset, and unstage hunk actions
generated: 2026-07-17
---

# Summary

The git gutter should support staging, resetting, and unstaging the hunk under the cursor. The UI should also reflect staged changes separately from unstaged ones.

---

# Target Behavior

- A hunk can be staged from the gutter.
- A staged hunk can be unstaged again.
- A hunk can be reset back to the last committed state.
- Staged and unstaged signs are visually distinct.

---

# Scenarios

## 1 — Stage a hunk

```
Step 1: Select a changed hunk.
  Stage it from the gutter.
Step 2: Look again.
  The hunk is now shown as staged.
```

## 2 — Unstage a hunk

```
Step 1: Select a staged hunk.
  Unstage it.
Step 2: Check the buffer.
  It returns to the unstaged state.
```

## 3 — Reset a hunk

```
Step 1: Select a modified hunk.
  Reset it.
Step 2: The buffer updates.
  The changes are removed.
```

---

# Behavior Rules

- Stage and unstage should work from the same hunk context.
- The gutter should distinguish staged from unstaged changes.
- Reset should restore the original content lines.

---

# Success Criteria

- [ ] Stage, unstage, and reset work from the gutter.
- [ ] Staged and unstaged signs are distinct.
- [ ] The diff view stays consistent after actions.
