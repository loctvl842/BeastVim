# Benchmarking — bench contract, inventory, and workflow recipes

> See also: [`bench-ux.md`](./bench-ux.md) for the wezterm UX harness deep-dive, [`writing-benches.md`](./writing-benches.md) for adding new benches, [`bench-ci.md`](./bench-ci.md) for the GitHub Actions startup-history dashboard, [`glossary.md`](./glossary.md) for terms.

This is the reference for **what** benches exist, **what** they measure, **what** to run when something changes, and **what** "passing" means.

---

## The bench contract

Every bench script in `scripts/` (headless and wezterm alike) obeys the same convention so they're shell-pipeable and CI-friendly:

| Rule | Enforcement |
|---|---|
| Final stdout line starts with `BENCH ` | grep / awk-friendly summary |
| Includes `name=<short-id>` | distinguishes one bench from another |
| Includes primary metric + threshold | `p50=X.YZms threshold=Nms` |
| Exit `0` PASS, `1` FAIL (threshold tripped), `2` setup error | scriptable gates |
| Side-channel chatter goes to stderr | clean stdout, grep-friendly |

Stuck on a regression? **The `BENCH` line is the only thing CI looks at.** Everything above it is human-debug context.

---

## Bench inventory

### Component benches (headless, isolated)

Each runs in `nvim --clean --headless -l <file>`, stubs out the parts of BeastVim it doesn't need, and measures one lib in isolation. Threshold tuned for Apple Silicon; bump in-file when hardware genuinely changes.

| Script | Lib under test | Primary metric | Threshold | Notes |
|---|---|---|---|---|
| `bench-startup.sh` | full config | startup mean (10 runs) | mean **< 150 ms**, steady **< 50 ms** | `MODE=warm\|cold\|mixed`, slowest sourcing event surfaced; appends hyperfine wall-clock + JSON export if installed |
| `bench-git.lua` | `beast.libs.git.diff` | `compute_hunks` p50 on 5k lines | **< 10 ms** | pure hunk-diff cost, no event wiring |
| `bench-breadcrumb.lua` | `beast.libs.breadcrumb` | full winbar render p50 | **< 1000 µs** (warn: 50 µs) | proxy for cursor-move cost |
| `bench-explorer.lua` | `beast.libs.explorer` | mixed-scenario render p50 | **< 2000 µs** (warn: 500 µs) | full tree paint |
| `bench-finder-matcher.lua` | `beast.libs.finder.matcher` | match on 90k items | full-scan **< 80 ms**, subset path **< 50 ms** | 1-char vs 3-char paths |
| `bench-statuscolumn.lua` | `beast.libs.statuscolumn` | per-line median (200 lines × 1000 renders) | **< 5 µs/line** (warn: 2 µs) | per redraw §3 cost driver — keep this lean |
| `bench-statusline.lua` | `beast.libs.statusline` | full-bar render p50 | **< 1000 µs** (warn: 50 µs) | compares against lualine if installed |
| `bench-tabline.lua` | `beast.libs.tabline` | full-bar render p50 | **< 1000 µs** (warn: 50 µs) | compares against bufferline if installed |
| `bench-key-hint.lua` | `beast.libs.key.hint` | `hint_open` p50 + `index_build` p50 | open **< 5 ms**, index **< 500 µs** | trigger → window-visible proxy |
| `bench-context.lua` | `beast.libs.treesitter.context` | single-window refresh p50 (get + full render) | **< 2000 µs** (warn: 800 µs) | sticky-context cost per `WinScrolled`/`CursorMoved` (throttled ≤2×/150ms); also reports no-change render + multiwindow tick |

### End-to-end benches (real wezterm pane, real keystrokes)

Spawn a real nvim in a real wezterm pane, drive keys via `wezterm cli send-text`, and time **key-to-paint latency** — the closest proxy for perceived UX. Must be run from inside an existing wezterm session so the cli can talk to the mux.

| Script | What it tests | Knobs |
|---|---|---|
| `bench-ux.sh` | 5 UX scenarios: `keypress`, `scroll`, `bufswitch`, `extmarks`, `longsession`, plus `all` | full env-var matrix — see [`bench-ux.md`](./bench-ux.md) |
| `bench-git-wezterm.sh` | TextChanged → first sign-namespace extmark write for `beast.libs.git` vs `gitsigns.nvim` | `BENCH_DEBOUNCE`, `ITERS`, `BACKEND` (positional) — see [`bench-ux.md`](./bench-ux.md#bench-git-wezterm) |
| `bench-ux/diag-bufswitch-wezterm.sh` | _Diagnostic._ Cycles buffers and dumps histograms of which autocmd groups, events, and extmark namespaces grew — finds leaks | `N`, `LANG_KIND`, `USE_GIT` — see [`bench-ux.md`](./bench-ux.md#diagnostic-whos-leaking) |

### Fixture helpers (no benching of their own)

| Script | Builds |
|---|---|
| `make-git-test-repo.sh` | repo with every porcelain v2 status combination (M./. M/A./D./MM/AM/AD/MD/RM/??/!) — for explorer/gitsigns testing |
| `make-git-hunks-fixture.sh` | single file exercising every hunk type (add/change/delete/topdelete/changedelete) — for statuscolumn |

---

## Workflow recipes

### Before merging a lib change

```sh
nvim --clean --headless -l scripts/bench-<lib>.lua
```

If it FAILs, the threshold tripped. Either the change really is slower (read the surrounding research doc) or the threshold needs bumping (only if hardware genuinely changed — note the reason in your commit).

### After touching anything that runs on `BufEnter` / `CursorMoved`

```sh
LOAD_USER_CONFIG=1 FIXTURE_LANG=lua FIXTURE_GIT=1 \
  ./scripts/bench-ux.sh bufswitch
N=20 LANG_KIND=lua USE_GIT=1 \
  ./scripts/bench-ux/diag-bufswitch-wezterm.sh
```

The diag's `by_group` histogram tells you immediately if your new code registered per-buffer handlers.

### After touching extmark code (signs / virt_text / decorations)

```sh
EXTMARKS_N=50000 EXTMARK_VIRT=1 LOAD_USER_CONFIG=1 \
  ./scripts/bench-ux.sh extmarks
```

Plus the diag, and watch the `by_namespace` line for your namespace.

### Hunting a slow-burn leak

```sh
LOAD_USER_CONFIG=1 LONG_MINUTES=30 FIXTURE_GIT=1 \
  ./scripts/bench-ux.sh longsession
```

CSV stream (`# longsession scenario: tag,t,uptime_s,...`) plots latency, RSS, extmark count, Lua refcount per snapshot. Anything growing linearly with `uptime_s` is a leak.

### Startup regressed

```sh
./scripts/bench-startup.sh 20 warm
```

Output highlights the slowest sourcing event with file and ms — use this for **per-file diagnosis**. The wall-clock truth ("how long does the user actually wait?") is in the appended hyperfine row at the bottom; the `--startuptime`-based "Quality" rating in the middle excludes dyld/exec cost, so don't trust it as the headline metric. Track regressions by diffing `~/.cache/beast-bench/startup-*.json` between runs. Compare against `docs/KPI/health-*.md` for the last recorded baseline. The methodology / awk magic is documented at the top of `docs/tec-config/health-config.md`.

If the regression is in *what loads* (rather than *how much each thing costs*), see [`lazy-loading.md`](./lazy-loading.md) — most startup regressions come from accidentally eager `require()`s or wrong `defer` choices.

---

## What's a realistic startup floor for BeastVim?

On Apple Silicon (M1+), wall-clock `nvim --headless +qa` warm:

| Config | Mean |
|---|---|
| `nvim --clean` (no config at all) | ~30 ms |
| LazyVim (default distro) | ~38 ms |
| BeastVim (this repo) | **~75-80 ms** |

The 35-40 ms gap between BeastVim and LazyVim is **structural, not a bug**. LazyVim's user `init.lua` is 4 lines (`vim.g.lazyvim_picker = "telescope"; require("config.lazy")`), and lazy.nvim defers every plugin to events that don't fire under `+qa`. BeastVim's `require("beast").setup()` does meaningful infrastructure work upfront — global modules, highlights, key system, notify/toast/confirm, statusline, starter, packer with 12+ `packer.lazy()` calls, explorer, git, finder, indent, etc.

A/B test (run 2026-06-05, 30 hyperfine runs each):

| Disabled libs | Mean |
|---|---|
| Baseline | 84.7 ms |
| −statusline | 77.7 ms |
| −starter | 78.3 ms |
| −notify+toast | 78.7 ms |
| −all four | 74.8 ms |

Savings don't stack linearly — these libs share infrastructure (`beast.libs.view`, key registration, highlight loads), so removing one doesn't fully eliminate that cost. Realistic gain from fully lazy-loading them: **~10 ms**, putting BeastVim at ~65 ms.

**Treat <100 ms warm as the goal**, not parity with LazyVim. The current ~75 ms is excellent (~50% under the 150 ms warning threshold, and matches what an experienced user perceives as "instant"). Closing the last 35 ms would require gutting the eager infrastructure — not worth the architectural cost.
