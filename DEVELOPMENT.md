# BeastVim — Development Guide

A reference for benchmarking, profiling, and validating changes to BeastVim's libs and plugins. Two-tier system: **headless component benches** for unit-level perf, and **wezterm-driven UX benches** for end-to-end input-to-paint latency.

> Everything in this guide is read-only background reading until you change code that touches a benched lib. Then the relevant bench is mandatory.

## Where to read next

| Topic | File |
|---|---|
| Bench contract, what each bench measures, workflow recipes | [`docs/development/benchmarking.md`](docs/development/benchmarking.md) |
| wezterm UX harness deep-dive, leak diagnostic, git backend A/B | [`docs/development/bench-ux.md`](docs/development/bench-ux.md) |
| When (and when not) to use `defer` on event triggers | [`docs/development/lazy-loading.md`](docs/development/lazy-loading.md) |
| How to write a new bench from scratch | [`docs/development/writing-benches.md`](docs/development/writing-benches.md) |
| Term definitions (key-to-paint, growth indicator, marktree, …) | [`docs/development/glossary.md`](docs/development/glossary.md) |

## Prerequisites

| Tool | Purpose | Install | Required? |
|---|---|---|---|
| `nvim` (≥0.11) | Run the editor under test | — | Yes |
| `wezterm` | Drive end-to-end UX benches | `brew install --cask wezterm` | UX benches only |
| `hyperfine` | **Wall-clock startup benchmarking** (trust this over `--startuptime`) | `brew install hyperfine` | `bench-startup.sh` (highly recommended) |
| `sudo` access to `purge` | True cold-cache startup runs on macOS | built-in | `bench-startup.sh cold` only |

`bench-startup.sh` works without `hyperfine` but only reports nvim-internal time (`--startuptime`), which excludes dyld/exec cost and undercounts true cold start by 300–400 ms on macOS. With `hyperfine` installed, the script appends a wall-clock section and exports results as JSON to `~/.cache/beast-bench/startup-<APP>-<MODE>-<TIMESTAMP>.json` for trend tracking. **Treat the hyperfine numbers as authoritative.**

## Quick start

```sh
# 1. Daily-ish: is startup still healthy?
./scripts/bench-startup.sh

# 2. Before merging: do all component benches pass?
for f in scripts/bench-*.lua; do
  nvim --clean --headless -l "$f" || echo "FAIL: $f"
done

# 3. After any plugin / autocmd / extmark change: is UX latency healthy?
LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim FIXTURE_LANG=lua FIXTURE_GIT=1 \
  ./scripts/bench-ux.sh all
```
