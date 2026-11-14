---
name: explorer-project-search
description: Search every file under the explorer root from the explorer itself, shown as a tree, powered by the file finder
generated: 2026-11-14
---

# Summary
Pressing `/` or `?` in the explorer searches all files under the explorer's root folder, including files inside folders that are collapsed, and shows only the matching files as a tree. It reuses the file finder's search so results match what the file finder would give. If the file finder is not installed, the explorer keeps its current behavior.

---

# Problem

Today `/` in the explorer is the editor's plain text search on the explorer window. It only sees the lines that are on screen as text, so a file inside a collapsed folder is invisible to it. Example: `lua/beast/init.lua` lives in the closed folder `lua/beast/`; searching `in.lua` finds nothing, because that name is not drawn anywhere.

The only way to find such a file is to leave the explorer and open the file finder, which shows a flat list and loses the folder context the user was looking at.

## Why now
The file finder already searches the whole project quickly. Letting the explorer use it gives one search that works in both places, and keeps the folder structure visible, which is the reason people use the explorer.

---

# Target Behavior

STATE 1 — Before searching (folders closed):

```
┌─ explorer ──────────────────────────┐
│  BeastVim                           │
│  ▸ colors                           │
│  ▸ docs                             │
│  ▸ lua                              │
│  ▸ scripts                          │
│    init.lua                         │
│    README.md                        │
└─────────────────────────────────────┘
```

STATE 2 — Typing in the editor's own search prompt at the bottom (`/` pressed, typed `in.lua`):

```
┌─ explorer ──────────────────────────┐
│  / in.lua                   3 files│
│  BeastVim                           │
│  ▾ lua                              │
│    ▾ beast                          │
│        init.lua                     │
│      ▾ libs                         │
│        ▾ explorer                   │
│            init.lua                 │
│        ▾ finder                     │
│            init.lua                 │
└─────────────────────────────────────┘
/in.lua█
  (the usual search prompt at the bottom of the screen takes the typing;
   matching letters "in.lua" are highlighted in each name;
   folders on the way to a match are opened automatically;
   everything that does not match is hidden)
```

STATE 3 — After `<Enter>` (bottom prompt closed, results stay, cursor on first match):

```
┌─ explorer ──────────────────────────┐
│  / in.lua                   3 files│
│  BeastVim                           │
│  ▾ lua                              │
│    ▾ beast                          │
│ ▶     init.lua                      │
│      ▾ libs                         │
│        ▾ explorer                   │
│            init.lua                 │
│        ▾ finder                     │
│            init.lua                 │
└─────────────────────────────────────┘
  (the `/ in.lua` line at the top stays so the user knows search mode is still on)
```

STATE 4 — No results:

```
┌─ explorer ──────────────────────────┐
│  / zzzz                     0 files│
│                                     │
│        No files match "zzzz"        │
│                                     │
└─────────────────────────────────────┘
/zzzz█
```

STATE 5 — Finder not installed:

```
  `/` and `?` behave exactly as they do today (plain text search of the
  explorer window). No search line, no error.
```

---

# Scenarios

## 1 — Find a file inside a closed folder (happy path)

```
Step 1: Explorer is open, every folder closed. User presses `/`.
  The editor's normal search prompt opens at the bottom of the screen, and a
  "/ query" line appears at the top of the explorer.

Step 2: User types `in.lua`.
  The explorer shows only the search line and nothing else until something
  matches. After each keystroke the matching files and the folders leading to
  them (all opened) appear. The count at the right updates.

Step 3: User presses <Enter>.
  The bottom prompt closes. Results stay on screen. Cursor moves
  to the first matching file.

Step 4: User moves with j / k between matching files.
  The cursor jumps from one match to the next, skipping folders.

Step 5: User presses <Enter> on a file.
  The file opens in the editor window, as it does today. The explorer stays
  in search mode with the same results.
```

## 2 — Leave search mode

```
Step 1: Explorer shows search results (bottom prompt already closed).
Step 2: User presses <Esc><Esc>.
  The "/ query" line disappears. The tree returns to how it looked before the
  search: same folders open or closed, cursor on the file that was selected in
  the results (its folders are opened so it stays visible).
```

## 3 — Typing is cancelled before confirming

```
Step 1: User presses `/`, types `abc`.
Step 2: User presses <Esc> in the bottom prompt (as with any search).
  The prompt closes, search mode ends, tree is back to its previous state.
```

## 4 — No match

```
Step 1: User presses `/`, types `zzzz`.
  The explorer shows "No files match "zzzz"" and the count reads 0 files.
Step 2: User deletes characters with <BS>.
  Results come back as soon as something matches.
```

## 5 — Search while hidden files are off

```
Step 1: Hidden files are not shown (the default).
Step 2: User searches `env`.
  Files like `.env` are not listed, same as in the file finder.
Step 3: User toggles hidden files.
  Results refresh to include them without losing the typed text.
```

## 6 — Finder is not installed (graceful degrading)

```
Step 1: User presses `/` in the explorer.
  The editor's plain text search starts, exactly as before this feature.
  Nothing about the explorer looks different.
```

## 7 — Change of root after searching

```
Step 1: In search mode, user presses <Esc><Esc>, then `.` on a folder
  (set as root). Search mode has ended; the explorer re-roots as today.
  The user can press `/` again to search the new root.
```

---

# Behavior Rules

- `/` and `?` do the same thing (search is not directional).
- The search covers every file under the explorer's current root, not only what is drawn.
- Matching uses the file finder's fuzzy matching on the path relative to the root. A folder name in the query narrows results to files under it.
- Only files are matched. Folders appear only as the path to a matching file, and are always shown open.
- Results are ordered like the normal tree (folders first, then alphabetical), not by score.
- Hidden and gitignored files follow the same visibility switches as the explorer and the file finder.
- Files that are open in a buffer are not given special treatment in search results: they show only if they match.
- Git status, diagnostics and clipboard badges keep showing on result rows.
- While searching, result rows support open, split, system open and toggling hidden files. Create, rename, delete, trash, copy, cut, paste, set root and navigate up are not available until search mode ends with `<Esc><Esc>` (the cursor lands on the file the user was on).
- Search mode starts empty and fills as the user types.
- Typing uses the editor's own search prompt at the bottom, so editing keys, history and paste work as in any search.
- In the bottom prompt `<Enter>` closes it and keeps results; `<Esc>` closes it and ends search mode (normal search cancel).
- Once results are showing, `<Esc><Esc>` ends search mode. A single `<Esc>` does nothing there, so it never feels delayed or half-cancelled.
- Search mode stays on after the prompt closes, and ends only on `<Esc><Esc>` in the explorer or when the explorer is closed (closing and reopening shows the normal tree).
- The top "/ query" line is display only (query and count); it cannot be typed in.
- Pinned ancestor folder headers (sticky) are switched off while search mode is on, because the results already show the full folder path to every match and the pinned headers would cover the "/ query" line. They come back when search mode ends.
- The tree state from before the search (opened folders, cursor) is restored when search mode ends.
- The search line stays visible for as long as search mode is on.
- If the finder is not installed, `/` and `?` keep their normal meaning and no search mode exists.

---

# Success Criteria

- [ ] Searching `in.lua` with every folder closed shows `lua/beast/init.lua` and the other matches.
- [ ] Results appear as a tree with the right folders opened and non-matches hidden.
- [ ] Matching letters are highlighted in each result name.
- [ ] Typing happens in the editor's own bottom search prompt, with results updating live.
- [ ] `<Enter>` leaves the prompt, keeps results, and puts the cursor on the first match.
- [ ] j / k move between results without landing on folders.
- [ ] Opening a result file works and search mode stays on.
- [ ] `<Esc><Esc>` returns the tree to its exact pre-search state.
- [ ] A zero-result search shows a clear empty message and a 0 count.
- [ ] With the file finder missing, `/` and `?` behave exactly as before.
- [ ] Searching a large project stays responsive while typing.

---

# Out of Scope

- Searching inside file contents (the finder's live grep already does that).
- Matching folder names on their own (files only).
- Sorting results by match score.
- Searching outside the explorer's root.
- Remembering the last query between uses.
- Customizing the search keys (defaults only for now).
