# Daily Health Report — 2026-05-12 (midday)

## Summary

🟡 — Startup improved to 46.57 ms (−27.3 % vs morning). Cold-cache run 1 outlier persists but less severe. `tabline.context` require at 3.54 ms crosses warn threshold. stylua drift persists. Codemaps approaching staleness.

## 🟡 Startup Performance

- Startup mean: **46.57 ms** (std 9.91, 10 runs)
- vs earlier today: **−27.3 %** (improved from 64.05 ms)
- vs 2026-05-11 night baseline: **+30.0 %** (up from 35.82 ms)
- Slowest single sourcing event: `sourcing init.lua` — 43.61 ms ⚠️ (> 30 ms warn, < 60 ms action)
- Raw values (ms): 68.12, 47.34, 55.70, 57.87, 39.50, 39.16, 38.96, 39.13, 39.44, 40.47

**Outlier note**: Run 1 (68.12 ms) is the typical cold-cache first hit. Less severe than earlier today (171.9 ms). Excluding run 1, runs 2–10 mean is **44.18 ms** (std 7.36).

| Threshold | Value | Status |
|---|---|---|
| Mean < 150 ms | 46.57 ms | ✅ |
| Std < 20 ms | 9.91 ms | ✅ |
| Sourcing event < 30 ms | 43.61 ms | 🟡 (> 30 ms warn, < 60 ms action) |
| Regression < 15 % vs 05-11 night | +30.0 % | 🔴 |

## 🟡 Per-Lib Profile

- Recording uptime: 85.93 ms
- Top offender by SELF_MS (require): `beast.libs.tabline.context` — 3.54 ms (1 call) ⚠️ (> 3 ms warn, < 5 ms action)
- Top offender by SELF_MS (function): `beast.libs.packer.state.load` — 7.65 ms (2 calls)
- `beast.libs.packer.setup` — 3.10 ms self (1 call) — under 10 ms warn ✅
- `beast.libs.buf.new` — 2.23 ms self (1 call)
- Functions over their threshold: none (all setup functions < 10 ms warn)
- Duplicated `setup` calls: none (all setup functions called exactly once)

## 🟢 Run-time Benches

| Bench | Result | Summary |
|---|---|---|
| explorer | PASS | `BENCH name=explorer full_render=465.37us nodes=195 scenario=mixed threshold=2000us` |
| statusline | PASS | `BENCH name=statusline beast=5.33us lualine=85.49us ratio=16.0x threshold=1000us` |
| tabline | PASS | `BENCH name=tabline beast=680.42us bufferline=3362.18us ratio=4.9x threshold=1000us` |

> **Note**: tabline cold render at 680.42 µs > 50 µs soft target (bench emitted its own WARN but exited 0). Increased from earlier today (159.87 µs) — worth monitoring.

## 🟡 Lint & Format

- stylua: **FAIL** — formatting drift detected (e.g. `lua/beast/plugins/init.lua`)

## 🟡 Codemap & Dev-Spec Freshness

- Codemaps generated: 2026-05-06 (6 days ago) ⚠️ — will cross 7-day warn threshold tomorrow
- Stale dev specs (> 14 days): none
- Dev specs with no git history: `bench-explorer.md`, `packer-lazy-libs.md`, `packer-profile-ui.md`, `tabline-library.md`

## ⚠️ Process Gaps

- **stylua drift** — run `stylua lua/` to re-format, then commit
- **No `tests/` directory** — standing gap; no test files exist yet

## Action Items

1. [warn] `beast.libs.tabline.context` require self time (3.54 ms) crossed the 3 ms warn threshold. Investigate if it's doing heavy work at load time.
2. [warn] Startup still +30 % vs 2026-05-11 night baseline (35.82 ms). Cold-cache run 1 outlier less severe today. Monitor tomorrow.
3. [warn] Run `stylua lua/` to fix formatting drift, then commit.
4. [info] Codemaps will go stale tomorrow — run `/tec-update-codemaps`.

## Trend

| Date | Run | Startup mean | Std | Notes |
|---|---|---|---|---|
| 2026-05-09 | daily | 37.54 ms | 4.72 | — |
| 2026-05-10 | daily | 46.77 ms | 32.94 | outlier run 1 (138 ms) |
| 2026-05-11 | morning | 38.67 ms | 14.07 | with `vim.pack.add` |
| 2026-05-11 | evening | 34.11 ms | 2.24 | without `vim.pack.add` |
| 2026-05-11 | night | 35.82 ms | 8.55 | post plugin cleanup |
| 2026-05-12 | morning | 64.05 ms | 37.34 | cold-cache outlier (run 1: 171.9 ms) |
| 2026-05-12 | midday | 46.57 ms | 9.91 | −27.3 % vs morning; outlier run 1: 68 ms |
