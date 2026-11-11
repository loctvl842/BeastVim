---
name: packer-install-failure
description: Keep startup fully working when a plugin cannot be installed, and stop retrying known-broken plugins on every start
generated: 2026-11-11
---

# Summary

When one plugin cannot be downloaded (repo is private or removed, no network, no access), the rest of BeastVim must still start normally, the user is told once what failed, and later starts do not pay the cost of retrying the download every time.

---

# Problem

Today, one unreachable plugin damages the whole session in two ways:

- **Setup stops half-way.** The plugins that did download are present, but the remaining startup work is skipped. The user gets an editor where some plugins' settings, keymaps and features are silently missing, with only an error message as a hint.
- **Every start is slow.** The download of the broken plugin is attempted again on every launch and blocks the editor while it tries. Each broken plugin adds roughly 300ms on a good network and more on a bad one, on every single start.
- **The error is noisy and easy to lose.** It appears as a raw error message instead of the usual BeastVim toast.

This was seen for real: three language plugins were private, a CI machine could not download them, and startup went from about 40ms to about 330ms for weeks without anyone noticing, while the config being measured was also only partly set up.

## Why now

The language plugins are separate repositories, so more of them (and more users without access to some of them) will exist. A broken or unreachable plugin should degrade one feature, not the whole editor and not every launch.

---

# Target Behavior

## STATE 1 — First start with a plugin that cannot be downloaded

```
┌──────────────────────────────────────────────────────────┐
│ editor opens normally, everything else works             │
│                                                          │
│                 ┌─────────────────────────────────────┐  │
│                 │  ⚠ Could not install "json"         │  │
│                 │    repository not found or no       │  │
│                 │    access. Skipped for now.         │  │
│                 └─────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

One toast, shown once. All other plugins load and are configured as usual.

## STATE 2 — Later starts, before the retry window ends

```
(no toast, no delay)
Packer UI:

  ✗ json    install failed 2h ago - repository not found
  ✓ python
  ✓ cpp
```

The broken plugin is not downloaded again. It is listed as failed in the Packer window, so the user can see why a feature is missing.

## STATE 3 — Retry succeeds

```
Packer UI after the user presses the install/sync action:

  ✓ json    installed
```

The failure record is cleared and the plugin works from the next start (or immediately if lazy).

---

# Scenarios

## 1 — Happy path: one plugin unreachable

```
Step 1: The user starts BeastVim; "json" cannot be downloaded.
  The editor opens. One warning toast names "json" and says it was skipped.

Step 2: The user opens a Lua file and a Python file.
  Everything behaves as normal: settings, keymaps and language support
  for the other plugins are all present.

Step 3: The user opens a JSON file.
  Only the JSON-specific extras are missing. Basic editing works.
```

## 2 — Next start does not retry

```
Step 1: The user quits and starts BeastVim again shortly after.
  Startup is as fast as with no broken plugin. No toast appears.

Step 2: The user opens the Packer window.
  "json" is shown as failed with the reason and how long ago.
```

## 3 — User fixes the cause and retries

```
Step 1: The user makes the repository reachable (or gets network back)
        and runs the install/sync action in the Packer window.
  The plugin downloads. The failed marker disappears.

Step 2: The user starts BeastVim again.
  "json" loads like any other plugin.
```

## 4 — Retry window expires on its own

```
Step 1: Enough time has passed since the failure (see Behavior Rules).
  The next start tries the download once more.

Step 2a: It succeeds -> a normal "installed" notice, failure marker cleared.
Step 2b: It fails again -> the failure is recorded again, a toast is shown
         once, and the window restarts.
```

## 5 — Several plugins fail

```
Step 1: Two plugins cannot be downloaded.
  One toast lists both names (not one toast per plugin).
  Everything else loads normally.
```

## 6 — No network at all (offline start)

```
Step 1: The user starts BeastVim with no network and plugins that are
        already installed.
  Nothing is attempted for installed plugins. No toast, no delay.

Step 2: A brand-new plugin was added to the config, never downloaded.
  It is reported as failed once, the rest of the config loads.
```

---

# Behavior Rules

- A failed download never stops the remaining plugins from being loaded and configured.
- A failure is reported with the usual BeastVim toast, once per failure, naming the plugin and a short reason. Several failures in one start are combined into one toast.
- A plugin that failed is not downloaded again on later starts until the retry window ends or the user explicitly retries.
- The failure record survives restarts, so quitting and reopening does not trigger another attempt.
- Explicit install/sync/update in the Packer window always retries, regardless of the window, and clears the record on success.
- Removing the plugin from the config, or changing its source, clears its failure record.
- The Packer window shows failed plugins distinctly from not-yet-installed ones, with the reason and age.
- Plugins that are already installed are never affected by another plugin's failure.

---

# Success Criteria

- [ ] With one unreachable plugin, every other plugin still loads and its settings and keymaps are present.
- [ ] A single toast names the failed plugin on the first start; none on later starts inside the retry window.
- [ ] Startup with a known-broken plugin is as fast as without it (no download attempt).
- [ ] The Packer window lists the failed plugin with its reason.
- [ ] Running install/sync in the Packer window retries and, on success, clears the failure.
- [ ] Several failures in one start produce one combined toast.
- [ ] No raw error message is shown for a download failure.

---

# Out of Scope

- Automatically fixing the cause (changing access, mirrors, credentials) - the user does that.
- Retrying in the background while the editor is open - deferred; the explicit action covers it.
- Handling plugins that download fine but crash while loading - a separate concern.
- Changing how CI installs plugins - the CI side was fixed separately.

---

# Open Decisions

- **Retry window length.** Suggested default: 24 hours. Shorter retries sooner after a transient outage; longer saves more startups.
- **Should the toast repeat on retry-failed starts?** Suggested: yes, once per window, so a persistent problem is not forgotten.
