---
name: finder-lsp-exclude-current-position
description: LSP-backed finder sources (definitions, references, declarations, implementations) leave out the occurrence the cursor is already sitting on
generated: 2026-08-09
---

# Summary

When the user asks "go to references," "go to definition," "go to declaration," or "go to implementation," the result list should never include the exact spot the cursor is already sitting on - only the *other* occurrences.

---

# Problem

Today, "find references" on a symbol returns every occurrence, including the one the cursor is currently sitting on. Since the user is already there, that entry is useless - it's not a place to jump to, it's just noise that pads out the list and (in the single-remaining-result case) can force a picker to open when the user would otherwise have jumped straight there.

For example, with the cursor on the first `profile` below:

```lua
if os.getenv("BEAST_PROFILE") == "1" then
    pcall(function()
        local profile = require("beast.profile")
        profile.start()
        local out = os.getenv("BEAST_PROFILE_OUT") or (vim.fn.stdpath("cache") .. "/beast-profile.txt")
        profile.auto_dump_on_quit(out)
    end)
end
```

"find references" currently returns all 3 occurrences of `profile` - including the one under the cursor. The user only wants to see the other 2.

## Why now

This compounds with the existing single-result auto-jump behavior: a symbol with exactly 2 occurrences (the current one, plus one other) today shows a picker with 2 entries, when it should just jump straight to the one real result - the same way a normal single-reference symbol already does.

---

# Target Behavior

**STATE 1 - Multiple other occurrences remain (picker as before, minus the self-entry):**

```
┌─ References ──────────────────────────────────────┐
│ > profile                                          │
├─────────────────────────────────────────────────────┤
│  init.lua:4   local profile = require("beast.pro…  │
│  init.lua:5   profile.start()                      │
│  init.lua:7   profile.auto_dump_on_quit(out)       │
└─────────────────────────────────────────────────────┘
```

The row for line 3 - `local profile = require("beast.profile")`, where the cursor already is - never appears.

**STATE 2 - Exactly one other occurrence remains (instant jump, no picker):**

```
Before (cursor on the require line):     After ("go to references" jumps directly):
┌────────────────────────────┐           ┌────────────────────────────┐
│ 3  local profile = ...      │   gr      │ 4  profile.start()          │
│ 4  profile.start()           │  ───►    │ 5  local out = ...          │
└────────────────────────────┘           └────────────────────────────┘
```

**STATE 3 - No other occurrences exist (only the current position matched):**

```
 ⚠ beast.finder.lsp: no references found
```

No picker opens, and the cursor doesn't move - identical to today's "nothing found" behavior.

---

# Scenarios

## 1 - Find references, self excluded, multiple remain

```
Step 1: Cursor is on the first `profile` (the `local profile = require(...)` line).
User triggers "find references."
  The picker opens.

Step 2: The user looks at the list.
  It shows the 2 other occurrences of `profile` (line 5 and line 7). The line the
  cursor is on is not in the list.
```

## 2 - Find references, self excluded, exactly one remains

```
Step 1: Cursor is on a symbol used in exactly one other place besides where the
cursor sits. User triggers "find references."
  Excluding the current position leaves exactly one match.

Step 2: The editor jumps straight to that one remaining occurrence.
  The picker window is never shown - same as today's existing single-result
  auto-jump, just counted after the exclusion.
```

## 3 - Go to definition while already standing on the definition

```
Step 1: Cursor is on the function's own definition line. User triggers "go to
definition."
  The only location the language server reports is the current position itself.

Step 2: After excluding it, there's nothing left to jump to.
  A "no definition found" warning appears. The cursor doesn't move, and no
  picker opens.
```

## 4 - Go to definition from a usage site (unaffected case)

```
Step 1: Cursor is on a call to a function defined elsewhere. User triggers "go
to definition."
  The language server's result is a different location than the cursor's - there's
  nothing to exclude.

Step 2: Behavior is unchanged from today.
  Single result -> instant jump. Multiple results -> picker with all of them.
```

## 5 - Cursor lands mid-word

```
Step 1: Cursor is on the last few letters of `profile` (not the very first
character) at the require line. User triggers "find references."
  The language server still resolves the symbol under the cursor as `profile`,
  and reports that same occurrence back as one of the results.

Step 2: The result list.
  The occurrence at that line is still excluded, exactly as if the cursor had
  been on the first letter. Where in the word the cursor sits doesn't matter.
```

---

# Behavior Rules

- Applies to all four LSP-backed jump actions: go to definition, find references, go to declaration, go to implementation.
- "Current position" means wherever the cursor was sitting at the moment the action was triggered - if the cursor moves while the language server is still responding, the original position is still the one excluded.
- A result is excluded if it's in the current file and the cursor was anywhere within that occurrence's word span - not just exactly on its first character.
- Excluding the current position happens before the existing "how many results?" decision: if exclusion brings the count down to exactly one, the editor jumps there directly with no picker; if it brings the count to zero, the existing "not found" warning appears with no picker.
- If the language server's results never include the current position in the first place (the common case for "go to definition" from a usage site), nothing changes from today's behavior.

---

# Success Criteria

- [ ] The occurrence the cursor is currently on never appears as a row in the references/definitions/declarations/implementations list.
- [ ] A symbol with exactly one *other* occurrence besides the current position jumps straight there, with no picker flash.
- [ ] A symbol whose only reported location is the current position shows the existing "not found" warning, with no picker and no cursor movement.
- [ ] Jumps from a usage site to a definition elsewhere look exactly as they do today.

---

# Out of Scope

- Excluding occurrences in *other* files that happen to share the same line/column coordinates as the current position - only an exact match in the current file's word span is excluded.
- Changing dedup behavior for identical results returned by multiple language server clients - that's handled already and is untouched here.
- Applying this exclusion to non-LSP finder sources (files, buffers, live grep, colorschemes, help tags) - they don't have a notion of "current position" in the same sense.
