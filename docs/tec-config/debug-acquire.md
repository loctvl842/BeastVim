# Debug Data Acquisition — BeastVim

This is a personal Neovim configuration repo. There is no CI, no pipeline-
alert email, no remote log aggregator. "Failures" here are local, and the
single most common failure mode is a **performance regression in a lib**
(statusline, key, explorer, packer, etc.). This file describes how to get
the data needed to diagnose them.

The skill (`tec-debug`) reads this file and follows it. The user typically
asks one of:

- "debug performance of `<lib>`" — go to **§ Performance Regression** below.
- "debug startup-time spike" — go to **§ Startup-time Spike**.
- "debug `<paste error>`" — go to **§ Runtime Error**.
- bare "`/tec-debug`" — ask the user which of the three above applies. Do
  NOT guess; the acquisition tools differ for each.

---

## Step 1: Identify the failure type

Ask the user **once** if the path isn't already obvious from their prompt:

> Which kind of failure are we debugging?
> 1. **Performance regression** in a specific lib (slow function, slow render)
> 2. **Startup-time spike** (overall `nvim` launch is slow)
> 3. **Runtime error** (Lua stack trace, `:checkhealth` failure, plugin error)

The branches below are largely independent — pick the one that matches.
Skip the others.

---

## § Performance Regression — primary use case

### Step 2a: Capture a fresh profile

Run the in-tree profiler with the same `timer_start(0, qa!)` pattern used
by health-config so the recording covers the full startup:

```bash
out="$HOME/.cache/BeastVim/beast-profile.txt"
rm -f "$out"
BEAST_PROFILE=1 BEAST_PROFILE_OUT="$out" \
  NVIM_APPNAME=BeastVim nvim --headless \
  -c 'autocmd VimEnter * call timer_start(0, {-> execute("qa!")})'
```

The dump at `$out` has two fixed-width sections — `Module require times`
and `Function call times` — both with `CALLS / TOTAL_MS / SELF_MS /
MEAN_US / MAX_US` columns. See `health-config.md` § *Per-Lib Performance
Breakdown* for the format spec.

### Step 2b: Filter to the lib under suspicion

```bash
# Everything attributed to the lib (require + every public fn)
grep -E "^beast\.libs\.<lib>(\.|\s)" "$out"

# Just the offending lib's setup line — usually the headline number
grep -E "^beast\.libs\.<lib>\.setup\s" "$out"
```

Rank by **SELF_MS**, not TOTAL_MS — TOTAL includes children that are
already attributed elsewhere.

### Step 2c: Compare against baseline

Find the most recent KPI report and diff:

```bash
ls -1t docs/KPI/health-*.md | head -3
```

The latest report's "Per-Lib Profile" section has the previous self-time
for each function. A regression worth investigating is **either**:

- self time crossed an Alert Threshold from `health-config.md`
  (`>5 ms` for require, `>20 ms` for `setup`), **or**
- self time grew **>15 %** vs the last report even if still under threshold.

### Step 2d: Cross-check with `--startuptime` (optional)

If the profile shows the cost concentrated in `setup` but you suspect a
specific Vimscript autocmd or `runtime` call inside it, also capture
`--startuptime` and find the same lib's sourcing event:

```bash
tmp=$(mktemp); : > "$tmp"
NVIM_APPNAME=BeastVim nvim --startuptime "$tmp" -c 'call timer_start(0, {-> execute("qa!")})' >/dev/null
grep -E "beast/libs/<lib>" "$tmp"
rm -f "$tmp"
```

The 3-column lines give `clock`, `self+sourced`, `self` for each `:source`
event — useful for catching a transitively-loaded plugin that
`beast.profile` cannot see (Lua-only).

### Step 2e: If the lib has a runtime bench, run it

`scripts/bench-<lib>.lua` measures the steady-state hot path (e.g.
statusline render). Load-time and run-time regressions are different;
make sure both are captured if the lib has a bench:

```bash
nvim --clean --headless -l scripts/bench-<lib>.lua
```

A non-zero exit means a runtime threshold was crossed — diagnose
separately from the load-time profile.

### Step 2f: Localize via git

Once a single function is identified as the regressor, look for a recent
change:

```bash
git log --oneline -20 -- lua/beast/libs/<lib>/
git log --oneline -20 -- lua/beast/libs/<lib>.lua
```

If the regression appeared between two health reports, narrow the window
with the commit dates of `docs/KPI/health-*.md` files at the boundary.

---

## § Startup-time Spike

### Step 2a: Confirm the spike

Run the same 10-try block from `health-config.md` § *Data Freshness*:

```bash
tmp=$(mktemp); : > "$tmp"
for i in $(seq 1 10); do
  NVIM_APPNAME=BeastVim nvim --startuptime "$tmp" -c 'call timer_start(0, {-> execute("qa!")})' >/dev/null
done
awk '
  /--- N?VIM STARTING ---/ { last=""; session++ }
  /^[0-9]/                 { last=$1 }
  /--- N?VIM STARTED ---/  { if (session % 2 == 0) print last }
' "$tmp"
```

Compare mean and std against the latest KPI report. If today's mean is
within `2 × std` of the last report, this is not a real regression — stop
and tell the user. Otherwise continue.

### Step 2b: Find the slowest sourcing event

```bash
awk '/^[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+:/ {
       printf "%s %s\n", $2, substr($0, index($0,": ")+2)
     }' "$tmp" | sort -nr | head -20
rm -f "$tmp"
```

Top of the list is the headline. If it's a `beast/libs/<lib>` path, jump
into **§ Performance Regression** with that lib name. If it's a
plugin-manager-loaded plugin, the next step is `git log -- lua/beast/plugins/`
to find what wired it in.

### Step 2c: Cross-check with `beast.profile`

Same as **§ Performance Regression Step 2a**. The profiler attributes by
Lua module; `--startuptime` attributes by `:source`d file. They disagree
sometimes, and the disagreement is itself a clue (Vimscript-only cost
appears in `--startuptime` but not the profile).

---

## § Runtime Error

### Step 2a: If the user pasted an error/stack trace

Use it directly. Skip Step 2b–2c.

### Step 2b: Capture `:messages` and `:checkhealth`

```bash
nvim --headless \
  -c 'redir > /tmp/beast-messages.txt | silent messages | redir END' \
  -c 'qa!' && cat /tmp/beast-messages.txt && rm -f /tmp/beast-messages.txt
```

For `:checkhealth`:

```bash
nvim --headless \
  -c 'checkhealth' \
  -c 'redir > /tmp/beast-health.txt | silent %print | redir END' \
  -c 'qa!' && cat /tmp/beast-health.txt && rm -f /tmp/beast-health.txt
```

### Step 2c: Lazy.nvim error log (if the failure is at plugin load)

If `lazy.nvim` is the loader, plugin load errors land in its log:

```bash
nvim --headless -c 'Lazy log' -c 'qa!' 2>&1 | tee /tmp/lazy-log.txt
# or check the on-disk log if Lazy writes one
ls -lt ~/.local/state/BeastVim/lazy/ 2>/dev/null
```

### Step 2d: Locate the failing module

A Lua stack trace's top frame names the file. From there:

```bash
git log --oneline -10 -- <path-from-trace>
git blame <path-from-trace> | sed -n '<lineno-from-trace>p'
```

---

## Pipelines

| Pipeline Name | Stage | Owner |
|---|---|---|
| _none_ | _no CI configured_ | — |

If GitHub Actions is added later (e.g. `luacheck.yml`, `stylua.yml`), add
rows here and update Step 1 to mention "pipeline failure" as a fourth
failure type. Until then, every failure is local.

---

## Known Error Patterns

| Pattern | Category | Quick Fix |
|---|---|---|
| `attempt to index a nil value (field 'X')` | Lua / module load | Module is required before its dependency is loaded. Check the require order in `lua/beast/libs/<lib>/init.lua`. |
| `module 'beast.X' not found` | Loader / runtimepath | The lib's path doesn't match its require name. Confirm `lua/beast/X.lua` or `lua/beast/X/init.lua` exists. |
| `package.loaded[X]` set to a table on first require but `nil` later | ColorScheme reload | Intentional — `*.highlights` modules are cleared and re-required on `ColorScheme`. Confirm by grepping for `package.loaded["beast.libs.<lib>.highlights"] = nil`. |
| `setup` function `CALLS` > 1 in `beast.profile` | Duplicated wiring | Two require sites are calling `setup`. Grep `lua/beast/init.lua` and `lua/beast/libs/<lib>/init.lua` for double-call. |
| Self time **negative** in `beast.profile` | Frame-stack corruption (profiler bug) | An error inside an instrumented fn leaked a frame. Re-run; if it persists, it's a profiler bug — file under `lua/beast/profile.lua`. |
| `--startuptime` total stable, but `beast.profile` total grew | Lua-only regression | The cost is in a Lua module not visible to `:source` accounting. Use the profile, not startuptime, to localize. |
| `--startuptime` total grew, but `beast.profile` total stable | Vimscript / autocmd regression | The cost is in a `:source` event or a non-Lua autocmd. Use startuptime's 3-column section to localize. |
| `bench-*.lua` exits 2 | Bench setup error | The bench's environment broke (renamed module, removed file). Fix the bench script before treating as a regression. |
| `bench-*.lua` exits 1 | Runtime threshold exceeded | A run-time hot path regressed. Diff against the last health report's bench results. |
| `E5108: Error executing lua` at startup | Init-time exception | Run `nvim --headless -c 'qa!' 2>&1` to see the full trace. The first non-pcall'd error wins. |
| `vim.pack.get()` called synchronously in `setup` → SELF_MS spike on the lib's `setup` | Startup hot-path / Neovim API | `vim.pack.get()` walks each plugin's git metadata (~30–60 ms even for a handful of plugins) and does **not** cache. Defer it to `vim.schedule` if the result only feeds UI state. |

---

## Post-Debug Triage (optional)

After diagnosis:

- If the root cause is a regression that crossed a threshold, append a
  **one-line entry** to today's `docs/KPI/health-YYYY-MM-DD.md` under a
  `### Debug Notes` section so the next health check sees the resolution.
- If a new error pattern was learned, add a row to **§ Known Error
  Patterns** above so the next debug run hits it directly.
- If the failure is a runtime hot-path regression and the lib has no
  `scripts/bench-<lib>.lua`, that's a process gap — flag it for follow-up
  with `/tec-dev-spec`.

No bug tracker, no work-item system — that's the whole triage.
