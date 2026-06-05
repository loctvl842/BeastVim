# Glossary

- **key-to-paint** — time from `vim.on_key` firing to the next decoration provider `on_end` callback. The user-perceived latency metric.
- **growth indicator** — autocmd count, extmark count per namespace, Lua refcount, RSS. Static during steady state; rising means a leak.
- **decoration provider on_end** — the last callback called per redraw cycle (`src/nvim/decoration_provider.c`). Used as our paint-complete signal.
- **marktree** — Neovim's B-tree of extmarks. O(log n) per op, but `clear_namespace` is O(n) (`src/nvim/extmark.c:198-253`).
- **bench contract** — the `BENCH name=… p50=… status=…` line + 0/1/2 exit code that every bench in `scripts/` produces. See [`benchmarking.md`](./benchmarking.md).
- **defer** — wrapping a lib's load in `vim.schedule()` so the autocmd handler returns before the lib's `setup()` runs. Only meaningful for `event` triggers. See [`lazy-loading.md`](./lazy-loading.md).
- **nvim-internal time** — what `--startuptime` measures: events between `NVIM STARTING` and `NVIM STARTED`. Excludes dyld/exec and `VimEnter` drain. On macOS cold start, this undercounts wall-clock by 300–400 ms.
- **wall-clock startup** — full process time from `exec()` to exit, measured by hyperfine. The number the user actually waits for.
