---
name: tec-health
description: "Daily health check for BeastVim. Measures startup time, runs per-lib profiles and bench scripts, checks linters and codemap freshness, and saves a dated report. Use when asked 'how is the project doing', 'health check', 'morning check', 'project status', 'anything need attention'."
---

# Daily Health Check — BeastVim

Run a quick, project-shaped health check across the signals that actually matter for a personal Neovim config: **startup performance, per-lib profile, run-time benches, lint/format drift, and codemap freshness**.

This skill is the **runner**. The thresholds, snippets, and BeastVim-specific gaps live in [`docs/tec-config/health-config.md`](../../../docs/tec-config/health-config.md) — that file is the source of truth for *what* to check; this skill defines *how* the check flows and *what* the report looks like.

## Input

The user can just say "health check" or "what needs attention today?" — no other input is needed.

## Step 0: Load Health Config

Read `docs/tec-config/health-config.md` from the repo root.

**If the file is missing — STOP.** Tell the user it must exist before this skill can run, and point them at the template inside that file's history.

Extract from `health-config.md`:

- The `--startuptime` measurement snippet and the **mean / std / single-sourcing-event** thresholds.
- The `beast.profile` capture snippet and its **per-module** and **per-function** thresholds.
- The list of `scripts/bench-*.lua` scripts to run (glob `scripts/bench-*.lua`).
- The **process gap** checks (stylua, codemap age, dev-spec staleness, plugin lockfile drift, empty tests directory).
- The **alert thresholds** table at the bottom — both *warn* and *action required* levels.

Do **not** invent thresholds. If `health-config.md` doesn't define a threshold for something, omit it from the report rather than guessing.

## Step 1: Startup Time (10-run cold mean)

Run the snippet from `health-config.md` § *Data Freshness — Startup Performance*. It launches `nvim --startuptime` 10 times under `NVIM_APPNAME=BeastVim` and prints one total per run.

From the 10 numbers compute:

- **mean** and **std**
- the **slowest single sourcing event** across all runs (rank `self+sourced` column)

Compare against:

- the warn / action thresholds in `health-config.md` § *Alert Thresholds*
- the **previous report's recorded mean** (read the most recent `docs/KPI/health-*.md` and grep for `Startup mean`). Flag if today's mean is > 15 % higher.

## Step 2: Per-Lib Profile (`beast.profile`)

Run the `BEAST_PROFILE=1` capture snippet from `health-config.md` § *Per-Lib Performance Breakdown*. Read the report file it dumps (default `~/.cache/BeastVim/beast-profile.txt`).

Apply each row from `health-config.md`'s "What to flag from a profile report" table:

- any `beast.libs.*` require `SELF_MS` over its threshold
- any `*.setup` function `SELF_MS` over its threshold
- any function with a `CALLS` count above what's expected (especially `setup` called more than once — that's always a bug)

Surface the offenders with their numbers, not just a yes/no.

## Step 3: Run-time Benches

Glob `scripts/bench-*.lua` and run each one with:

```bash
nvim --clean --headless -l scripts/bench-<name>.lua
```

Decide PASS / FAIL **purely from the exit code** (the bench owns its own thresholds — see the contract in `health-config.md`):

- `0` → PASS — record the final `BENCH …` summary line
- `1` → FAIL (threshold exceeded) — surface the `BENCH …` line and flag for action
- `2` → setup error — flag as a separate, higher-severity item; the bench is broken and silently passing would be worse than a real regression

If `scripts/bench-*.lua` matches nothing, surface that as a process gap ("no run-time benches defined yet"), not as a pass.

## Step 4: Lint & Format

From `health-config.md` § *Process Gaps*:

- **stylua** — if `stylua` is on `$PATH`, run `stylua --check lua/`. Non-zero exit → flag (drift). If `stylua` isn't installed, **skip silently** — don't surface "tool not installed" as a finding.

## Step 5: Codemap & Dev-Spec Freshness

- Read `docs/CODEMAPS/INDEX.md`'s `<!-- Generated: YYYY-MM-DD ... -->` header. Compare against today.
  - **> 7 days** → warn
  - **> 14 days** → action
- List `docs/dev-specs/*.md` and check each file's git mtime. Any spec **> 14 days old** with no implementation commit on its phases → flag as "unimplemented dev spec".

## Step 6: Other Process Gaps

The remaining rows of `health-config.md` § *Process Gaps* (BeastVim-specific):

- **Empty `tests/` directory** — flag as a *standing* process gap until tests exist. One line per report, no escalation.

## Step 7: Generate and Save Report

Save to `docs/KPI/health-YYYY-MM-DD.md` (create `docs/KPI/` if missing).

Use this exact structure so reports are diffable across days and the trend lines (especially **Startup mean**) can be grepped across the directory:

```markdown
# Daily Health Report — YYYY-MM-DD

## Summary

🟢 / 🟡 / 🔴 — one-line verdict

## 🟢 / 🟡 / 🔴 Startup Performance

- Startup mean: **N.NN ms** (std N.NN, 10 runs)
- vs last report (YYYY-MM-DD): +N.N % / -N.N %
- Slowest single sourcing event: `<plugin/file>` — N.NN ms

## 🟢 / 🟡 / 🔴 Per-Lib Profile

- Top offender by SELF_MS: `<module>` — N.NN ms
- Functions over their threshold: <list or "none">
- Duplicated `setup` calls: <list or "none">

## 🟢 / 🟡 / 🔴 Run-time Benches

| Bench | Result | Summary |
|---|---|---|
| statusline | PASS | `BENCH name=statusline beast=12.17us …` |

## 🟢 / 🟡 / 🔴 Lint & Format

- stylua: PASS / FAIL / skipped (not installed)

## 🟢 / 🟡 / 🔴 Codemap & Dev-Spec Freshness

- Codemaps generated: YYYY-MM-DD (N days ago)
- Stale dev specs: <list or "none">

## ⚠️ Process Gaps

- <gap description, one bullet each>

## Action Items

1. [severity] <action — file/line if applicable>
```

Use the legend:
- 🟢 — within warn threshold
- 🟡 — between warn and action threshold (or any *manual* item)
- 🔴 — past the action threshold (or any setup-error / FAIL)

The section colour is the **worst** signal inside that section. The summary's colour is the worst across all sections.

## Step 8: Offer Next Steps

Match the suggestion to the actual finding — don't suggest unrelated skills:

- Startup regression > 15 % vs last report → `"Rerun the per-lib profile (Step 2) to find the new offender."`
- Bench exit code 1 → `"Investigate the failing bench. Compare against docs/dev-specs/<lib>.md § Success Criteria."`
- Bench exit code 2 → `"Bench setup is broken — fix the script before the next run, don't silence it."`
- Stale codemap → `"Run /tec-update-codemaps to regenerate."`
- Stale dev spec with no impl → `"Run /tec-implement docs/dev-specs/<file>.md to pick up where you left off, or close the spec out."`

## Scope

`tec-health` does **one thing**: surface health signals from BeastVim's own measurements and save a dated report.

It does **NOT**:

- Diagnose *why* startup regressed (run `beast.profile` again manually)
- Fix anything (no auto-edits, no auto `stylua` runs)
- Push or commit the saved report (the user reviews and commits it)
