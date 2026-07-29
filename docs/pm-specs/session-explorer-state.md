---
name: session-explorer-state
description: Session save/restore remembers whether the explorer was open, its folder tree, and where focus was
generated: 2026-07-28
---

# Summary
When you quit Neovim with the file explorer open, reloading your last session
brings the explorer back exactly as you left it - same root folder, same
expanded folders, same focus (explorer or last file) - instead of leaving you
with just the files reopened and the explorer gone.

---

# Problem

You've got a project open, the explorer panel is open on the side, you've
drilled into a few folders to find what you're working on, and you quit
Neovim. Next time you load your last session, all your file buffers come
back - but the explorer is gone. You have to reopen it and re-navigate to the
same folders all over again, every single time. It only remembers the files,
not the workspace you built to find them.

## Why now
The explorer is one of the most frequently open panels in an editing session.
Session restore already promises "pick up where you left off" for buffers -
right now it breaks that promise for the explorer, which is a visible,
daily-use gap.

---

# Target Behavior

STATE 1 - Before quitting (explorer open, folder expanded, focus on a file):

```
┌───────────────┬─────────────────────────────┐
│ project        │  1  function setup()        │
│ ▾ src          │  2    return true            │
│   ▾ components │  3  end                      │
│     Button.tsx │                              │
│   lib          │                              │
│ ▾ tests        │                              │
│   app.test.lua │                              │
└───────────────┴─────────────────────────────┘
                        ^ cursor here (Button.tsx open, not the explorer)
```

Step: `:qa`, then later reload the last session (e.g. pressing `<leader>s`
from the start screen).

STATE 2 - After session reload:

```
┌───────────────┬─────────────────────────────┐
│ project        │  1  function setup()        │
│ ▾ src          │  2    return true            │
│   ▾ components │  3  end                      │
│     Button.tsx │                              │
│   lib          │                              │
│ ▾ tests        │                              │
│   app.test.lua │                              │
└───────────────┴─────────────────────────────┘
                        ^ cursor still here - same as before quitting
```

The explorer reopened at the same root, `src` and `tests` are expanded again
exactly as they were, and the cursor is back in the file - because that's
where it was when you quit.

---

STATE 3 - Quitting with focus *inside* the explorer instead:

```
┌───────────────┬─────────────────────────────┐
│ project        │  1  function setup()        │
│ ▾ src          │  2    return true            │
│   ▾ components │  3  end                      │
│  >  Button.tsx │                              │
│   lib          │                              │
│ ▾ tests        │                              │
│   app.test.lua │                              │
└───────────────┴─────────────────────────────┘
    ^ cursor here (explorer panel) when quitting
```

On reload, the cursor lands back in the explorer panel, on the same row, not
in the file:

```
┌───────────────┬─────────────────────────────┐
│ project        │  1  function setup()        │
│ ▾ src          │  2    return true            │
│   ▾ components │  3  end                      │
│  >  Button.tsx │                              │
│   lib          │                              │
│ ▾ tests        │                              │
│   app.test.lua │                              │
└───────────────┴─────────────────────────────┘
    ^ focus restored here too
```

---

# Scenarios

## 1 - Quit with explorer open, focus on a file, reload

```
Step 1: Explorer open, "src" and "tests" expanded, cursor in Button.tsx.
  Panel visible on the side, tree shows expanded folders.

Step 2: Quit Neovim (:qa).
  Editor closes normally.

Step 3: Later, reload the last session.
  Explorer reopens at the same root. "src" and "tests" are expanded again.
  Cursor is in Button.tsx, same as before quitting.
```

## 2 - Quit with focus inside the explorer, reload

```
Step 1: Explorer open, cursor sitting on a row inside the tree (not in a file).
  Cursor/highlight is on that row in the explorer panel.

Step 2: Quit Neovim.

Step 3: Reload the last session.
  Explorer reopens with the same folders expanded, and keyboard focus lands
  back in the explorer panel - not in a file buffer.
```

## 3 - Quit with explorer closed, reload

```
Step 1: Explorer was never opened, or was closed before quitting.
  No explorer panel visible.

Step 2: Quit Neovim.

Step 3: Reload the last session.
  Explorer stays closed. Nothing changes from today's behavior.
```

## 4 - Edge case: saved root folder no longer exists

```
Step 1: Explorer was open, rooted at "src/legacy", when you quit.

Step 2: Between sessions, "src/legacy" gets deleted or renamed on disk.

Step 3: Reload the last session.
  Explorer does not reopen. No error, no popup - the rest of the session
  (file buffers) restores normally. It behaves as if the explorer had been
  closed when you quit.
```

---

# Behavior Rules

- Explorer state is only remembered if the explorer was open when you quit;
  nothing changes for people who never open it.
- The remembered tree reflects exactly which folders were expanded right
  before quitting - not more, not less.
- The remembered root folder can be different from your project root (e.g.
  after navigating into a subfolder or re-rooting), and restore respects
  that.
- Focus on restore mirrors exactly where your cursor was at quit time -
  explorer panel or last edited file, whichever was active.
- If the remembered root folder is missing or unreadable at reload time, the
  explorer simply does not reopen - silently, with no error.
- This follows the existing per-project-directory + per-git-branch session
  identity - no new session scheme is introduced.

---

# Success Criteria

- [ ] Quitting with the explorer open and reloading brings the explorer back
      open, rooted at the same folder.
- [ ] Folders that were expanded before quitting are expanded again after
      reload.
- [ ] Keyboard focus after reload matches exactly where it was at quit time
      (explorer panel vs. last edited file).
- [ ] Quitting with the explorer closed leaves it closed after reload - no
      regression to current behavior.
- [ ] A missing/deleted saved root folder fails silently - no error dialog,
      rest of the session restores normally.

---

# Out of Scope

- Exact cursor row / scroll position inside the explorer tree - only which
  folders are expanded is remembered, not the precise highlighted row.
- Explorer panel width or side (left/right) - these stay config-driven, not
  session state.
- `show_hidden` toggle, clipboard (copy/cut) state, git status badges - these
  reset to defaults / recompute live on every explorer open, session or not.
