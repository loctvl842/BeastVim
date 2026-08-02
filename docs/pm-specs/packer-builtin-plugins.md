---
name: packer-builtin-plugins
description: Mark plugins that ship with BeastVim by default in the Packer UI, and block them from deletion
generated: 2026-08-02
---

# Summary

In the Packer dashboard, plugins that ship with BeastVim by default (like
`blink.cmp`) are visually marked as builtin. Pressing `x` on a builtin plugin
is blocked, same as it already is for libraries - but pressing `u` still
updates it normally, since staying up to date is safe and deleting it isn't.

---

# Problem

Every plugin row in the Packer UI looks the same today, whether the user
installed it themselves or it came bundled with BeastVim. Pressing `x` deletes
any plugin immediately and without confirmation - including ones BeastVim
depends on internally, like the completion engine. There's nothing in the UI
that tells the user "this one is different, removing it removes a piece of
BeastVim itself, not just something you added."

## Why now

Delete already ships and applies uniformly to every plugin row. That's the
right behavior for plugins the user chose to install, but it's a trap for the
handful of plugins BeastVim ships with by default - deleting `blink.cmp`
doesn't feel like "I removed my own plugin," it silently breaks completion.
Marking these plugins and blocking their deletion closes that gap before it
causes a real incident.

---

# Target Behavior

```
STATE 1 — Home page, blink.cmp is builtin and loaded:

┌──────────────────────────────────────────────────────────────┐
│  🦁 Packer                                                    │
│                                                                │
│   Total: 42 plugins · 3 libraries   Sort: Name                │
│                                                                │
│   Loaded (28 plugins, 3 libraries)                            │
│    ★ ✓ blink.cmp                  (12.4ms)                    │
│      ✓ gitsigns.nvim                (3.1ms)                   │
│    󰂖 ✓ explorer                     (1.8ms)                   │
│      ...                                                      │
│                                                                │
│   Not Loaded (14 plugins)                                     │
│      ○ neotest                     event BufReadPost          │
│      ○ vim-dadbod                  cmd :DB                    │
│      ...                                                      │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│ <CR> Load   S Sort   x Delete   u Update   ? Help   q Close   │
└──────────────────────────────────────────────────────────────┘

The ★ badge marks blink.cmp as builtin. 󰂖 (unchanged) still marks explorer as
a library. The two badges never appear on the same row - a row is either a
plugin (builtin or not) or a library.

─────────────────────────────────────────────────────────────────

STATE 2 — Cursor on blink.cmp, user presses x:

│    ★ ✓ blink.cmp                  (12.4ms)  ← cursor here      │

  Toast (bottom right): "blink.cmp is a builtin plugin and can't be deleted"

  Nothing else changes - blink.cmp stays in Loaded, no confirmation prompt
  was shown, no plugin was removed.

─────────────────────────────────────────────────────────────────

STATE 3 — Cursor on blink.cmp, user presses u instead:

│    ★ ✓ blink.cmp                  (12.4ms)  ← cursor here      │

  Update proceeds exactly like it would for any ordinary plugin - the
  Operations section shows the update running, then its result. Being
  builtin has no effect on u at all.
```

---

# Scenarios

## 1 — Spotting a builtin plugin at a glance

```
Step 1: User opens the Packer dashboard.
  Loaded and Not Loaded sections render as usual.

Step 2: User scans the Loaded section for blink.cmp.
  It has a ★ badge to the left of its name, same row layout as every
  other plugin otherwise (loaded check, name, timing).

Step 3: User scrolls to Not Loaded.
  Any builtin plugin that happens to not be loaded yet shows the same ★
  badge there too - builtin marking doesn't depend on load state.
```

## 2 — Trying to delete a builtin plugin

```
Step 1: User moves the cursor onto blink.cmp's row (marked ★).

Step 2: User presses x, the same key that deletes any other plugin.
  A toast appears: "blink.cmp is a builtin plugin and can't be deleted."

Step 3: User checks the Loaded section.
  blink.cmp is still there, unchanged. No confirmation dialog was ever
  shown - the block is immediate, matching how library rows already
  refuse x today.
```

## 3 — Updating a builtin plugin works normally

```
Step 1: User moves the cursor onto blink.cmp's row.

Step 2: User presses u.
  The update runs exactly as it would for any non-builtin plugin - no
  special-casing, no toast blocking it.

Step 3: Update finishes.
  Operations section reports success or failure the normal way.
```

## 4 — Deleting an ordinary (non-builtin) plugin is unaffected

```
Step 1: User moves the cursor onto gitsigns.nvim (no ★ badge).

Step 2: User presses x.
  gitsigns.nvim is deleted immediately, moves into the Deleted section -
  identical to today's behavior. Builtin marking only changes what
  happens to plugins that have the badge.
```

## 5 — Builtin badge vs. library badge never collide

```
Step 1: User moves the cursor onto explorer (library row, 󰂖 badge).

Step 2: User presses x.
  Toast: "explorer is a library and can't be deleted" - the existing
  library message, unchanged by this feature.

Step 3: User presses u on explorer.
  Toast: "explorer is a library and can't be updated" - also unchanged.
  Libraries still block both actions; builtin plugins only block delete.
```

---

# Behavior Rules

- The builtin badge appears on a plugin row regardless of loaded/not-loaded
  state - marking is a property of the plugin, not its current status.
- Pressing `x` on a builtin plugin always shows a toast and never deletes it,
  with no confirmation prompt (consistent with the no-confirmation delete
  model already shipped).
- Pressing `u` on a builtin plugin is never blocked - it behaves exactly like
  updating any ordinary plugin.
- A row is exactly one of: an ordinary plugin, a builtin plugin, or a library.
  Builtin and library are mutually exclusive - libraries are a separate
  registry (`packer.lazy()` entries) and were never buildable/deletable
  candidates in the first place.
- Builtin marking is informational plus a delete guard - it never affects
  load order, lazy triggers, or profiling data shown for the plugin.

---

# Success Criteria

- [ ] Builtin plugins (e.g. `blink.cmp`) are visually distinguishable from
      user-added plugins in both the Loaded and Not Loaded sections.
- [ ] Pressing `x` on a builtin plugin never deletes it; a toast explains why,
      with no confirmation dialog.
- [ ] Pressing `u` on a builtin plugin updates it exactly like any other
      plugin - no blocking, no special message.
- [ ] Non-builtin plugins keep working exactly as before for both `x` and `u`.
- [ ] Library rows keep their existing behavior unchanged (both `x` and `u`
      still blocked with their existing messages).

---

# Out of Scope

- The exact list of which plugins count as builtin (just `blink.cmp`, or a
  broader set) - that's a maintenance detail for whoever wires up the list,
  not a product behavior.
- Blocking `u` (update) for builtin plugins - explicitly allowed by this spec.
- Any confirmation dialog before delete, for builtin or ordinary plugins -
  stays "no confirmation," matching the existing delete spec.
- Letting the user edit or toggle the builtin list from inside the UI - it's
  a static, developer-maintained list, not user-editable at runtime.
