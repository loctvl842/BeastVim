---
name: session-init
description: Auto-saves the working session on quit, keyed by project dir + git branch, with a manual load API
generated: 2026-07-20
---

# Summary

Session automatically saves the user's open buffers/layout when they quit Neovim, keyed by the current project directory and (for non-main/master) the git branch. The user manually loads it back with one command when they reopen the project.

---

# Problem

Today, closing Neovim loses the working layout — open files, splits, cursor positions. Reopening a project means manually re-finding and reopening every file that was open before. There's no built-in way to pick up exactly where the user left off, per project and per branch, without adopting a whole session-switching workflow the user doesn't want.

## Why now

The user's daily flow is: `cd` into a project, launch Neovim fresh for that directory, and optionally restore that project's last state. They don't want session pickers, "last session," or cross-directory switching — just a save that quietly happens on quit, and a load they trigger themselves when they want it.

---

# Target Behavior

There is no visible UI. The feature is entirely invisible during normal use — it only changes what happens at two moments: quitting, and running the load command.

```
STATE 1 — Normal editing:
  Nothing to see. No indicator, no statusline element, no prompt.

─────────────────────────────────────────
STATE 2 — Quitting Neovim (:q, :qa, closing terminal, etc.):
  Neovim exits normally. Behind the scenes, the current buffer/window
  layout is saved to a file identified by the project directory
  (and git branch, if not on main/master). No message, no delay
  the user notices.

─────────────────────────────────────────
STATE 3 — User runs the load command after reopening:
  :lua require("session").load()

  If a matching saved session exists, all its buffers/splits open
  exactly as they were left. If nothing was ever saved for this
  directory (+branch), nothing happens — the user is left with
  whatever Neovim already showed (e.g. an empty buffer or dashboard).
```

---

# Scenarios

## 1 — First time in a project, quit and reopen

```
Step 1: User runs `cd ~/code/my-project` then `NVIM_APPNAME=BeastVim nvim`
  Neovim opens as normal (no prior session exists for this dir).

Step 2: User opens a couple of files, arranges some splits, then quits.
  On exit, the layout is silently saved, keyed to `~/code/my-project`
  (no branch suffix, since they're on `main`).

Step 3: Later, user runs `cd ~/code/my-project` then `nvim` again,
  then types `:lua require("session").load()`.
  All previously open files and splits reappear exactly as left.
```

## 2 — Working on a feature branch

```
Step 1: Inside `~/code/my-project`, user checks out branch `feature/login`.
  They open files relevant to that feature and quit.
  The session is saved keyed to `~/code/my-project` + branch `feature/login`,
  separate from the `main`-branch (no-suffix) session.

Step 2: User switches back to `main`, opens different files, quits.
  This save goes to the no-suffix `~/code/my-project` session —
  the `feature/login` session from Step 1 is untouched.

Step 3: User later checks out `feature/login` again, opens Neovim,
  runs `:lua require("session").load()`.
  The `feature/login`-specific layout is restored, not the `main` one.
```

## 3 — Branch session doesn't exist yet, falls back to project session

```
Step 1: User creates a brand new branch `feature/new-thing` for the first
  time and opens Neovim in that state — no session has ever been saved
  for this exact branch.

Step 2: User runs `:lua require("session").load()`.
  No `feature/new-thing`-specific session file exists, so the plain
  project-level session (the one without a branch suffix) is loaded
  instead, if one exists.

Step 3: If neither the branch-specific nor the plain project session
  exists, the load command does nothing. Neovim stays exactly as it
  was — no error, no message.
```

## 4 — Quitting with nothing open

```
Step 1: User launches Neovim in a project directory but never opens a
  real file — e.g. only sees a start screen — then quits immediately.

Step 2: No session is saved for this quit. Whatever session already
  existed for this directory (+branch) from a previous, real editing
  session is left untouched — it is not overwritten with an empty one.
```

---

# Behavior Rules

- Saving happens automatically and only on quitting Neovim — there is no manual save command and no periodic/background save.
- The session is identified by the current working directory. If the directory is a git repo on a branch other than `main` or `master`, the branch name is also part of the identity; `main`/`master` (and non-git directories) share the same plain, no-suffix identity.
- A quit only saves if at least one real file buffer is open at the time. Quitting with zero real file buffers open leaves any existing saved session for that directory (+branch) untouched.
- Loading is always manual — the user explicitly triggers it. Nothing is ever auto-restored on startup.
- Loading always targets the current directory (+ current branch) — there is no cross-directory session switching, no "last session," and no session picker.
- If no session was ever saved for the exact current directory + branch, loading falls back to the plain (no-branch) session for that directory, if one exists.
- If no session exists for either the branch-specific or the plain identity, loading is a silent no-op.
- The user can also check, without loading, whether a session exists for the current directory + branch (accounting for the same fallback-to-plain-session rule) — useful for the user's own config logic (e.g. deciding whether to show a hint).

---

# Success Criteria

- [ ] Quitting Neovim after editing at least one real file silently saves the layout for the current dir (+ branch, unless main/master).
- [ ] Quitting with no real file buffers open never overwrites a previously saved session.
- [ ] `:lua require("session").load()` restores the exact layout last saved for the current dir + branch.
- [ ] On a branch with no session of its own, `load()` falls back to the plain project-level session instead of doing nothing.
- [ ] `load()` is a no-op with no error when nothing has ever been saved for the current dir (in either branch-specific or plain form).
- [ ] A way to check session existence for the current dir + branch (with the same fallback rule) is available, without triggering a load.
- [ ] main/master branches never produce a separate suffixed session file — they always share the plain project-level session.

---

# Out of Scope

- Auto-restoring a session on startup — the user starts from a blank/dashboard state and loads explicitly.
- Listing, browsing, or picking between multiple saved sessions.
- Loading the "last" session regardless of directory.
- Switching to a different project directory's session from within a running Neovim instance.
- Any UI, statusline indicator, or notification around saving/loading.
- Configuring what session data gets captured (relies on Neovim's own session behavior).
