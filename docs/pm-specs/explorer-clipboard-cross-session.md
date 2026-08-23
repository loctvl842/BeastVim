---
name: explorer-clipboard-cross-session
description: Explorer copy/cut/paste works across separate Neovim sessions (and after quitting) by piggybacking on the computer's shared system clipboard.
generated: 2026-08-23
---

# Summary
Copying or cutting a file in the explorer sidebar puts it on the same clipboard every other app on the computer shares, so pasting works in any other running Neovim window - not just the one where you pressed copy or cut.

---

# Problem

BeastVim's file explorer sidebar lets you mark a file or folder to copy or cut, then paste it somewhere else - the same copy/cut/paste you'd use in a normal file manager like Finder or Windows Explorer. Today, that clipboard only lives inside the single running editor window where you pressed copy or cut.

If you have two projects open at once - say, two terminal tabs each running their own instance of the editor - copying a file in one window and switching to the other to paste it does nothing. The paste action reports the clipboard is empty, even though you copied a file seconds ago. This is surprising, because everywhere else on the computer, copy/paste works across windows and apps without a second thought.

## Why now
Working across multiple projects side by side in separate windows is a normal way to use the editor, and needing to keep everything inside one single running instance just to move a file defeats the point of splitting work across windows in the first place. Reusing the computer's system clipboard - the same shared clipboard every other app already uses - closes this gap without changing how copy/cut/paste already feels.

---

# Target Behavior

```
Session A (Terminal tab 1)                 Session B (Terminal tab 2)
┌───────────────────────────┐              ┌───────────────────────────┐
│ MY-PROJECT                │              │ OTHER-PROJECT             │
│  src/                     │              │  src/                    │
│    app.lua (copy)         │              │    utils.lua             │
│    utils.lua              │              │  README.md               │
│  README.md                │              │                          │
└───────────────────────────┘              └───────────────────────────┘
  cursor on app.lua, press "y"                cursor on src/, press "p"
```

After paste completes in Session B:

```
Session B (Terminal tab 2)
┌───────────────────────────┐
│ OTHER-PROJECT             │
│  src/                    │
│    app.lua                │
│    utils.lua              │
│  README.md                │
└───────────────────────────┘
```

`app.lua` now exists in both projects. In Session A, `app.lua` was only copied (not cut), so it's untouched there - though its `(copy)` marker won't clear until Session A's explorer next redraws (see Behavior Rules).

---

# Scenarios

## 1 — Copy a file, paste it in a different session

```
Step 1: In Session A, cursor on app.lua, press "y" (copy)
  app.lua shows a highlighted "(copy)" marker next to its name

Step 2: Switch to Session B - a separate, already-running Neovim window on a different project
  Session B's explorer looks exactly as it did before; nothing to see yet

Step 3: In Session B, cursor on the destination folder, press "p" (paste)
  app.lua appears in that folder in Session B, with the same content it had in Session A
```

## 2 — Toggling copy off clears the clipboard everywhere

```
Step 1: In Session A, cursor on app.lua, press "y" (copy)
  app.lua shows a highlighted "(copy)" marker

Step 2: Press "y" again (same as today: pressing copy again while a copy is already pending cancels it)
  The "(copy)" marker disappears in Session A

Step 3: Switch to Session B, cursor on a folder, press "p"
  Nothing happens - the explorer reports there is nothing to paste, since the clipboard was cleared, not just in Session A but everywhere
```

## 3 — Cut a file, quit Neovim, paste later

```
Step 1: In Session A, cursor on old-report.md, press "x" (cut)
  old-report.md shows a highlighted "(cut)" marker; the file itself is untouched on disk

Step 2: Quit Session A entirely (:qa)
  old-report.md still exists at its original location - cutting never deletes anything by itself

Step 3: In Session B (or a freshly opened Neovim), cursor on a destination folder, press "p"
  old-report.md moves into that folder and disappears from its original location
```

## 4 — Multiple files marked together, pasted together elsewhere

```
Step 1: In Session A, visually select three files, press "y"
  All three show a highlighted "(copy)" marker

Step 2: In Session B, cursor on a destination folder, press "p"
  All three files are copied into that folder in one paste, same as a same-session multi-paste today
```

## 5 — Pasting the marked files somewhere other than the explorer

```
Step 1: In Session A, mark two files with "y" (copy)
  The two paths are now sitting on the plain system clipboard, one per line - nothing hidden or specially encoded

Step 2: Instead of pasting in an explorer, paste (Cmd+V / normal system paste) into a text buffer or a chat box
  The two file paths appear as plain text, one per line - the same as pasting the result of any other app's copy action
```

## 6 — Pasting when the clipboard holds something unrelated

```
Step 1: Outside of the explorer (in any other app, or by copying plain text), the system clipboard now holds "hello world"

Step 2: In a Neovim session's explorer, cursor on a folder, press "p"
  Nothing is created or moved; the explorer reports there is nothing to paste

Step 3: The tree is unchanged
```

## 7 — Source file disappears before paste

```
Step 1: In Session A, cursor on report.md, press "x" (cut)
  report.md shows a "(cut)" marker

Step 2: Outside Neovim entirely, report.md gets deleted from disk before anyone pastes it

Step 3: In Session B, cursor on a destination folder, press "p"
  The explorer reports the move failed for report.md; nothing is left half-moved or broken
```

## 8 — No system clipboard available

```
Step 1: The terminal has no access to a system clipboard (for example, an SSH session without clipboard forwarding)

Step 2: In that same session, copy a file with "y" and paste it with "p" in the same window
  Copy/cut/paste works exactly as it does today, fully usable within that one session

Step 3: Cross-session paste simply isn't available here - no error, no broken state
```

---

# Behavior Rules

- Copying or cutting a file/folder writes it to the same system clipboard every other app on the computer shares, not just this window's own memory.
- Pressing copy (or cut) again while a copy (or cut) is already pending clears the mark, exactly like today - and because the clipboard is now the shared system one, that "empty" state is visible to every session, not just the one that cleared it.
- Marking multiple selected files at once (visual mode) puts all of their paths on the clipboard together as a plain list, one path per line - not a special format hidden from view.
- Because it's the ordinary system clipboard, pasting that content anywhere else - a text file, a chat box, a search field - shows the raw list of file paths, the same as it would for any other app's copy action.
- Paste checks whether the current system clipboard content is something the explorer put there. If it holds unrelated content (plain text, something copied in another app), paste treats it as empty and does nothing.
- A cut file is never removed from disk until a paste actually completes - cutting and then closing Neovim (or the whole terminal) does not lose or delete the file.
- Like today, a completed paste uses up the clipboard - pasting again does nothing until something new is copied or cut.
- The `(copy)`/`(cut)` marker next to a file name reflects what that session's own explorer last did. A marker set (or cleared) in one session is only guaranteed to appear in another already-open session's tree the next time that session's explorer redraws (e.g. on window focus or a tree refresh) - not the instant it happens elsewhere.
- If a copied/cut file is deleted or moved by something else before paste runs, paste reports an error for that file rather than silently doing nothing.
- On setups where the terminal has no access to a system clipboard, copy/cut/paste keeps working exactly as it does today, scoped to a single session.
- Conflict handling when pasting into a folder that already has a file with the same name is unchanged - same rename-or-cancel prompt as today, regardless of which session the copy/cut came from.

---

# Success Criteria

- [ ] Copying a file in one Neovim session and pasting in a different, already-running session places the file in the new location.
- [ ] Cutting a file in one session, quitting that session, and pasting later (in another session or after reopening Neovim) moves the file, removing it from the original location only once the paste completes.
- [ ] Pressing copy (or cut) again to cancel a pending mark clears the clipboard everywhere, not just in the session where it was cancelled.
- [ ] Multi-file selections copied/cut together in one session paste as the same group in another session.
- [ ] Pasting marked files into a non-explorer text context shows the plain list of paths, same as any normal system copy/paste.
- [ ] Pasting when the system clipboard holds unrelated content does nothing destructive and gives a clear "nothing to paste" message.
- [ ] Pasting a file that no longer exists on disk reports an error for that file instead of failing silently or corrupting the destination.
- [ ] Existing same-session behavior - the `(copy)`/`(cut)` marker, multi-select, and the rename-on-conflict prompt - keeps working exactly as it does today.
- [ ] On setups without system clipboard access, copy/cut/paste keeps working within a single session exactly as it does today.

---

# Out of Scope

- Live-updating the `(copy)`/`(cut)` marker in other already-open sessions the instant a copy/cut (or a cancel) happens elsewhere. It only catches up the next time that session's explorer tree redraws. Deferred because keeping every idle session's marker live would mean each one continuously watches the system clipboard in the background - a lot of always-on machinery for a cosmetic sync detail.
- Syncing the explorer clipboard across different machines (e.g. over SSH between two separate computers). This only reaches as far as the system clipboard already shared between programs on the same machine.
