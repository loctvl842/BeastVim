# Health Config — BeastVim

This is a personal Neovim configuration repo (not a service). The standard
"pipelines + ADO bugs" model doesn't apply, so this config is adapted:

- **Pipelines** → GitHub Actions (currently none — placeholder section).
- **Data freshness** → **plugin startup performance**, measured by driving
  `nvim --startuptime` directly from the shell (no plugin needed). For a
  Neovim config, the analogue of "is the data fresh?" is "is startup still
  fast?" — a regression here is the most likely silent failure.
- **Open bugs** → not tracked. This is a personal config; bugs are handled
  ad-hoc, not via an issue tracker.

---

## Pipelines (check daily)

| Pipeline Name | Expected Frequency | Source |
|---|---|---|
| _none yet_ | — | _No CI configured. If `.github/workflows/` is added later, list each workflow here and check its latest run via `gh run list` or the GitHub Actions MCP._ |

If a workflow is added (e.g. `luacheck.yml`, `stylua.yml`), the health check
should fail-loud when its latest run on `main` is failing or older than the
expected frequency.

---

## Data Freshness — Startup Performance

Startup time is the canonical performance signal for a Neovim config. The
measurement is done with **Neovim's built-in `--startuptime` flag** — no
plugin is required. Always use **multiple tries** so the comparison is
against a mean ± std, not a single noisy sample.

| Check | How to verify | Expected |
|---|---|---|
| Cold startup time (mean of 10 tries) | Run the snippet below, take mean of printed numbers. | Mean **< 150 ms**, std **< 20 ms** |
| Slowest single sourcing event | Inspect the largest `self+sourced` value in the dumped startuptime file. | No single plugin **> 30 ms** |
| Startup regression vs last health check | Compare today's mean against the previous `docs/KPI/health-*.md` report's recorded mean. | **< 15 %** increase |

### How to capture startup time

`nvim --startuptime <file>` writes one line per startup event. Each line's
first column is a millisecond clock value; the last event of each session
(`--- VIM STARTED ---`) gives the total startup time. The trick to capture
the *full* startup (including `VimEnter` autocmds and the first screen
update) is to quit via a zero-delay timer rather than `qa!` directly —
otherwise the last few events are missed.

```bash
# 10 cold-start runs, print the final "clock" timestamp of each.
# IMPORTANT: NVIM_APPNAME=BeastVim is required — otherwise this measures
# the user's default ~/.config/nvim config, not BeastVim.
tmp=$(mktemp); : > "$tmp"
for i in $(seq 1 10); do
  NVIM_APPNAME=BeastVim nvim --startuptime "$tmp" \
       -c 'call timer_start(0, {-> execute("qa!")})' >/dev/null
done
# Each run produces TWO sessions in the file: a Primary TUI client (~5ms)
# and the Embedded actual nvim. Skip the Primary by only printing every
# second STARTED marker.
awk '
  /--- N?VIM STARTING ---/ { last=""; session++ }
  /^[0-9]/                 { last=$1 }
  /--- N?VIM STARTED ---/  { if (session % 2 == 0) print last }
' "$tmp"
rm -f "$tmp"
```

Each printed number is one run's total startup time (ms). Take the mean
and std across the 10 runs. The same `tmp` file also contains every
sourcing event with three columns — `clock`, `self+sourced`, `self` — so
the slowest plugin can be found with:

```bash
# Top 10 slowest sourcing events across all runs (column 2 = self+sourced)
awk '/^[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+:/ {
       printf "%s %s\n", $2, substr($0, index($0,": ")+2)
     }' "$tmp" | sort -nr | head
```

### Notes on what's being measured

- Each try is a **full new process** — this is real cold startup including
  `shada` loading and `VimEnter` autocmds, not warm in-process timing.
- The `timer_start(0, qa!)` quit pattern keeps `VimEnter`,
  `before starting main loop`, `first screen update`, and
  `--- NVIM STARTED ---` in the data. A bare `-c qa!` cuts those off.
- Each run writes **two `--- NVIM STARTED ---` sessions**: a Primary
  TUI-client session (~4–5 ms) and the Embedded session (the actual nvim
  startup). The awk session counter above prints only the Embedded
  session. Earlier versions of this snippet matched `--- VIM STARTED ---`
  literally; that pattern does NOT match nvim 0.9+'s `--- NVIM STARTED ---`
  output. Use `--- N?VIM STARTED ---` (with the `?`) so the regex covers
  both old and new nvim.
- 3-column lines are **sourcing events** (`clock`, `self+sourced`, `self`);
  2-column lines are **other events** (`clock`, `elapsed`). `self+sourced`
  is what you want when ranking plugin cost — it includes children.
- If parallel runs ever flake with `E576`/`E886`, disable shada writing
  via a `VimEnter` autocmd: `-c 'autocmd VimEnter * set shada=
  shadafile=NONE'` (this keeps shada *loading* in the measurement but
  skips the *write on exit*).

---

## Per-Lib Performance Breakdown — `beast.profile`

`--startuptime` gives a coarse signal ("total startup is X ms"). When the
total regresses or you want to know *which lib* is the bottleneck, use the
in-tree profiler at `lua/beast/profile.lua`. It instruments every module
matching `^beast%.libs%.` and `^beast%.plugins%.`, tracks call count,
total time, **self time** (excluding instrumented children), min, and
max — for both `require()` and every public function — and dumps a plain
text report on `VimLeavePre`.

### How to capture a profile report

The profiler is gated behind the `BEAST_PROFILE` env var so it has zero
cost in normal use. To capture a startup profile:

```bash
out="$HOME/.cache/BeastVim/beast-profile.txt"
rm -f "$out"
BEAST_PROFILE=1 BEAST_PROFILE_OUT="$out" \
  NVIM_APPNAME=BeastVim nvim --headless \
  -c 'autocmd VimEnter * call timer_start(0, {-> execute("qa!")})'
cat "$out"
```

The same `timer_start(0, qa!)` trick used for `--startuptime` keeps the
full startup sequence in the recording.

### Report format

Two sections, both fixed-width text (easy for humans and AI agents):

```
## Module require times
NAME                              CALLS     TOTAL_MS      SELF_MS    MEAN_US     MAX_US
beast.libs.statusline                 1        7.444        2.207     7443.8     7443.8
...

## Function call times
NAME                              CALLS     TOTAL_MS      SELF_MS    MEAN_US     MAX_US
beast.libs.packer.setup               1       58.075       55.268    58075.2    58075.2
...
```

- **TOTAL_MS** is wall time including instrumented children.
- **SELF_MS** is wall time excluding instrumented children — this is the
  number to rank by when looking for hotspots.
- **CALLS** > 1 with a small mean is fine; **CALLS** > 1 for a `setup`
  function is a smell (something is initializing twice).

### What to flag from a profile report

| Signal | Threshold | Note |
|---|---|---|
| Any `beast.libs.*` require self time | > 5 ms | Either the module is doing heavy work at load, or it's transitively requiring something it shouldn't. |
| Any `*.setup` function self time | > 20 ms | Setup is on the hot path — split out heavy work into a deferred task. |
| Any function `CALLS` count | > expected (e.g. `setup` called > 1) | Indicates a duplicated wiring path. |
| Top-10 functions by self time changed across reports | n/a | Composition shift is a leading indicator of regression. |

### Limitations to be aware of

- Only **Lua** functions are wrapped. Vimscript autocmds and C callbacks
  are invisible to this profiler — `--startuptime` is the right tool for
  those.
- Functions captured by an upvalue (`local require = require`) before our
  hook installs won't be re-routed. For our libs this isn't an issue
  since they all use the global `require`.
- Memory use grows with the number of distinct functions instrumented,
  not with the number of calls — aggregation keeps it bounded.

---

## Run-time Render Performance — `scripts/bench-*.lua`

`--startuptime` and `beast.profile` both measure load-time. Run-time hot
paths (statusline render, completion, etc.) are different — they fire on
every cursor move or keystroke, so even small regressions accumulate into
visible input lag. Each lib that owns such a hot path checks in its own
bench under `scripts/bench-<lib>.lua`. There is no central registry — the
health check globs `scripts/bench-*.lua` and runs each one.

### How to run a single bench

```bash
nvim --clean --headless -l scripts/bench-<lib>.lua
```

### How to run all benches (daily health check)

```bash
fail=0
for f in scripts/bench-*.lua; do
  name=$(basename "$f" .lua | sed 's/^bench-//')
  printf "=== %-20s " "$name"
  if nvim --clean --headless -l "$f" >/dev/null 2>&1; then
    echo "PASS"
  else
    echo "FAIL (exit $?)"
    fail=1
  fi
done
exit $fail
```

For a verbose trace (per-bench output and the final `BENCH …` summary
line), drop the `>/dev/null 2>&1` redirect.

### Contract for new bench scripts

Every `scripts/bench-*.lua` file MUST:

1. Run end-to-end as `nvim --clean --headless -l scripts/bench-<name>.lua`
   (no other flags, no env vars required).
2. Print a final stdout line beginning with `BENCH ` and containing
   space-separated `key=value` tokens — at minimum `name=<lib>`, the
   primary metric, and the `threshold=` used. Example:

   ```text
   BENCH name=statusline beast=12.17us lualine=89.33us ratio=7.3x threshold=1000us
   ```

3. Exit with one of:
   - `0` — PASS (within threshold)
   - `1` — FAIL (threshold exceeded)
   - `2` — setup error (could not open buffer, load module, etc.)

The health check decides PASS/FAIL purely from the exit code — thresholds
and metric definitions live inside each script, so libs own their own
perf contract.

### What to flag

| Signal | Action |
|---|---|
| Any `bench-*.lua` exits 1 | Investigate — a hot-path regressed past its own threshold. Compare against `docs/dev-specs/<lib>.md` § Success Criteria. |
| Any `bench-*.lua` exits 2 | Setup is broken (missing file, refactored API). Fix the bench, not silence it. |
| New lib lands with a hot-path render but no `bench-*.lua` | Standing process gap until added. |

### Existing benches

| Bench | Lib | Primary metric | Notes |
|---|---|---|---|
| `bench-statusline.lua` | `beast.libs.statusline` | full-bar `µs/render` (mean of 3 × 1000) | Opens a real file buffer and waits for `git_commit`'s async `vim.system` callback before timing — measures the cache-hit (steady-state) path. Includes Lualine baseline if `~/.local/share/{LazyVim,nvim}/lazy/lualine.nvim` exists. Hard threshold: 1 ms; soft warn: 50 µs. |

---

## Process Gaps (BeastVim-specific)

In addition to the generic gaps in the skill (stale codemaps, unimplemented
dev specs), check these:

| Gap | How to detect |
|---|---|
| `luacheck` failing | Run `luacheck lua/` from the repo root. `.luacheckrc` is the source of truth. Non-zero exit = flag. |
| `stylua` drift | If `stylua` is installed: `stylua --check lua/`. Skip silently if not installed. |
| Stale codemaps | Read the `<!-- Generated: YYYY-MM-DD ... -->` header in `docs/CODEMAPS/INDEX.md`. Older than **7 days** = flag. |
| Unimplemented dev specs | Files in `docs/dev-specs/` whose latest git mtime is > **14 days** old and that have no corresponding implementation commit. |
| Plugin lockfile drift | If `lazy-lock.json` exists at the runtime path, surface "run `:Lazy check`" as a manual step in the report (don't auto-run — it requires a TUI). |
| Test coverage gap | `tests/` directory is empty. Flag once per report as a standing process gap until tests are added. |

---

## Alert Thresholds

| Signal | Warn | Action required |
|---|---|---|
| Startup mean | > 150 ms | > 200 ms or > 15 % regression vs last report |
| Startup std (10 tries) | > 20 ms | > 40 ms (indicates a flaky plugin) |
| Single sourcing event | > 30 ms | > 60 ms |
| `beast.profile` lib require self time | > 3 ms | > 5 ms |
| `beast.profile` `*.setup` function self time | > 10 ms | > 20 ms |
| `beast.profile` `setup` call count | > 1 | n/a — duplicated wiring is always a bug |
| `scripts/bench-*.lua` exit code | n/a | Any non-zero exit (1 = threshold; 2 = setup error). Each script owns its own thresholds. |
| `luacheck` warnings | > 0 (warn) | non-zero exit (action) |
| Codemap age | > 7 days | > 14 days |

---

## Report History

Daily reports are saved to `docs/KPI/health-YYYY-MM-DD.md`. The "startup
mean" line in each report is the trend signal — a steady creep upward over
several reports is the cue to investigate even if no single report crosses
the action threshold.
