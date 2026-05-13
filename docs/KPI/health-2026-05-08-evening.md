# Daily Health Report — 2026-05-08 (evening)

## Summary

🟡 — Startup slightly elevated vs earlier today (45.92 ms vs 39.85 ms), driven by a cold-cache first-run outlier (71.78 ms). Excluding it, mean is 43.04 ms (+8.0 %). Slowest sourcing event at 52.42 ms crosses the 30 ms warn threshold. All other signals green.

## 🟡 Startup Performance

- Startup mean: **45.92 ms** (std 10.81, 10 runs)
- vs last report (2026-05-08, 39.85 ms): **+15.2 %** ⚠️ (borderline action threshold)
- Excluding first-run outlier (71.78 ms): mean **43.04 ms** (std 6.88) → **+8.0 %**
- Slowest single sourcing event: `init.lua` — 52.42 ms ⚠️ (warn: > 30 ms)

Individual runs (ms): 71.78, 36.82, 44.83, 31.76, 34.84, 51.34, 43.15, 46.57, 44.77, 53.31

**Analysis:**
- The first run (71.78 ms) is a cold-cache outlier pulling the mean up
- Runs 2–10 are consistent with the earlier report (31–53 ms range)
- Slowest sourcing event (init.lua 52.42 ms) also from the first run
- No real regression when accounting for the outlier

## 🟢 Per-Lib Profile

- Top offender by SELF_MS (require): `beast.libs.key.highlights` — 0.61 ms
- Top offender by SELF_MS (function): `beast.libs.packer.state.load` — 9.90 ms (2 calls)
- Functions over their threshold: none
- Duplicated `setup` calls: none

All module require self times well under 3 ms warn threshold. All `*.setup` function self times under 10 ms warn threshold (`packer.setup` = 2.31 ms self).

## 🟢 Run-time Benches

| Bench | Result | Summary |
|---|---|---|
| explorer | PASS | `BENCH name=explorer full_render=483.09us nodes=195 scenario=mixed threshold=2000us` |
| statusline | PASS | `BENCH name=statusline beast=15.20us lualine=91.94us ratio=6.0x threshold=1000us` |

## 🟡 Lint & Format

- luacheck: skipped (not installed)
- stylua: skipped (not installed)

## 🟢 Codemap & Dev-Spec Freshness

- Codemaps generated: 2026-05-06 (2 days ago) ✅
- Stale dev specs: none (all within 14 days or uncommitted/new)

## ⚠️ Process Gaps

- `tests/` directory is empty — no test coverage
- `luacheck` and `stylua` not installed — lint checks cannot run

## Action Items

1. [warn] First-run cold-cache outlier (71.78 ms) inflates the mean. If this persists across reports, investigate shada/cache warm-up cost.
2. [warn] Slowest sourcing event (`init.lua` 52.42 ms) above 30 ms warn threshold — seen only on cold first run, but worth monitoring.
3. [info] Standing gap: no tests in `tests/` directory.
4. [info] Install `luacheck` and `stylua` to enable lint/format checks.

## Trend

| Date | Run | Startup mean | Std | Notes |
|---|---|---|---|---|
| 2026-05-07 | — | 48.84 ms | 8.86 | Baseline (old monokai-pro) |
| 2026-05-08 | morning | 39.85 ms | 2.96 | Updated monokai-pro, best run |
| 2026-05-08 | evening | **45.92 ms** | **10.81** | Cold-cache outlier in run 1; excl. outlier: 43.04 ms (std 6.88) |
