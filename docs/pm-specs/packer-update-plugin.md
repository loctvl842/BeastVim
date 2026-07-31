---
name: packer-update-plugin
description: Update a plugin from the Packer UI with the 'u' key
generated: 2026-07-31
---

# Summary

From the Packer UI, the user can move the cursor onto a plugin and press `u` to update it immediately to its latest version, without leaving the UI or confirming anything.

---

# Problem

The Packer UI can show, load, and delete plugins, but there's no way to pull in a newer version of one. Today, keeping a single plugin current means leaving the UI and running a separate update flow for everything at once — there's no way to just grab the latest version of the one plugin the user is looking at right now.

## Why now

Load and Delete already happen inline in the Packer UI. Update is the other everyday plugin-manager action that's missing, and without it the UI still can't stand in for a full plugin manager.

---

# Target Behavior

```
STATE 1 — Home page, before updating anything:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Total: 42 plugins · 3 libraries   Sort: Name                │
│                                                                │
│   Loaded (28 plugins, 3 libraries)                            │
│      ✓ blink.cmp                (12.4ms)                      │
│      ✓ gitsigns.nvim              (3.1ms)                     │
│    󰂖 ✓ explorer                   (1.8ms)                     │
│      ...                                                      │
│                                                                │
│   Not Loaded (14 plugins)                                     │
│      ○ neotest                     event BufReadPost          │
│      ○ vim-dadbod                  cmd :DB                    │
│      ...                                                      │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load  S Sort  x Delete  u Update  P Profile  ? Help  q Close │
└──────────────────────────────────────────────────────────────┘

STATE 2 — Cursor moved onto "gitsigns.nvim", right before pressing u:

│   Loaded (28 plugins, 3 libraries)                            │
│      ✓ blink.cmp                (12.4ms)                      │
│      ✓ gitsigns.nvim              (3.1ms)   ← cursor here     │

STATE 3 — Immediately after pressing u, update in progress:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Updating (0/1)                             Sort: Name       │
│                                                                │
│   Operations (1)                                              │
│      ⠋ gitsigns.nvim   update   180ms                         │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load  S Sort  x Delete  u Update  P Profile  ? Help  q Close │
└──────────────────────────────────────────────────────────────┘

STATE 4 — Update finished successfully:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Updating (1/1)                             Sort: Name       │
│                                                                │
│   Operations (1)                                              │
│      ✓ gitsigns.nvim   updated   842ms                        │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load  S Sort  x Delete  u Update  P Profile  ? Help  q Close │
└──────────────────────────────────────────────────────────────┘
```

---

# Scenarios

## 1 — Update a plugin that has a newer version available

```
Step 1: The user moves the cursor onto a plugin row, loaded or not
(e.g. gitsigns.nvim).
  The cursor sits on that plugin's line.

Step 2: The user presses u.
  The plugin's row moves into an "Operations" section with a spinner
  next to its name, same as when a brand-new plugin is being installed.

Step 3: The update finishes.
  The spinner turns into a checkmark and shows how long it took. A
  short notification confirms the plugin was updated. The plugin then
  goes back to showing normally in "Loaded" or "Not Loaded".
```

## 2 — The plugin is already up to date

```
Step 1: The user presses u on a plugin that has no newer version to
pull.
  The cursor sits on that plugin's line.

Step 2: The result.
  No spinner, no operation shown — instead a short message tells the
  user the plugin is already up to date. Nothing about the row changes.
```

## 3 — Cursor is on a library row, not a plugin

```
Step 1: The user moves the cursor onto a row marked with the library
badge (a Beast-internal library such as "explorer", not a git plugin).
  The cursor sits on that row.

Step 2: The user presses u.
  Nothing is updated. A short message explains that libraries aren't
  updated this way. The row stays exactly where it was.
```

## 4 — Cursor isn't on a plugin row at all

```
Step 1: The user moves the cursor onto a blank line, a section header,
or a row inside "Deleted".
  The cursor sits on a non-plugin line.

Step 2: The user presses u.
  Nothing happens except a short "nothing to update here" message.
```

## 5 — Update fails

```
Step 1: The user presses u on a plugin row, but the update can't
complete (e.g. no network, or the source repo is unreachable).
  A spinner appears next to the plugin's name, same as any update.

Step 2: The result.
  The spinner turns into an error mark with a short reason. The
  plugin's own files are untouched — it keeps working exactly as
  before, just not updated.
```

---

# Behavior Rules

- `u` only acts on plugin rows inside "Loaded" or "Not Loaded". It has no effect on library rows, the "Deleted" section, or any other line.
- Updating is immediate — there is no confirmation prompt.
- While an update is running, the plugin shows up in the same "Operations" list already used for fresh installs, with a spinner, then a checkmark or an error mark.
- The header above "Operations" reflects what's actually happening — it reads "Updating" for an update, the same way it already reads for a fresh install.
- If the plugin has nothing new to pull, no spinner or operation appears — the user just gets a short "already up to date" message.
- If an update fails, the plugin is left exactly as it was before — nothing is deleted, nothing is left half-updated.
- Updating a plugin only touches that one plugin. It never triggers updates for anything else in the list.
- The action bar and the `?` help screen both list the `u` / Update action alongside the existing ones.

---

# Success Criteria

- [ ] Pressing `u` on a plugin row (loaded or not loaded) starts an update immediately, no confirmation needed.
- [ ] The update shows progress (spinner, then success or error) the same way an install does.
- [ ] Pressing `u` on an already-up-to-date plugin shows a clear "already up to date" message and changes nothing.
- [ ] Pressing `u` on a library row or a non-plugin line does nothing and shows a clear message.
- [ ] A failed update leaves the plugin working as before and reports the error, instead of silently failing.
- [ ] The action bar and help screen show the new `u` Update action.

---

# Out of Scope

- Updating every plugin at once from this key — this is single-plugin only, matching how `x` deletes one plugin at a time.
- A changelog / diff view of what changed in the update — not requested.
- Rolling back an update once applied.
