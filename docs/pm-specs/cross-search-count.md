---
name: search-count
description: Show "current/total" match count after a search, floating at the end of the matched line and in the statusline
generated: 2026-10-26
---

# Summary
After you search with `/`, the editor shows which match you are on and how many there are in the file (for example `2/3`). The count floats at the end of the matched line and also appears in the statusline, so it stays visible when the line is too long to see its end.

---

# Problem

When you search for a word, you only see the highlighted matches and the cursor jumping. You cannot tell how many matches exist or which one you are on without pressing `n` repeatedly until the cursor wraps back. When the matched line is long, any hint at the end of the line is scrolled out of view.

## Why now
Searching is one of the most common moves in a file. A count turns it from "keep pressing n and guess" into "I am on 2 of 3".

Mockup: `docs/pm-specs/mockups/cross-search-count.html`

---

# Target Behavior

STATE 1 - after pressing Enter on `/local` (cursor was on line 1):

```
  1  local M = {}
  2
  3  function M.setup(opts)
  4    opts = opts or {}
  5    local cfg = vim.tbl_extend("force", defaults, opts)  2/3
  6    return cfg
  7  end
 ...
 main  ▲ 28                  2/3  loctvl842 (4 days ago)  Ln 5, Col 3  Lua  Spaces: 2  UTF-8  NORMAL
 /local
```

- `2/3` floats two columns after the end of the line holding the current match.
- `2/3` also shows in the statusline, left of the git blame segment.
- Only the line with the current match shows a floating count. Other matches stay highlighted but have no count.

---------------------------------------------------------
STATE 2 - match on a very long line (end of line is off screen):

```
  8  -- this generated mapping table is intentionally one huge line so it runs far past the ri
 ...
 main  ▲ 28                  3/3  loctvl842 (4 days ago)  Ln 8, Col 120  Lua  Spaces: 2  UTF-8  NORMAL
```

The floating count is not shown (its line end is off screen). The statusline count is the one to read.

---------------------------------------------------------
STATE 3 - no match:

```
 main  ▲ 28                       loctvl842 (4 days ago)  Ln 5, Col 3  Lua  Spaces: 2  UTF-8  NORMAL
 /zzz

                                                         ┌──────────────────────────────┐
                                                         │ Search                       │
                                                         │ Pattern not found: zzz       │
                                                         └──────────────────────────────┘
```

A toast appears at the bottom right (the normal toast position). No count anywhere.

---------------------------------------------------------
STATE 4 - search wrapped around:

```
                                                         ┌──────────────────────────────┐
                                                         │ Search wrapped               │
                                                         │ Hit BOTTOM, continuing at TOP│
                                                         └──────────────────────────────┘
  1  local M = {}  1/3
```

---

# Scenarios

## 1 - Search and step through matches (happy path)

```
Step 1: File has 3 "local". Cursor on line 1. User types /local and presses Enter.
  Cursor jumps to the next match (line 5). Shows "2/3" at end of line 5 and in the statusline.

Step 2: User presses n.
  Cursor jumps to the third match. Count becomes "3/3". The count on line 5 is gone.

Step 3: User presses n again.
  Search wraps to the first match. Count becomes "1/3". A "Search wrapped" toast appears.

Step 4: User presses N.
  Cursor goes back to the previous match, count updates. Toast notes wrap when it wraps.
```

## 2 - Match on a long line

```
Step 1: User searches for text whose current match sits on a line longer than the window.
  Floating count is not visible because the line end is off screen.

Step 2: User looks at the statusline.
  The same "3/3" is shown there.
```

## 3 - Pattern not found

```
Step 1: User types /zzz and presses Enter.
  Toast "Pattern not found: zzz" at the bottom right. No count in the buffer or statusline.
```

## 4 - Clearing the search

```
Step 1: User presses Esc (or runs :noh) after searching.
  Highlights go away. Floating count and statusline count disappear.
```

## 5 - Very many matches

```
Step 1: File has 12,000 matches. User searches.
  Count shows "1/999+" style: any total above 999 shows as "999+".
  Current index above 999 also shows "999+" (for example "999+/999+").
```

## 6 - Search in a different file or window

```
Step 1: User has a count showing, then switches to another buffer.
  The old count is not shown in the other buffer. The statusline shows no count unless that buffer has its own active search.
```

---

# Behavior Rules

- Format is exactly `current/total`, no brackets, no icon.
- Totals and current index above 999 display as `999+`.
- The count only appears after Enter, not while typing the pattern.
- The floating count is placed two columns after the end of the matched line, with a subtle background so it is readable over any text.
- Only the line with the current match shows the floating count.
- The floating count is hidden when the end of the line is not visible in the window.
- The statusline count sits on the right, left of the git blame segment, and has an accent background so it is easy to spot.
- Clearing the search highlight (`Esc`, `:noh`) removes both counts.
- Starting to edit the text also removes both counts, since the match list is no longer accurate.
- "Pattern not found" and "search wrapped" messages use the standard toast (bottom right), not the command line.
- Counts are per window: each window shows only its own buffer's search state.
- Cursor movement that stays on a match (without `n`/`N`) keeps the count showing the matching index.

---

# Success Criteria

- [ ] After `/local` + Enter on a file with 3 matches, the nearest match shows `2/3` (or `1/3`, `3/3` by position) at the end of its line.
- [ ] The same count appears in the statusline.
- [ ] `n` and `N` update the count and move the floating label to the new line.
- [ ] A match on a long line shows the count in the statusline even though the float is hidden.
- [ ] A pattern with no matches shows a bottom-right toast and no count.
- [ ] Wrapping shows a toast and the count continues correctly.
- [ ] `Esc` / `:noh` clears both counts.
- [ ] Totals above 999 show `999+`.
- [ ] Searching a large file does not make Enter, `n` or `N` feel slower.

---

# Out of Scope

- Live count while typing the pattern (incsearch). Deferred, current ask is after Enter only.
- Pinning the floating count to the window edge for long lines. The statusline covers this case.
- Counts for `*` / `#` and other search-like commands unless they use the same search. To be confirmed in the dev phase.
- Count for substitute (`:s`) or finder/picker results. Different features.
