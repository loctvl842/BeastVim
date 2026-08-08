---
name: finder-auto-select
description: Pre-flight LSP check before opening the finder picker, plus a statusline indicator for the wait
generated: 2026-08-08
---

# Summary

When a jump to definition, references, declaration, or implementation resolves to exactly one location, the editor should jump straight there without ever showing the picker window. A small statusline indicator appears if the check takes long enough to notice, so the user always knows something is happening.

---

# Problem

Today, pressing "go to definition" (or references, declaration, implementation) opens the picker window, then - once it turns out there's only one match - immediately closes it again and jumps. For the common case of a single match, this means the picker window flashes open and shut in a split second. It's visually noisy, and it's also fragile: closing the picker while it's still receiving keyboard input can leave the cursor one column off from where it should land, a bug that's currently unresolved.

There's also a smaller, related gap: today the picker's own loading spinner tells the user "still working" while results stream in. If the picker stops opening for the single-match case, that feedback disappears - so on a slow language server, the user could be left staring at an unchanged screen with no sign that anything is happening.

## Why now

The flicker is a visible rough edge every time someone jumps to a definition, which is one of the most frequent actions in a coding session. Fixing it also removes the conditions that produce the cursor-position bug, instead of trying to patch around it.

---

# Target Behavior

**STATE 1 — Single result, fast (the common case):**

```
Before (cursor in caller):              After (instant jump, no picker ever shown):
┌────────────────────────────┐          ┌────────────────────────────┐
│ 12  local result = foo()    │   gd     │ 45  local function foo()    │
│ 13  print(result)            │  ───►   │ 46    return 42              │
└────────────────────────────┘          └────────────────────────────┘
```

**STATE 2 — Multiple results (unchanged from today):**

```
┌─ References ──────────────────────────┐
│ > foo                                  │
├─────────────────────────────────────────┤
│  lua/foo.lua:12  local result = foo()  │
│  lua/bar.lua:30  return foo() + 1      │
│  lua/baz.lua:8   foo()                 │
└─────────────────────────────────────────┘
```

**STATE 3 — Checking (only visible when the check takes a moment, e.g. a slow language server):**

```
 …editor content unchanged…

──────────────────────────────────────────────────────
 NORMAL   lua/foo.lua   ⠋ Definition…        main   UTF-8
──────────────────────────────────────────────────────
```

The spinner cycles briefly, then either the jump happens (STATE 1's "after") or the picker opens (STATE 2) - the statusline indicator disappears the instant either happens.

**STATE 4 — No results:**

```
 ⚠ beast.finder.lsp: no references found
```

Nothing else appears on screen - no picker, no lingering statusline indicator.

---

# Scenarios

## 1 — Go to definition, single result, fast response

```
Step 1: Cursor is on a function call. User triggers "go to definition."
  Nothing visibly changes yet (the check is effectively instant).

Step 2: The check finds exactly one definition.
  The cursor jumps directly to that location. The picker window is never shown.
```

## 2 — Find references, multiple results

```
Step 1: Cursor is on a symbol used in several places. User triggers "find references."
  The check finds more than one location.

Step 2: The picker opens.
  The user sees the familiar list of references and can browse/select as before.
```

## 3 — Slow language server, single result

```
Step 1: User triggers "go to definition" against a language server that's slow to respond
(e.g. still warming up).
  A statusline indicator appears: "⠋ Definition…"

Step 2: The language server responds with exactly one location.
  The statusline indicator disappears and the cursor jumps directly there. The picker
  is never shown, even though the wait was noticeable.
```

## 4 — Slow language server, multiple results

```
Step 1: User triggers "find references" against a slow language server.
  The statusline shows "⠋ References…"

Step 2: The language server responds with several locations.
  The statusline indicator disappears and the picker opens showing the list.
```

## 5 — No results found

```
Step 1: User triggers "go to definition" on a symbol with no resolvable definition.
  If the check takes a moment, the statusline briefly shows "⠋ Definition…"

Step 2: The check completes with zero results.
  The statusline indicator disappears. A warning notification appears: "no definition found."
  No picker window opens.
```

## 6 — Rapid re-trigger

```
Step 1: User triggers "go to definition," then - before it resolves - moves the cursor
to a different symbol and triggers "go to definition" again.
  The statusline indicator relabels to reflect the newest request ("⠋ Definition…" for
  the new symbol); the first, now-abandoned check has no further effect.

Step 2: The second check resolves.
  The editor behaves as if only the second request had been made - jump or picker,
  per its own result count. Nothing from the first, abandoned request appears.
```

---

# Behavior Rules

- The picker window must never become visible when a jump resolves to exactly one location - not even briefly.
- The statusline indicator only appears while a check is in flight and no picker has opened yet. It disappears the instant any of the following happens: the cursor jumps, the picker opens, or a "not found" warning appears.
- The indicator names the specific action being performed (Definition / References / Declaration / Implementation) rather than a generic label, so it also tells the user what's being searched.
- Triggering a new jump while a previous check is still pending supersedes the previous one; the abandoned check has no visible effect once it eventually resolves.
- Multiple-result and zero-result behavior looks exactly as it does today - only the single-result path changes.

---

# Success Criteria

- [ ] Jumping to a definition/reference/declaration/implementation that resolves to a single location never shows the picker window, even for an instant.
- [ ] Multi-result and zero-result behavior is visually indistinguishable from today.
- [ ] A statusline indicator appears whenever a check is slow enough to notice, and never lingers past the moment it resolves.
- [ ] The cursor no longer lands a column off from the target location on single-result jumps.

---

# Out of Scope

- A general, always-on LSP status indicator in the statusline - this spec only covers the brief pre-jump checking window, not ongoing LSP client/activity status.
- Any change to existing LSP progress toast notifications (e.g. workspace indexing progress) - those continue to work as they do today.
- Applying this pre-flight behavior to non-LSP pickers (files, buffers, live grep, colorschemes, help tags) - none of those currently auto-select a single result, and this spec doesn't add that.
