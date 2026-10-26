---
name: toast-repeat-count
description: Merge identical toasts that repeat while visible into one line with an "xN" count
generated: 2026-10-26
---

# Summary
When the same toast fires again while it is still on screen, no new line is added. The existing toast gains a count (`x2`, `x3`, ... `xN`) and stays visible a little longer.

---

# Problem

A message that repeats (a failed search tried several times, a formatter error on every save, a warning in a loop) stacks one identical line per occurrence. The corner fills with copies of the same sentence, pushing out other toasts and making it hard to tell whether something happened once or ten times.

## Why now
Errors and warnings from Neovim now appear as toasts (including "Pattern not found" and "Search wrapped"). Repeating them is common, so the stack needs to stay readable.

Mockup: `docs/pm-specs/mockups/toast-repeat-count.html`

---

# Target Behavior

STATE 1 - first occurrence (no badge):

```
                                  Pattern not found: foo  Search 󰍉
```

STATE 2 - same message again while visible:

```
                                  Pattern not found: foo x2  Search 󰍉
```

STATE 3 - many repeats:

```
                                  Pattern not found: foo x14  Search 󰍉
```

STATE 4 - different messages stay separate lines:

```
                                    Format failed x3  Conform 
                           Pattern not found: foo x2  Search 󰍉
                                       file saved  BeastVim 
```

---

# Scenarios

## 1 - Same message repeats (happy path)

```
Step 1: User searches for "foo", no match.
  Toast "Pattern not found: foo" appears.

Step 2: User searches for "foo" again within the toast's lifetime.
  The same toast now reads "Pattern not found: foo x2". No new line.

Step 3: User keeps going.
  The count climbs: x3, x4 ... and the toast stays on screen while repeats keep coming.

Step 4: User stops.
  After the usual display time (counted from the last repeat) the toast fades out.

Step 5: User searches "foo" again later.
  A fresh toast appears with no count.
```

## 2 - Different messages

```
Step 1: "Format failed" appears, then "file saved", then "Format failed" again.
  Two lines: "Format failed x2" and "file saved". The repeat merged into the first line
  even though another toast arrived in between.
```

## 3 - Same text, different level or title

```
Step 1: "Done" with title "Build", then "Done" with title "Test".
  Two separate toasts, no count.
```

## 4 - Sticky toasts (edge case)

```
Step 1: A toast that does not auto-dismiss (progress, loading) repeats.
  It is not merged; it keeps its own behavior (in-place updates).
```

## 5 - Very many repeats

```
Step 1: Same message fires 250 times.
  Count shows x99+ from the 100th onward.
```

---

# Behavior Rules

- Two toasts are "the same" when text, level and title are identical.
- Matching looks at every visible toast, not only the newest.
- A repeat adds the count after the message, before the title, in the accent color. The first occurrence shows no count.
- A repeat restarts the display timer; the toast disappears the usual time after its last repeat.
- The count resets once the toast has disappeared.
- The count caps at `x99+`.
- Toasts that never auto-dismiss are never merged.
- The existing LSP progress toasts keep their current `(N)` style and behavior.
- The toast width grows to fit the count.

---

# Success Criteria

- [ ] Firing the same toast twice shows one line ending in `x2`.
- [ ] Each further repeat increases the count.
- [ ] A repeat while other toasts are visible merges into the matching one.
- [ ] A repeat restarts the display time.
- [ ] Different text, level or title are separate lines.
- [ ] After a toast disappears, the same message starts again with no count.
- [ ] 100 or more repeats show `x99+`.
- [ ] Sticky and progress toasts are unchanged.

---

# Out of Scope

- Changing the LSP progress count style from `(N)` to `xN` (left as is).
- A history of how many times a message ever appeared (this is about visible toasts only).
- Merging messages that differ slightly (for example different file names).
