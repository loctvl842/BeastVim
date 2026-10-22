---
name: review
description: Review Claude Code's proposed file changes inside Neovim as an inline Current vs Incoming diff, accept or reject per hunk, and tell Claude the outcome
generated: 2026-10-22
---

# Summary
When Claude Code wants to change a file, the change shows up in the open Neovim buffer as an inline conflict-style diff instead of being written straight to disk. You accept or reject each hunk, and Claude is told what you decided.

---

# Problem

Today Claude Code changes files on disk while Neovim is open. Neovim either shows nothing until you notice, or reloads the buffer and the new text just appears. You cannot review the change before it lands, and if you dislike it you have to undo it by hand. Claude is not told you disliked it, so it carries on as if the change was fine.

Claude Code already has a way to ask an editor "do you approve this change?" before writing anything. Neovim does not speak it yet, so Claude falls back to writing directly.

## Why now
- Reviewing agent edits is now a daily activity, and the buffer you are already looking at is the right place to do it.
- A rejection that Claude actually hears about stops it from repeating the same change.
- The inline diff built here is also what a later feature needs, to review changes made by tools other than Claude (formatters, `git checkout`, other agents).

---

# Target Behavior

## Connecting

Neovim announces itself to Claude Code as an editor. In any terminal in the same project, running `/ide` in Claude Code lists "Neovim" and connects.

```
:Review status

  Review: running
  Claude Code: connected (1 session)
  Project: /Users/me/code/app
```

## A proposed change, STATE 1 - pending review

Claude proposes edits to a file. The file on disk and the buffer text are untouched. Current lines keep their text and get a red band. Incoming lines appear directly below as a green band. A label ends each band.

```
 12  function total(items)
 13 -  local sum = 0                          ← Current
 14 -  for i = 1, #items do                    ← Current
 14 -    sum = sum + items[i].price
 15 -  end
     +  local sum = 0                          ← Incoming (Claude)
     +  for _, item in ipairs(items) do
     +    sum = sum + item.price
     +  end
 16    return sum
 17  end
 ...
 41  local function format(n)
 42 -  return n .. "$"                          ← Current
     +  return string.format("$%.2f", n)       ← Incoming (Claude)
 43  end

 Review: Claude proposes 2 changes - hunk 1/2
```

## STATE 2 - one hunk decided

An accepted hunk becomes normal text in the buffer. A rejected hunk goes back to the Current text. Either way its bands disappear. Undecided hunks stay highlighted.

```
 12  function total(items)
 13    local sum = 0
 14    for _, item in ipairs(items) do
 15      sum = sum + item.price
 16    end
 17    return sum
 18  end
 ...
 42 -  return n .. "$"                          ← Current
     +  return string.format("$%.2f", n)       ← Incoming (Claude)
 43  end

 Review: Claude proposes 1 more change - hunk 2/2
```

## STATE 3 - all decided

When the last hunk is decided the review ends. Bands are gone, the file is saved, and a short notice says what happened.

```
 Review: saved app.lua - 1 accepted, 1 rejected. Claude was told.
```

---

# Scenarios

## 1 - Accept everything

```
Step 1: Claude Code proposes a change to a file that is open in Neovim.
  A notice appears: "Claude proposes 3 changes in app.lua".
  The window showing the file jumps to the first hunk.

Step 2: You press the accept-all key.
  All Incoming text replaces the Current text, bands disappear, the file is saved.

Step 3: Claude Code continues as if it had written the file itself.
  The notice reads "saved app.lua - 3 accepted".
```

## 2 - Review hunk by hunk

```
Step 1: Claude proposes 3 changes. The cursor is on hunk 1.

Step 2: You accept hunk 1.
  Its bands disappear and the cursor moves to hunk 2.

Step 3: You reject hunk 2.
  The Current text stays, bands disappear, cursor moves to hunk 3.

Step 4: You accept hunk 3.
  The file is saved with changes 1 and 3 only.
  Notice: "saved app.lua - 2 accepted, 1 rejected".
```

## 3 - Reject everything

```
Step 1: Claude proposes a change.

Step 2: You press the reject-all key.
  Bands disappear, the buffer and the file are exactly as before. Nothing is saved.

Step 3: Claude Code is told the change was rejected and says so in its session.
  Notice: "rejected app.lua - Claude was told".
```

## 4 - File is not open yet

```
Step 1: Claude proposes a change to a file you do not have open.
  The file opens in the current window as a normal buffer.

Step 2: The diff shows exactly as in the open-file case.
  You review it the same way.
```

## 5 - New file

```
Step 1: Claude proposes a file that does not exist yet.
  A new buffer opens with the proposed name. There is no Current text.
  Every line is Incoming.

Step 2: You accept: the file is created and saved.
  You reject: nothing is created and the empty buffer is closed.
```

## 6 - Several proposals at once

```
Step 1: Claude proposes changes to app.lua and then to util.lua before you reply.
  Two notices appear. Each file shows its own pending hunks.

Step 2: You review the files in any order.
  Deciding one file does not affect the other.

Step 3: Claude proposes a second change to app.lua while the first is still pending.
  The second waits and appears after the first is resolved.
```

## 7 - You have unsaved edits

```
Step 1: You have typed unsaved changes in the buffer.
  Claude proposes a change.

Step 2: The Current side is what is in the buffer right now, including your edits.

Step 3: When the review ends the whole buffer is saved, your edits included.
  The notice says so: "saved app.lua (includes your unsaved edits)".
```

## 8 - Claude cancels or disconnects

```
Step 1: A review is pending. You interrupt Claude, or its session ends.

Step 2: The pending bands disappear. The buffer is exactly as it was.
  Notice: "review of app.lua cancelled by Claude Code".
```

## 9 - You close the buffer mid-review

```
Step 1: A review is pending and you close the buffer.

Step 2: This counts as reject-all.
  Claude is told the change was rejected.
```

## 10 - Nothing is connected

```
Step 1: Neovim is running but Claude Code has not connected.
  Nothing changes. No bands, no notices.

Step 2: You start Claude Code and run /ide, then Neovim shows up.
  From then on its proposals are reviewed in Neovim.
```

---

# Behavior Rules

- Nothing is written to disk until the review of that file ends with at least one accepted hunk.
- The buffer text never contains conflict markers. Bands and labels are display only, so a stray save can never write them into your file.
- The review ends when every hunk has a decision. If at least one hunk was accepted, the file is saved and Claude is told the file was saved. If none were accepted, Claude is told the change was rejected.
- With a partial accept, the saved file differs from what Claude proposed. Claude is told "saved", and may not realise only part was applied. It will see the real content the next time it reads the file. This is the one place Claude's picture of the file can briefly be wrong.
- Keys act on the hunk under the cursor, with next and previous hunk navigation, plus accept-all and reject-all for the file. All keys are buffer-local, only active while a review is pending, and can be changed in config.
- The notice and the "hunk 1/2" message use the existing notification style.
- Neovim only starts listening if you opt in through config. It listens on this machine only and requires the secret token Claude Code reads from the discovery file. Other programs on the machine cannot connect without reading that file.
- Several Neovim instances can run at once. Claude Code picks the one whose project folder matches where it was started.
- When Neovim exits, it removes its discovery file. If Neovim crashes, a stale file may remain. Claude Code ignores entries whose process no longer exists.
- Highlights follow the colorscheme and reuse the look of the merge-conflict bands (red Current, green Incoming) without depending on the git feature.
- The way Claude Code talks to editors is not officially documented. It was worked out from the VS Code extension and the existing community plugin. A Claude Code update could change it. If Claude Code stops connecting, `:Review status` should say why, such as "no connection in the last N minutes".

---

# Success Criteria

- [ ] After `/ide`, Claude Code lists Neovim and connects.
- [ ] A proposed change to an open file shows as Current and Incoming bands, with no markers in the buffer text.
- [ ] Each hunk can be accepted or rejected individually, and all at once.
- [ ] Accepting everything writes the proposed content and Claude continues normally.
- [ ] Rejecting everything leaves the file exactly as it was, and Claude reports the rejection.
- [ ] A partial decision saves only the accepted hunks.
- [ ] Unopened files and new files can be reviewed too.
- [ ] Two files can be reviewed independently, and a second proposal for the same file waits its turn.
- [ ] Closing the buffer, or Claude cancelling, never leaves stuck bands or a half-written file.
- [ ] Without opt-in, nothing listens and startup is unaffected.
- [ ] `:Review status` always shows whether it is running and whether Claude Code is connected.

---

# Out of Scope

- Reviewing changes made by tools other than Claude Code (formatters, `git checkout`, other agents, edits on disk while no review was requested). A later feature, which will reuse these bands. For that feature, rejecting means writing the buffer's content back to disk.
- Telling Claude about decisions through any other channel (log file, `--listen` socket).
- Sending your selection, open files, or diagnostics to Claude. Only what is needed to make the review work is included.
- Side-by-side or separate-tab diff layouts. This is inline only.
- Editing the incoming text before accepting it.
- Session history of past reviews.
- Support for other agents' editor protocols.
