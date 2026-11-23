---
name: breadcrumb-symbol-trail
description: Winbar shows the chain of symbols (class > method > inner function) that contains the cursor, after the file path
generated: 2026-11-23
---

# Summary

The breadcrumb bar learns to show *where inside the file* the cursor is: the chain of symbols that contain it (for example `Config > setup > merge`), each with a kind icon, right after the file name. It replaces what people install nvim-navic for, built into BeastVim, and also works in files that have no language server.

---

# Problem

The breadcrumb bar today stops at the file name. The earlier breadcrumb spec promised "code context" after the file, but nothing is drawn there. In a 600-line file, once the function header scrolls off screen, there is no cue for which function, method or class the cursor is in. You scroll up, or search for the header, to find out.

## Why now

The bar, its per-window behavior and its colors already exist, and the slot after the file name is empty. Filling it closes the gap with nvim-navic without adding a plugin or a second winbar owner.

---

# Target Behavior

STATE 1 - cursor inside a nested function (the trail is the "symbol trail"):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ lua  beast  libs  breadcrumb   init.lua   M   󰊕 setup   󰊕 ensure_autocmds │
└──────────────────────────────────────────────────────────────────────────────┘
   dir  dir   dir    dir          file        │      │          └ innermost symbol
                                              │      └ function
                                              └ module-level table
```

- Directories and file name look as they do today.
- Each symbol is a kind icon followed by its name, joined by the same separator as the path.
- Icons are the same kind icons the completion menu uses; icon color follows the kind family, names are one calm color.

```
STATE 2 - cursor at the top level of the file, outside any symbol:

┌──────────────────────────────────────────────────────────────────────────────┐
│ lua  beast  libs  breadcrumb   init.lua                                      │
└──────────────────────────────────────────────────────────────────────────────┘

─────────────────────────────────────────
STATE 3 - cursor moves into a different method:

before:  init.lua   Server   󰊕 start
after:   init.lua   Server   󰊕 stop

─────────────────────────────────────────
STATE 4 - narrow window, the trail does not fit:

┌─────────────────────────────────────────────┐
│ …  init.lua   …  󰊕 ensure_autocmds         │
└─────────────────────────────────────────────┘
  Outer directories go first, then outer symbols.
  File name and innermost symbol stay.

─────────────────────────────────────────
STATE 5 - file with no language server, but a known language (e.g. a config or markdown file):

┌──────────────────────────────────────────────────────────────────────────────┐
│ docs  guide.md   Install   Linux                                             │
└──────────────────────────────────────────────────────────────────────────────┘
  The trail is read from the file's structure instead (functions, classes,
  headings...). Same look, same icons.

─────────────────────────────────────────
STATE 5b - plain text, or a language that is not understood at all:

┌──────────────────────────────────────────────────────────────────────────────┐
│ notes  todo.txt                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
  Same as today. No placeholder, no spinner, no error.

─────────────────────────────────────────
STATE 6 - unsaved changes with a trail:

┌──────────────────────────────────────────────────────────────────────────────┐
│ init.lua   M   󰊕 setup ●                                                    │
└──────────────────────────────────────────────────────────────────────────────┘
  The modified marker stays at the very end, after the last symbol.
```

---

# Scenarios

## 1 - Walking through a file

```
Step 1: The user opens a Lua file with a language server attached; cursor on line 1.
  Winbar shows the path and file name only (line 1 is outside any symbol).

Step 2: The user moves the cursor into the body of `M.setup`.
  The trail extends:  init.lua   M   󰊕 setup

Step 3: The user moves into a callback defined inside `setup`.
  The trail extends again:  init.lua   M   󰊕 setup   󰊕 callback

Step 4: The user moves below the end of `M.setup`.
  The trail shrinks back to the symbols that still contain the cursor.
```

## 2 - Opening a file, language server still starting

```
Step 1: The user opens a file; the server has not answered yet.
  Winbar shows the path and file name only.

Step 2: The server finishes loading (no keypress needed).
  The symbol trail appears on its own for the current cursor position.
```

## 3 - Editing while a trail is shown

```
Step 1: The user types inside `setup`.
  The trail stays visible and does not blink or go blank while typing.

Step 2: The user adds a new function above and pauses typing.
  Within a moment the trail reflects the new structure.

Step 3: The user renames the function the cursor is in.
  After the server catches up, the trail shows the new name.
```

## 4 - Two splits on the same file

```
Step 1: The user splits the window; both show init.lua.
  Both bars show the same trail.

Step 2: The user moves the cursor in the left split only.
  The left trail changes. The right trail still describes the right cursor,
  even though that split is not the focused one.
```

## 5 - Window too narrow

```
Step 1: A deep trail is shown in a wide window.
  Full path, file and all symbols are visible.

Step 2: The user narrows the window.
  Outer directories collapse into "…" first. If still too wide, outer
  symbols collapse into "…" too. The file name and the innermost symbol
  are always kept.
```

## 6 - Turning it off

```
Step 1: The user sets the symbol trail to off in their config.
  The bar behaves exactly as before this feature: path and file name only,
  and no request for symbols is made.
```

## 7 - No language server

```
Step 1: The user opens a markdown file; no server is attached.
  The trail shows headings from the file's structure: guide.md   Install   Linux

Step 2: A language server later attaches to a file that was using the structure trail.
  The trail switches to the server's symbols without a blink.

Step 3: The user opens a plain text file.
  Path and file name only. Nothing else changes, nothing is reported.
```

---

# Behavior Rules

- The trail is the chain of symbols whose range contains the cursor, outermost first, innermost last.
- A cursor on a symbol's own header line counts as inside it.
- Outside every symbol, no symbols are shown (file only).
- Each window shows the trail for its own cursor, including windows that are not focused.
- Symbols come from the file's language server when it provides them. Otherwise they are read from the file's structure when the language is understood. Otherwise the path only.
- The server wins whenever both are available, so the trail never mixes the two sources.
- A symbol with an empty name is skipped; its children still show.
- The trail updates when the cursor stops moving, not on every keystroke, so holding `j` stays smooth.
- While the server is re-reading after an edit, the previous trail is kept rather than blanked.
- Truncation order: outer directories, then outer symbols. The file name, the innermost symbol and the modified marker are never dropped.
- The modified marker moves to the end of the bar so it always follows the last visible item.
- The bar stays hidden wherever it is hidden today (transient panels, special buffers).
- Everything is optional and off-switchable; with it off, nothing about the bar changes.

---

# Success Criteria

- [ ] Moving the cursor into a function, method or class shows its name with a kind icon after the file name.
- [ ] Nested symbols show as an ordered chain, outermost first.
- [ ] Outside any symbol, only the path and file name show.
- [ ] Two windows on one file show independent trails.
- [ ] The trail appears by itself once a slow server finishes starting.
- [ ] Typing never blanks the trail; it refreshes shortly after typing pauses.
- [ ] Narrow windows keep the file name and innermost symbol visible.
- [ ] Files with no server but a known language still show a trail, with the same look.
- [ ] Plain text and unknown languages look exactly as they do today.
- [ ] Turning the feature off restores today's bar and stops symbol requests.
- [ ] Holding `j` or `k` through a large file shows no stutter.

---

# Out of Scope

- Clickable segments and "jump to symbol" menus (already out of scope for the breadcrumb bar; a dropdown of siblings is a separate feature).
- Filtering which symbol kinds appear (variables, fields, etc.) and a maximum depth setting; width-based truncation covers long trails for now.
- Exposing the trail text to other bars such as the statusline.
