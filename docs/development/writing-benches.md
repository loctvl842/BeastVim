# Writing a new bench

> See also: [`benchmarking.md`](./benchmarking.md) for the bench contract every new bench must satisfy.

## If it's a component (single lib, isolated)

1. Copy `scripts/bench-statuscolumn.lua` as a template. It's the cleanest example.
2. Stub the BeastVim globals the lib needs (`_G.Theme`, `_G.Util`, etc.) so the test runs under `--clean`.
3. Define `FAIL_THRESHOLD_*` and `WARN_THRESHOLD_*` near the top.
4. Use `vim.uv.hrtime()` for timing; never `os.clock()` or `os.time()`.
5. Run RUNS=3 inner loops × ITERS_PER_RUN renders; report median of medians (resistant to outliers).
6. End with one stdout line matching the bench contract:

   ```
   BENCH name=<id> p50=<X>ms p99=<Y>ms threshold=<N>ms status=PASS
   ```

7. `os.exit(status == "PASS" and 0 or 1)` — never let an uncaught error exit `0`.

## If it's UX-level (real user workflow)

1. Decide if it fits an existing scenario in `bench-ux.sh`. If yes, add it as a subcommand alongside `run_keypress` etc. Reuse `spawn_pane`, `quit_pane`, `send_text`, `send_ctl`, `send_cmd`.
2. If not, write a new top-level shell script following the `bench-git-wezterm.sh` pattern: per-iteration spawn → key feed → probe-log → python summarise.
3. Always source `scripts/bench-ux/probe.lua` so you get key-to-paint measurement and growth snapshots for free.
4. Propagate `NVIM_APPNAME` through the `wezterm cli spawn -- env …` block (don't rely on mux inheritance — see existing helpers).

## Stubbing checklist (headless benches)

The `nvim --clean` env has no plugins, no colors, no palette. If your lib touches any of these, stub them:

```lua
_G.Theme = { get = function() return setmetatable({}, {
  __index = function() return "#ffffff" end
}) end }
_G.Util = { colors = { set_hl = function() end, blend = function(c) return c end } }
```

If you need plugins (rare), prepend `runtimepath` and `package.path`:

```lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
```
