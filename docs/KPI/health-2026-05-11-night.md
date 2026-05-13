# Daily Health Report — 2026-05-11 (night, post plugin cleanup)

## Summary

🟡 — Startup at 35.82 ms after plugin cleanup — 7.4 % faster than morning (38.67 ms) with `vim.pack.add` still active. All perf thresholds green. stylua drift persists. luacheck not installed.

> **Context**: User cleaned unused plugins. This run measures the effect with normal `vim.pack.add` enabled. The improvement (38.67 → 35.82 ms) suggests the cleanup removed ~3 ms of unnecessary plugin loading.

## 🟢 Startup Performance

- Startup mean: **35.82 ms** (std 8.55, 10 runs)
- vs evening run (no `vim.pack.add`): **+5.0 %** (34.11 → 35.82 ms)
- vs morning run (with `vim.pack.add`): **−7.4 %** (improved from 38.67 ms)
- vs last daily report (2026-05-10): **−23.4 %** (improved from 46.77 ms)
- Slowest single sourcing event: `sourcing init.lua` — 26.44 ms ✅ (under 30 ms warn)
- Raw values (ms): 40.37, 29.88, 23.65, 31.84, 29.21, 49.63, 36.62, 46.04, 42.47, 28.46

**Plugin cleanup impact**: Morning had 38.67 ms with `vim.pack.add`; now 35.82 ms with `vim.pack.add` — the ~2.85 ms gap is the cost of the removed plugins. Evening's 34.11 ms (no `pack.add`) is still the floor; the remaining ~1.71 ms is `pack.add` overhead for the kept plugins.

## 🟢 Per-Lib Profile

- Top offender by SELF_MS (require): `beast.libs.explorer.highlights` — 0.72 ms (5 calls)
- Top offender by SELF_MS (function): `beast.libs.packer.state.load` — 2.44 ms (2 calls)
- `beast.libs.packer.setup` — 2.00 ms self (1 call)
- `beast.libs.buf.new` — 1.76 ms (1 call)
- Functions over their threshold: none (all requires < 3 ms warn; all setup functions < 10 ms warn)
- Duplicated `setup` calls: none (all setup functions called exactly once)

## 🟢 Run-time Benches

| Bench | Result | Summary |
|---|---|---|
| explorer | PASS | `BENCH name=explorer full_render=472.47us nodes=195 scenario=mixed threshold=2000us` |
| statusline | PASS | `BENCH name=statusline beast=6.75us lualine=98.60us ratio=14.6x threshold=1000us` |

## 🟡 Lint & Format

- luacheck: **not installed** — cannot verify lint status
- stylua: **FAIL** — formatting drift detected (e.g. `lua/beast/plugins/init.lua`)

## 🟢 Codemap & Dev-Spec Freshness

- Codemaps generated: 2026-05-06 (5 days ago) ✅
- Stale dev specs (> 14 days): none
- Dev specs with no git history: `bench-explorer.md`, `packer-profile-ui.md`, `tabline-library.md`

## ⚠️ Process Gaps

- **luacheck not installed** — install via `luarocks install luacheck` to enable lint checks
- **stylua drift** — run `stylua lua/` to re-format, then commit
- **No `tests/` directory** — standing gap; no test files exist yet

## Action Items

1. [warn] Run `stylua lua/` to fix formatting drift, then commit.
2. [info] Install `luacheck` (`luarocks install luacheck`) so lint drift can be detected.
3. [info] Stale codemap approaching 7-day warn in 2 days — consider running `/tec-update-codemaps` soon.

## Trend

| Date | Run | Startup mean | Std | Notes |
|---|---|---|---|---|
| 2026-05-09 | daily | 37.54 ms | 4.72 | — |
| 2026-05-10 | daily | 46.77 ms | 32.94 | outlier run 1 (138 ms) |
| 2026-05-11 | morning | 38.67 ms | 14.07 | with `vim.pack.add` |
| 2026-05-11 | evening | 34.11 ms | 2.24 | without `vim.pack.add` |
| 2026-05-11 | night | 35.82 ms | 8.55 | **post plugin cleanup** — ~2.85 ms saved vs morning |
