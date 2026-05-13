# Daily Health Report — 2026-05-11 (evening, no vim.pack.add)

## Summary

🟡 — Startup excellent at 34.11 ms with `vim.pack.add` commented out (all plugins assumed installed). −11.8 % vs morning run. All perf thresholds green. stylua drift persists. luacheck still not installed.

> **Context**: This run assumes all plugins are already installed and `vim.pack.add` is skipped. Purpose: measure the potential gain from deferring `pack_add` to a background job.

## 🟢 Startup Performance

- Startup mean: **34.11 ms** (std 2.24, 10 runs)
- vs morning run (with `vim.pack.add`): **−11.8 %** (improved from 38.67 ms)
- vs last daily report (2026-05-10): **−27.1 %** (improved from 46.77 ms)
- Slowest single sourcing event: `sourcing init.lua` — 19.35 ms ✅ (under 30 ms warn)
- No cold-cache outlier this run — all 10 values tightly clustered
- Raw values (ms): 35.62, 35.30, 33.56, 35.10, 31.32, 36.49, 34.59, 29.98, 37.22, 31.92

## 🟢 Per-Lib Profile

- Top offender by SELF_MS (require): `beast.libs.explorer.highlights` — 0.64 ms (5 calls)
- Top offender by SELF_MS (function): `beast.libs.packer.state.load` — 2.90 ms (2 calls)
- `beast.libs.packer.setup` — 0.65 ms self (1 call)
- `beast.libs.buf.new` — 1.74 ms (1 call)
- Functions over their threshold: none (all requires < 3 ms warn; all setup functions < 10 ms warn)
- Duplicated `setup` calls: none (all setup functions called exactly once)

## 🟢 Run-time Benches

| Bench | Result | Summary |
|---|---|---|
| explorer | PASS | `BENCH name=explorer full_render=475.20us nodes=195 scenario=mixed threshold=2000us` |
| statusline | PASS | `BENCH name=statusline beast=8.37us lualine=87.92us ratio=10.5x threshold=1000us` |

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

1. [investigate] `vim.pack.add` skip saves ~4.56 ms (38.67 → 34.11). Explore deferring `pack_add` to a background job when all plugins are already installed.
2. [warn] Run `stylua lua/` to fix formatting drift, then commit.
3. [info] Install `luacheck` (`luarocks install luacheck`) so lint drift can be detected.

## Trend

| Date | Run | Startup mean | Std | Notes |
|---|---|---|---|---|
| 2026-05-09 | daily | 37.54 ms | 4.72 | — |
| 2026-05-10 | daily | 46.77 ms | 32.94 | outlier run 1 (138 ms) |
| 2026-05-11 | morning | 38.67 ms | 14.07 | with `vim.pack.add` |
| 2026-05-11 | evening | 34.11 ms | 2.24 | **without `vim.pack.add`** — ~4.56 ms saved |
