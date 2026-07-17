---
name: finder-init
description: Fuzzy finder picker with prompt, results list, and preview
generated: 2026-07-17
---

# Summary

Finder gives users a fast in-editor picker for files, buffers, and searches. It keeps everything inside Neovim with a prompt, a results list, and an optional preview so users can jump to the right place without leaving the editor.

---

# Problem

When a project grows, scrolling through buffers or searching by hand becomes slow. Users need a picker that can narrow results quickly, show enough context to choose confidently, and open the result in the right way.

## Why now

This reduces the friction of moving between files and search results and makes the editor feel faster during everyday navigation.

---

# Target Behavior

```
┌──────────────────────────────────────────────────────┐
│ > init                                               │
│ init.lua                                             │
│ finder/init.lua                                      │
│ statusline/init.lua                                  │
├──────────────────────────────────────────────────────┤
│ preview area shows the selected file                 │
└──────────────────────────────────────────────────────┘
```

```
STATE 1 — Typing a query:
  The prompt updates as the user types and the results narrow immediately.

STATE 2 — Moving through results:
  The selected row changes, and the preview follows the highlighted item.

STATE 3 — Confirming a result:
  Pressing Enter opens the selected item in the chosen way.

STATE 4 — Special modes:
  Buffer selection, file search, and text search all use the same picker shell but show different sources.
```

---

# Scenarios

## 1 — Opening the file picker

```
Step 1: The user opens Finder for files.
  A prompt, results list, and preview window appear.

Step 2: The user types a few letters.
  The result list narrows to matching file names.

Step 3: The user presses Enter.
  The selected file opens and the picker closes.
```

## 2 — Choosing from open buffers

```
Step 1: The user opens Finder for buffers.
  The list shows currently open buffers.

Step 2: The user moves between entries.
  The selection highlight and preview update.

Step 3: The user confirms a buffer.
  That buffer becomes active.
```

## 3 — Using the preview and multi-select

```
Step 1: The user moves the cursor through results.
  The preview changes to match the highlighted item.

Step 2: The user toggles multiple items.
  Selected entries remain marked in the list.

Step 3: The user confirms.
  The chosen items are passed to the selected action.
```

---

# Behavior Rules

- Search results should update as the user types.
- The preview should help the user confirm the right result before opening it.
- File and buffer pickers should feel like the same tool, just with different sources.
- Multi-select should be available when it helps the user choose more than one item.
- The picker should stay inside Neovim and not require a separate external fuzzy-search app.

---

# Success Criteria

- [ ] Users can open a picker for files, buffers, and search results.
- [ ] Typing narrows results quickly.
- [ ] The selected item can be previewed before opening.
- [ ] Enter opens the chosen result in the expected place.
- [ ] The picker works without needing a separate fuzzy-search binary.

---

# Out of Scope

- Field-specific query syntax
- Frecency history ranking
- External terminal fuzzy-finder integrations
