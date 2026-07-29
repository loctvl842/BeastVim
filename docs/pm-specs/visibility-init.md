---
name: visibility-init
description: A single global visibility state (hidden files, gitignored files) shared by Explorer and Finder so toggling one updates both
generated: 2026-07-29
---

# Summary

One shared "what counts as visible" setting for the whole app. Toggling "show hidden files" or "show gitignored files" anywhere - a keymap, a tabline button, or from inside Explorer or Finder - instantly applies everywhere a file list is shown.

---

# Problem

Today, Explorer and Finder each decide for themselves which files to show, and they don't agree with each other:

- **Explorer** starts with hidden files (dotfiles) turned off, but has no way to hide files listed in `.gitignore` - a `node_modules` folder or a `.env` file that's gitignored still shows up in the tree.
- **Finder** does the opposite - it always shows dotfiles, but it always hides anything gitignored, with no way to turn either behavior off.

So a user who presses "show hidden files" in Explorer sees dotfiles appear in the tree, then opens Finder expecting the same files to be searchable - and they're not, because Finder was never told about that preference. Each surface has its own hidden rule, its own gitignore rule, and no shared memory between them. The user ends up mentally tracking "which screen shows what" instead of just working.

## Why now

The project is growing more file-based surfaces (Explorer, Finder, and likely more later). Every new surface that invents its own filtering rules makes the inconsistency worse and the mental overhead bigger. Fixing this once, centrally, stops the problem from compounding.

---

# Target Behavior

A visibility state with two independent switches:
- **Show hidden files** - dotfiles like `.env`, `.gitignore`
- **Show gitignored files** - anything matched by `.gitignore` rules (e.g. `node_modules/`, build output)

Both switches start **off**. Both Explorer and Finder read the same two switches.

```
                                              ┌ hidden files (off)
                                              │ ┌ gitignored files (off)
                                              │ │ ┌ day/night
                                              ▼ ▼ ▼
 main.lua  config.lua  ●README.md                          
```

When hidden files is switched on:

```
                                              ┌ hidden files (ON)
                                              │ ┌ gitignored files (off)
                                              │ │ ┌ day/night
                                              ▼ ▼ ▼
 main.lua  config.lua  ●README.md                          
```

Icons brighten/change when their switch is on, dim when off - same visual language as the existing day/night button.

Explorer tree, same project, hidden files ON / gitignored OFF:

```
 project/
 ├── .env
 ├── .gitignore
 ├── config.lua
 ├── main.lua
 └── README.md
```

Explorer tree, hidden files ON / gitignored ON (node_modules is gitignored):

```
 project/
 ├── .env
 ├── .gitignore
 ├── config.lua
 ├── main.lua
 ├── node_modules/
 └── README.md
```

Finder results list, same two settings, searching "m":

```
 hidden OFF / gitignored OFF     hidden ON / gitignored ON
 ┌───────────────────────┐       ┌───────────────────────┐
 │ config.lua             │       │ .env                  │
 │ main.lua               │       │ config.lua             │
 └───────────────────────┘       │ main.lua               │
                                  │ node_modules/webpack.js│
                                  └───────────────────────┘
```

---

# Scenarios

## 1 - Toggle hidden files from the keymap, see it in both places

```
Step 1: User opens Explorer. Dotfiles (.env, .gitignore) are not shown.

Step 2: User presses <leader>uh (toggle hidden files).
  Explorer tree redraws immediately, now showing .env and .gitignore.

Step 3: User opens Finder and searches "env".
  .env appears in the results - Finder already knows hidden files are visible,
  with no extra toggle needed.
```

## 2 - Toggle gitignored files from Finder's side, see it in Explorer

```
Step 1: User opens Finder, searches "webpack". No results - webpack.config.js
  lives inside a gitignored node_modules/ folder.

Step 2: User presses <leader>ug (toggle gitignored files).
  User searches "webpack" again - the file now appears in results.

Step 3: User closes Finder and opens Explorer.
  node_modules/ is now visible in the tree, without touching Explorer at all.
```

## 3 - Toggle from the tabline button

```
Step 1: User looks at the tabline. Two small icons sit beside the day/night
  button, both in their "off" state.

Step 2: User clicks the hidden-files icon.
  The icon switches to its "on" appearance. Explorer (if open) and Finder
  (next time it's opened) both show hidden files immediately.

Step 3: User clicks the gitignored-files icon.
  Same effect for gitignored files - one click, both surfaces update.
```

## 4 - Toggling while both Explorer and Finder are open

```
Step 1: User has Explorer open in a side panel and opens Finder on top of it.

Step 2: User presses <leader>uh.
  Finder's results refresh immediately to include hidden files.

Step 3: User closes Finder.
  Explorer, which was open the whole time underneath, is already showing
  hidden files too - it updated live, not just on next open.
```

## 5 - Edge case: toggling gitignored files outside a git repo

```
Step 1: User opens Explorer/Finder in a plain folder that is not a git
  repository (no .gitignore anywhere).

Step 2: User presses <leader>ug.
  The icon still switches state, but nothing in the file list changes -
  there are no gitignore rules to apply. No error, no notification.
```

---

# Behavior Rules

- Two independent switches: **show hidden files** and **show gitignored files**. Toggling one never affects the other.
- Both switches default to **off** (hidden files and gitignored files are hidden until the user turns them on) - this is a change from today's Explorer default, which currently shows gitignored files with no way to hide them.
- Any surface that changes a switch - keymap, tabline button click, or a future in-panel toggle - updates every consumer immediately. Open Explorer and Finder windows re-render without needing to be closed and reopened.
- `<leader>uh` and `<leader>ug` work globally (from any screen), not only while focused inside Explorer or Finder.
- The tabline shows two small toggle icons immediately beside the existing day/night button, each independently clickable, each visually distinguishing on vs. off (matching the day/night button's existing style language).
- The `.git` directory itself stays excluded from both Explorer and Finder regardless of either switch - unchanged from current behavior.
- Turning on "show gitignored files" outside a git repository (or in a folder with no applicable `.gitignore`) is a no-op on the file list - it does not error or notify.
- The visibility state is a single, in-memory setting for the whole running session - not per-window, per-tab, or per-project.

**Open question for the dev spec:** should the visibility state persist across Neovim restarts (e.g. captured by session save/restore, the way Explorer's tree state already is), or should it always reset to "hidden files off, gitignored off" on every new launch? This spec assumes it resets on every launch unless you tell us otherwise.

---

# Success Criteria

- [ ] Toggling hidden files anywhere (keymap, tabline button, or from within Explorer/Finder) is instantly reflected in both Explorer and Finder.
- [ ] Toggling gitignored files anywhere is instantly reflected in both Explorer and Finder.
- [ ] `<leader>uh` and `<leader>ug` work regardless of which screen currently has focus.
- [ ] The tabline shows two toggle icons beside the day/night button that always reflect current state and are clickable.
- [ ] No component-specific "hidden files" or "gitignored files" setting remains - there is exactly one source of truth.
- [ ] A future third file-based surface could plug into the same two switches without inventing its own filtering.

---

# Out of Scope

- Persisting visibility state across Neovim restarts - deferred pending the open question above.
- Per-project or per-directory visibility overrides - v1 is a single global state, per the request's initial scope.
- Any visibility rule beyond "hidden files" and "gitignored files" (e.g. size limits, custom glob excludes) - the state is built to be extensible, but v1 ships only these two.
- Search ranking/matching, file sorting, file metadata, and UI rendering choices - explicitly not controlled by this feature.
- Any file-based surface other than Explorer and Finder - future consumers are a goal of the design, not part of this release.
