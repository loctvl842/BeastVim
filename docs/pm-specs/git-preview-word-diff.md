---
name: git-preview-word-diff
description: Emphasize the exact changed words inside the removed and added lines of the hunk preview
generated: 2026-11-14
---

# Summary
When a hunk preview shows a line that was edited, the exact words that changed get a stronger background than the rest of the line. GitHub and GitLab do the same, so the eye lands on the real edit instead of re-reading two nearly identical lines.

---

# Problem

Editing one line produces a removed line and an added line that are almost the same. Today the whole removed line is tinted red and the whole added line is tinted green, with nothing marking which part differs. To find the change the user has to compare the two lines word by word. Longer lines make this slower and error-prone.

## Why now
The preview is now the place users check what is still unstaged versus staged. Spotting the real edit at a glance is the main reason to open it.

---

# Target Behavior

Current:

```
┌──────────────────────────────────────────────────────┐
│ 401 -    if not confirmed then                       │  whole line: soft red
│ 401 +    if not confirmed and vim.g.colors_name ~= original then │  whole line: soft green
└──────────────────────────────────────────────────────┘
```

After:

```
STATE 1 - one edited line (insertion):
┌──────────────────────────────────────────────────────┐
│ 401 -    if not confirmed then                       │  soft red, nothing stronger
│ 401 +    if not confirmed [and vim.g.colors_name ~= original ]then │
└──────────────────────────────────────────────────────┘
          [ ] = stronger green background on only the new words

─────────────────────────────────────────
STATE 2 - one word replaced:
│ 12 -   local count = [old_name](...)  │  stronger red on "old_name"
│ 12 +   local count = [new_name](...)  │  stronger green on "new_name"

─────────────────────────────────────────
STATE 3 - lines that are completely different:
│ 30 -   foo(a, b)                      │  soft red only
│ 30 +   return bar                     │  soft green only
  (too little in common: no stronger highlight, avoids a noisy striped look)

─────────────────────────────────────────
STATE 4 - pure additions or pure deletions:
│ 55 +   local x = 1                    │  soft green only, no stronger highlight
```

---

# Scenarios

## 1 - Words added to a line
```
Step 1: Edit a line by appending "and vim.g.colors_name ~= original" before "then".
Step 2: Open the hunk preview on that line.
  The removed line is soft red. The added line is soft green,
  and only "and vim.g.colors_name ~= original " has a stronger green background.
```

## 2 - Word replaced
```
Step 1: Rename one identifier on a line.
Step 2: Open the preview.
  Only the old name is stronger red, only the new name is stronger green.
```

## 3 - Staged, then edited again
```
Step 1: Stage a change, then edit the same line further.
Step 2: Open the preview.
  The comparison is staged text vs your current text, and the stronger
  highlight marks only what changed since staging.
```

## 4 - Several lines changed in one hunk
```
Step 1: Edit three consecutive lines.
Step 2: Open the preview.
  Each removed line is paired with the added line at the same position,
  and each pair gets its own stronger highlights.
```

## 5 - Unequal line counts (edge case)
```
Step 1: Replace 2 lines with 3 lines.
Step 2: Open the preview.
  The first two removed lines pair with the first two added lines and get
  stronger highlights. The extra added line gets soft green only.
```

## 6 - Whole line rewritten (edge case)
```
Step 1: Rewrite a line so almost nothing is shared.
Step 2: Open the preview.
  Soft red and soft green only. No stronger highlight.
```

## 7 - Theme change
```
Step 1: Switch colorscheme while a preview is open or after reopening it.
  The stronger highlights follow the theme and stay clearly visible
  against the soft line colors in both dark and light themes.
```

---

# Behavior Rules

- Stronger highlight applies only to the removed and added lines of a preview, never to unchanged context lines.
- A removed line and an added line are paired in order inside a hunk (first with first, second with second). Unpaired lines get soft highlighting only.
- The stronger highlight covers the differing words, not single characters scattered across the line. Changes are grouped at word level, with whitespace-only changes still marked.
- If a pair shares too little text to be a meaningful edit, skip the stronger highlight for that pair.
- Works the same in the "Staged" preview and the unstaged preview.
- Stronger highlight colors are separate theme-adjustable highlight groups, one for removed and one for added, defaulting to a more saturated version of the existing red and green.
- Syntax coloring of the code is kept; only the background changes.
- Previews of large hunks stay instant. Very long lines may skip the stronger highlight.

---

# Success Criteria

- [ ] An appended phrase is the only stronger-green region on the added line, as in the GitHub screenshot.
- [ ] A replaced word is stronger red on the old line and stronger green on the new line.
- [ ] Fully different lines and pure add/delete lines show soft highlight only.
- [ ] Unchanged context lines are never emphasized.
- [ ] Staged-then-edited lines emphasize only what changed since staging.
- [ ] Emphasis is clearly visible in every bundled colorscheme, dark and light.
- [ ] Opening the preview shows no visible delay on a large hunk.

---

# Out of Scope

- Emphasis in the gutter, sign column, or inline in the main buffer (preview float only).
- Character-level (sub-word) emphasis.
- A user setting to turn emphasis off (can follow if requested).
- Side-by-side diff layout.
