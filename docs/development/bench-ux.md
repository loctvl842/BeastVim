# bench-ux harness — UX latency, leak hunting, and backend A/B

> See also: [`benchmarking.md`](./benchmarking.md) for the bench contract and inventory, [`glossary.md`](./glossary.md) for terms like *key-to-paint* and *decoration provider on_end*.

The most general benches in BeastVim measure **key-to-paint latency** in a real wezterm pane, scoped to specific user workloads. This document covers `bench-ux.sh`, the leak-hunting diagnostic, and the git backend A/B harness.

---

## bench-ux.sh — the UX harness in depth

`bench-ux.sh` is the most general bench: it measures key-to-paint latency in a real wezterm pane, scoped to specific user workloads.

### How it works

```
            wezterm cli send-text "j"
                       │
                       ▼
           ┌──── nvim (your config) ────┐
           │                             │
           │  vim.on_key  ───┐           │
           │                 ├──► dt = end - start
           │  decoration ────┘           │
           │  provider on_end            │
           │       │                     │
           │       └──► append to log    │
           └─────────────────────────────┘
                       │
                       ▼
            summarise.py → BENCH line
```

The probe (`scripts/bench-ux/probe.lua`) records:

- a timestamp on every key entering Neovim (`vim.on_key`)
- the time the *next redraw cycle* finishes (decoration provider `on_end`, the last callback in the redraw pass — see `docs/neovim/latency-research.md` §3)
- periodic growth snapshots: autocmd count, extmark count per namespace, Lua refcount, RSS, redraw counter

The difference between key-in and redraw-out is the closest proxy for perceived UX latency we can measure inside Neovim without screen-scraping the terminal.

### Scenarios

| Subcommand | Targets bottleneck (see latency-research.md §) |
|---|---|
| `keypress` | baseline floor — sanity check |
| `scroll` | redraw amplification, TS parse per `<C-d>` (§2.1, §2.9) |
| `bufswitch` | `BufEnter`/`WinEnter` autocmd scans, FOR_ALL_BUFFERS (§2.11) |
| `extmarks` | marktree lookup, decoration redraw, inline virt_text (§2.1, §2.15, §4) |
| `longsession` | extmark / autocmd / Lua ref growth over time (§2.6, §2.12) |
| `all` | runs the four short ones (skips longsession) |

### Env knobs (full matrix)

```
ITERS=60               keys to feed per scenario
KEY_DELAY=0.08         seconds between keys (smaller = more pressure)
BUFSWITCH_N=100        buffers to preload for bufswitch
EXTMARKS_N=10000       extmarks to seed for extmarks
EXTMARK_VIRT=0|1       1 = inline virt_text per mark (worst-case redraw)
SCROLL_LINES=100000    lines in the scroll fixture
LONG_MINUTES=5         longsession duration
LONG_INTERVAL=30       longsession snapshot cadence (s)

LOAD_USER_CONFIG=0|1   0 = bare nvim baseline, 1 = full plugin stack
NVIM_APPNAME=BeastVim  which config to load (auto-defaults to BeastVim
                       when LOAD_USER_CONFIG=1 — never silently falls
                       through to ~/.config/nvim)
FIXTURE_LANG=txt|lua|py    txt is cheap; lua/py trigger LSP+TS+ftplugin
FIXTURE_GIT=0|1            1 = init repo with mixed states
                           (modified/staged-with-unstaged/untracked/deleted)
KEEP_LOGS=0|1              1 leaves /tmp/bench-ux.$$ for inspection
```

### Reading the output

```
BENCH name=bufswitch n=71 min=8.76ms p50=16.18ms p90=19.98ms p99=32.50ms \
      max=34.49ms thresh_p50=25ms thresh_p99=120ms status=PASS
GROWTH name=bufswitch d_bufs=2 d_autocmds=591 d_extmarks=2428 \
      d_lua_kb=30251 d_rss_kb=103376 ...
```

| Field | Meaning |
|---|---|
| `n=` | samples captured (one per paint) — fewer than `ITERS` is normal (some keys produce no redraw) |
| `p50/p90/p99/max` | key-to-paint latency percentiles |
| `d_autocmds` | autocmds added during the run — should be **0** in steady state |
| `d_extmarks` | extmarks added during the run — should be **bounded** |
| `d_lua_refcount` | Lua refs added — leaks accumulate here |
| `d_rss_kb` | resident-set growth (best-effort: `/proc/$pid/status` on Linux, `ps -o rss=` on macOS) |

The `BENCH` line decides PASS/FAIL via thresholds. `GROWTH` is for leak hunting — large `d_*` values point at per-buffer leaks (see the diag).

### Default-safe NVIM_APPNAME

When `LOAD_USER_CONFIG=1` and no `NVIM_APPNAME` is set, the script defaults to `BeastVim` and `export`s it before spawning. The first line of every log records `# nvim_appname=… loaded_config=…/init.lua` so results are self-describing. Override with `NVIM_APPNAME=nvim` to bench the default config dir.

---

## Diagnostic: who's leaking?

When `bench-ux.sh bufswitch` shows growing `d_autocmds` or `d_extmarks`, the wezterm-driven diag pinpoints **which plugin** is responsible.

```sh
N=20 LANG_KIND=lua USE_GIT=1 NVIM_APPNAME=BeastVim \
  ./scripts/bench-ux/diag-bufswitch-wezterm.sh
```

It cycles N buffers twice and dumps three histograms at three snapshots (`after_init`, `after_first_buffer`, `after_cycle`):

- **by_event** — which `BufEnter`/`CursorMoved`/... events grew
- **by_group** — which autocmd group grew (e.g. `navic`, `gitsigns`, `treesitter_context_update`)
- **by_namespace** — which extmark namespace grew (e.g. `nvim.lsp.semantic_tokens:1`)

Compare `after_first_buffer` ↔ `after_cycle` to see per-buffer growth. A flat group is well-behaved; one that grows linearly with buffer count is your leak. See `docs/neovim/bottleneck-report.md` for a worked example that found `navic` (+133 autocmds for 40 entries) and `nvim.lsp.semantic_tokens:1` (+3214 extmarks).

---

## bench-git-wezterm

Specialised version of bench-ux that compares **two git-sign backends** on the same 5000-line fixture: `beast.libs.git` and `gitsigns.nvim`.

It measures one specific latency: `TextChanged → first extmark in the unstaged sign namespace`. Bypasses the rest of the redraw pipeline so regressions in either backend show up cleanly.

```sh
./scripts/bench-git-wezterm.sh                  # both backends, default cfg
./scripts/bench-git-wezterm.sh beast            # one backend only
BENCH_DEBOUNCE=1 ./scripts/bench-git-wezterm.sh # bypass debounce (raw work)
ITERS=80 ./scripts/bench-git-wezterm.sh         # more samples
```

Thresholds shift with `BENCH_DEBOUNCE`: at the default 50 ms, latency floor *is* the debounce; at 1 ms, you're measuring pure diff+place work.
