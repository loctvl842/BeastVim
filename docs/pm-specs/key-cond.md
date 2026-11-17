---
name: key-cond
description: A keymap can carry a condition (true/false, or a check that may run an external command); a keymap whose check is still running exists as a placeholder that only shows a toast
generated: 2026-11-17
---

# Summary

A keymap can declare a `cond`. If the condition is false, the keymap does not exist. The condition can be a plain true/false, a quick check, or a slow check that runs an external command. For a slow check the keymap is registered right away as a placeholder: pressing it only shows a "still checking" toast. When the check says yes, the placeholder becomes the real keymap. When it says no, fails, or times out, the keymap is removed and a notification explains why.

---

# Problem

Some keymaps only make sense in certain situations: "only if `gh` is installed", "only if this folder is a git repo", "only if a tool answers `ok`". Today the config author has two bad choices:

- Register the keymap always. It shows up in the hint and cheatsheet, and pressing it fails with an error or does nothing.
- Wrap the registration in an `if` by hand. When the check needs an external command, the only simple way to get its answer is to block the editor until the command ends, which delays startup.

## Why now

A keymap whose check needs an external command is the case that exposes the gap. Without a built-in condition that can wait for a command without blocking, every such keymap would pay the cost in startup time or leave a dead key in the hint.

---

# Target Behavior

```
STATE 1 — Condition is true (or a quick check answers true):
  Press <leader>  ->  hint popup

  ┌─ <leader> ───────────────┐
  │  f   Files               │
  │  g   Git                 │
  │  gp  Pull requests       │   <- real keymap
  └──────────────────────────┘

─────────────────────────────────────────
STATE 2 — Condition is false (boolean or quick check):
  Press <leader>  ->  hint popup

  ┌─ <leader> ───────────────┐
  │  f   Files               │
  │  g   Git                 │
  └──────────────────────────┘      <- no "gp": not in hint, not in cheatsheet

─────────────────────────────────────────
STATE 3 — Slow check still running (external command not finished):
  The keymap exists at once, as a placeholder. The editor is fully usable.

  ┌─ <leader> ───────────────┐
  │  f   Files               │
  │  g   Git                 │
  │  gp  Pull requests       │   <- listed, but a placeholder
  └──────────────────────────┘

  User presses <leader>gp:

                         ┌────────────────────────────────┐
                         │ Pull requests: still checking  │   <- toast, nothing else happens
                         │ (is `gh` available?)           │
                         └────────────────────────────────┘

─────────────────────────────────────────
STATE 4 — Slow check answers yes:
  The placeholder silently becomes the real keymap. Pressing <leader>gp now runs it.

─────────────────────────────────────────
STATE 5 — Slow check answers no, fails, or times out:
  ┌────────────────────────────────────────────┐
  │ <leader>gp disabled: check timed out (10s) │   <- notification
  └────────────────────────────────────────────┘

  ┌─ <leader> ───────────────┐
  │  f   Files               │
  │  g   Git                 │
  └──────────────────────────┘      <- the placeholder is gone
```

What a config author writes (the three forms):

```
cond = true                         -- boolean: fixed answer, no placeholder
cond = function() ... return ok end -- quick check: answers right away, no placeholder
cond = function(done) ... done(ok) end
                                    -- slow check: placeholder until done(ok) is called
```

A function that returns true or false is a quick check. A function that returns nothing and calls `done` later is a slow check.

---

# Scenarios

## 1 — Boolean condition

```
Step 1: Author sets cond = false on a keymap.
  The keymap is not registered. It is absent from the hint and the cheatsheet.

Step 2: Author sets cond = true (or leaves cond out).
  The keymap behaves exactly as today.
```

## 2 — Quick function condition

```
Step 1: Author writes cond = function() return vim.fn.executable("gh") == 1 end
  The function is called once when the keymap is being registered.

Step 2: It returns true.
  The keymap is registered at once as the real keymap.

Step 3: It returns false.
  The keymap is not registered.
```

## 3 — Slow condition that waits for an external command (happy path)

```
Step 1: Neovim starts. The keymap has a slow condition.
  The keymap is registered at once as a placeholder. Startup does not wait
  for the command.

Step 2: The external command runs in the background.
  The user types, moves, opens files as normal. <leader>gp is listed in the hint.

Step 3: The command ends and the condition answers "yes".
  The placeholder becomes the real keymap, silently. The next press of
  <leader>gp runs the real action.
```

## 4 — Pressing the placeholder while the check runs

```
Step 1: The user presses <leader>gp before the check finished.
  A toast says the keymap is still being checked. Nothing else happens.

Step 2: The user presses it again.
  Same toast (it stacks as "x2" like any repeated toast). The press is not remembered:
  when the check ends with yes, the action does not run on its own.
```

## 5 — Slow condition answers no

```
Step 1: The command answers no.
  The placeholder is removed. It disappears from the hint and the cheatsheet.
  No notification: "no" is the intended outcome of a condition.
```

## 6 — Slow condition fails or hangs

```
Step 1: The external command is not installed, exits with an error, or the
        condition function itself raises an error.
  Treated as no. The placeholder is removed and a notification names the
  keymap and the reason.

Step 2: The command never ends.
  After 10 seconds the check is abandoned. The placeholder is removed and a
  notification says the check timed out.
```

## 7 — Buffer-local keymap

```
Step 1: A keymap with buffer = true and a slow cond is registered for buffer 7.
  A placeholder is set in buffer 7 only.

Step 2: The same keymap spec is attached to buffer 9 (e.g. a second LSP attach).
  The condition is checked again for buffer 9, with its own placeholder and answer.

Step 3: Buffer 7 is closed while its check is still running.
  The late answer is thrown away. Nothing is registered, no error, no notification.
```

## 8 — Keymap deleted or replaced while its check runs

```
Step 1: A placeholder is still pending when the author deletes that keymap.
  It is removed as today. The late "yes" does not bring it back.

Step 2: A placeholder is pending and a newer registration of the same keys replaces it.
  The older check's answer is thrown away. The newer registration has its own check.
```

---

# Behavior Rules

- `cond` is optional. A keymap without it behaves exactly as today.
- A boolean or a quick function answers at once. A "no" means the keymap is never registered: not in the hint, the cheatsheet or the conflict check.
- Only a slow check (a function that calls `done` later) creates a placeholder. A function that returns true/false is quick and never creates one.
- A placeholder is a real entry for the hint, the cheatsheet and conflict checks. It keeps the keymap's description. Pressing it only shows a toast, whatever the original action was.
- A yes replaces the placeholder with the real keymap. A no, an error or a timeout removes the placeholder.
- A plain "no" is silent. An error or a timeout produces a notification, once per keymap.
- The condition is checked once per registration (once per buffer for buffer-local keymaps). No live re-checking when the outside world changes.
- A slow function answers by calling `done` with true or false. A quick function answers by returning. Never both.
- Anything other than a clear "yes" counts as "no": `nil`, an error, a timeout, a failed command.
- The editor never blocks on a condition. A slow condition never delays startup and never freezes input.
- The limit for a slow answer is 10 seconds.
- A late answer for a keymap that was deleted, replaced, or whose buffer is gone is thrown away.
- Pressing a placeholder never queues the action for later.
- `cond` is not passed to Neovim as a key option; it only decides whether the keymap is registered.
- A label-only entry (a group name with no action) can carry `cond` too. It has no action to block, so it gets no placeholder: it is listed once the check says yes.

---

# Success Criteria

- [ ] A keymap with `cond = false`, or a quick check answering false, is absent from the hint popup and the cheatsheet.
- [ ] A keymap with `cond = true`, or no `cond`, is unchanged from today.
- [ ] A keymap with a slow check exists right after registration, with no added startup time.
- [ ] Pressing a pending placeholder shows a "still checking" toast and does nothing else.
- [ ] After a slow "yes" the same keys run the real action, with no restart.
- [ ] After a slow "no" the keymap disappears from the hint and the cheatsheet without a notification.
- [ ] After an error or timeout the keymap disappears and one notification explains why.
- [ ] While a slow check runs the editor stays responsive.
- [ ] Buffer-local keymaps are checked per buffer, and a closed buffer's late answer is ignored.
- [ ] Deleting or replacing a keymap while its check runs is not undone by the late answer.

---

# Open Decisions

1. **Notification on a plain "no".** Proposal: silent, since "no" is the intended outcome (for example `gh` is simply not installed). Alternative: always notify when a placeholder is removed. The user's wording asked for a notification on timeout, so the proposal notifies only on error or timeout.
2. **Timeout length.** 10 seconds is the proposal. Shorter makes a slow machine lose keymaps; longer keeps a placeholder around for longer.
3. **Placeholder in the hint.** Proposal: listed like any keymap, with no special mark. Alternative: dimmed with a "checking" tag, which is more honest but adds a visual state.

---

# Out of Scope

- Re-checking a condition later (when a folder changes, when a tool is installed after startup). Deferred: one check per registration keeps behavior predictable. A reload re-checks.
- Running the action automatically after a late "yes". Deferred: surprising to run something the user pressed seconds ago.
- Sharing one external command's answer between many keymaps. Deferred: authors can compute the answer once in their own config and read it from each `cond`.
- Conditions on removal (`cond` deciding when to delete). Out: deletion stays explicit.
