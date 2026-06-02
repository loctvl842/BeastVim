#!/usr/bin/env bash
# scripts/bench-git-wezterm.sh — end-to-end latency benchmark in a real wezterm pane.
#
# Compares `beast.libs.git` against `gitsigns.nvim` on the same fixture by
# spawning each in a fresh wezterm pane, driving real key input via
# `wezterm cli send-text` (real cursor moves + insertions), and timing
# TextChanged → first sign-namespace extmark write end-to-end.
#
# Why this exists
# ---------------
#   scripts/bench-git.lua measures pure `compute_hunks` cost in --headless.
#   That misses event wiring, debounce, redraw competition, and any future
#   regression in the attach/diff/place pipeline. This script catches those.
#
# Usage
# -----
#   ./scripts/bench-git-wezterm.sh                    # both backends, default cfg
#   ./scripts/bench-git-wezterm.sh beast              # one backend only
#   BENCH_DEBOUNCE=1 ./scripts/bench-git-wezterm.sh   # bypass debounce (raw work)
#   ITERS=80 ./scripts/bench-git-wezterm.sh           # more samples per run
#   GITSIGNS_PATH=/path/to/gitsigns.nvim ./scripts/bench-git-wezterm.sh
#
# Exit codes
# ----------
#   0 PASS (under all thresholds)
#   1 FAIL (a threshold tripped)
#   2 setup error (missing tools, fixture/probe failed)
#
# Requirements: wezterm, git, python3, nvim ≥ 0.10. Must run from a host
# already inside wezterm (so `wezterm cli spawn` can attach to the mux).

set -eu

BACKENDS="${1:-beast gitsigns}"
ITERS="${ITERS:-40}"
DEBOUNCE="${BENCH_DEBOUNCE:-50}"
GITSIGNS_PATH="${GITSIGNS_PATH:-$HOME/.local/share/nvim/lazy/gitsigns.nvim}"
BEAST_PATH="${BEAST_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

WORK="${TMPDIR:-/tmp}/bench-git-wezterm.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# ── Regression thresholds (median / p99 in ms) ────────────────────────────
#   Tuned on Apple Silicon. Bump if hardware genuinely changed.
#   At default 50 ms debounce, latency floor IS the debounce — allow +40 ms
#   to absorb the dual-diff cost (HEAD-vs-index + index-vs-buffer).
#   At 1 ms debounce, we measure pure work — tight bounds, also bumped for dual diff.
if [ "$DEBOUNCE" -ge 20 ]; then
  THRESH_MEDIAN=80    # debounce + dual diff + slack
  THRESH_P99=100
else
  THRESH_MEDIAN=8     # dual diff + place on 5k-line file
  THRESH_P99=15
fi

# ── Prereq checks ─────────────────────────────────────────────────────────
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'" >&2; exit 2; }
}
need wezterm
need git
need python3
need nvim
wezterm cli list >/dev/null 2>&1 || {
  echo "ERROR: 'wezterm cli list' failed — must run from inside wezterm" >&2
  exit 2
}
[ -d "$BEAST_PATH/lua/beast/libs/git" ] || {
  echo "ERROR: beast.libs.git not found at $BEAST_PATH" >&2; exit 2
}
[ -d "$GITSIGNS_PATH/lua/gitsigns" ] || {
  echo "ERROR: gitsigns.nvim not found at $GITSIGNS_PATH (set GITSIGNS_PATH=…)" >&2
  exit 2
}

# ── Build fixture: 5000-line file committed to a synthetic repo ───────────
FIXTURE="$WORK/repo"
mkdir -p "$FIXTURE"
(
  cd "$FIXTURE"
  git init -q -b main
  git config user.email bench@local
  git config user.name bench
  python3 - <<'PY'
with open("big.txt", "w") as f:
    for i in range(1, 5001):
        f.write(f"line {i:06d}  alpha bravo charlie delta echo foxtrot golf hotel\n")
PY
  git add big.txt
  git commit -q -m init
) || { echo "ERROR: fixture build failed" >&2; exit 2; }

# ── Shared probe: hooks nvim_buf_set_extmark per sign namespace ───────────
cat > "$WORK/probe.lua" <<'LUA'
local backend = os.getenv("BENCH_BACKEND") or "unknown"
local logpath = os.getenv("BENCH_LOG") or ("/tmp/perf-" .. backend .. ".log")
local log = assert(io.open(logpath, "w"))
log:write(string.format("# backend=%s pid=%d\n", backend, vim.fn.getpid())); log:flush()

local target_ns, pending_t0, last_logged_at = nil, nil, 0

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  callback = function() pending_t0 = vim.uv.hrtime() end,
})

local orig = vim.api.nvim_buf_set_extmark
vim.api.nvim_buf_set_extmark = function(buf, ns, row, col, opts)
  local r = orig(buf, ns, row, col, opts)
  if target_ns and ns == target_ns and pending_t0 then
    local now = vim.uv.hrtime()
    if now - last_logged_at > 1e6 then  -- 1ms coalesce window
      log:write(string.format("%.3f\n", (now - pending_t0) / 1e6)); log:flush()
      last_logged_at = now
      pending_t0 = nil
    end
  end
  return r
end

function _G.bench_set_ns(pattern)
  vim.defer_fn(function()
    for name, id in pairs(vim.api.nvim_get_namespaces()) do
      if name:match(pattern) then
        target_ns = id
        log:write(string.format("# ns=%s id=%d\n", name, id)); log:flush()
        return
      end
    end
    log:write("# WARN: ns not found for pattern " .. pattern .. "\n"); log:flush()
  end, 200)
end

vim.api.nvim_create_user_command("BenchQuit", function()
  log:close(); vim.cmd("qa!")
end, {})
LUA

# ── Per-backend minimal init ──────────────────────────────────────────────
cat > "$WORK/init-beast.lua" <<LUA
vim.opt.rtp:prepend("$BEAST_PATH")
package.path = "$BEAST_PATH/lua/?.lua;$BEAST_PATH/lua/?/init.lua;" .. package.path
vim.o.termguicolors = true; vim.o.swapfile = false; vim.o.signcolumn = "yes"
dofile("$WORK/probe.lua")
-- Stub globals beast.libs.git.highlights references (colours irrelevant here).
_G.Palette = { get = function() return setmetatable({}, { __index = function() return "#808080" end }) end }
_G.Util = { colors = { set_hl = function() end, blend = function(c) return c end } }
require("beast.libs.git").setup({ debounce_ms = tonumber(os.getenv("BENCH_DEBOUNCE") or "50") })
_G.bench_set_ns("^beast_git_signs\$")
LUA

cat > "$WORK/init-gitsigns.lua" <<LUA
vim.opt.rtp:prepend("$GITSIGNS_PATH")
vim.o.termguicolors = true; vim.o.swapfile = false; vim.o.signcolumn = "yes"
dofile("$WORK/probe.lua")
require("gitsigns").setup({
  signcolumn = true,
  update_debounce = tonumber(os.getenv("BENCH_DEBOUNCE") or "50"),
})
_G.bench_set_ns("^gitsigns_signs_\$")
LUA

# ── Driver: spawn pane, send keys, summarise log ──────────────────────────
run_one() {
  backend=$1
  init="$WORK/init-${backend}.lua"
  log="$WORK/perf-${backend}.log"
  [ -f "$init" ] || { echo "ERROR: no init for backend=$backend" >&2; return 2; }
  rm -f "$log"

  pane=$(wezterm cli spawn --cwd "$FIXTURE" -- \
    env BENCH_BACKEND="$backend" BENCH_DEBOUNCE="$DEBOUNCE" BENCH_LOG="$log" \
    nvim -u "$init" big.txt)
  printf "  spawned wezterm pane %s for %s (debounce=%sms, iters=%s)\n" \
    "$pane" "$backend" "$DEBOUNCE" "$ITERS"

  sleep 2.5  # let nvim start, attach, fetch base, do initial diff

  i=1; while [ "$i" -le "$ITERS" ]; do
    line=$(( (i * 113) % 4900 + 50 ))
    wezterm cli send-text --no-paste --pane-id "$pane" "${line}G"
    sleep 0.04
    wezterm cli send-text --no-paste --pane-id "$pane" "o"
    wezterm cli send-text --no-paste --pane-id "$pane" "edit_${i}"
    printf '\x1b' | wezterm cli send-text --no-paste --pane-id "$pane"
    sleep 0.12
    i=$((i + 1))
  done

  sleep 0.5
  wezterm cli send-text --no-paste --pane-id "$pane" ":BenchQuit"
  printf '\r' | wezterm cli send-text --no-paste --pane-id "$pane"
  sleep 1.0
}

summarise() {
  backend=$1; log="$WORK/perf-${backend}.log"; thresh_med=$2; thresh_p99=$3
  python3 - "$log" "$backend" "$thresh_med" "$thresh_p99" <<'PY'
import sys, statistics
path, backend, tm, tp = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
try:
    samples = [float(l) for l in open(path) if l.strip() and not l.startswith("#")]
except FileNotFoundError:
    print(f"ERROR {backend}: log missing"); sys.exit(2)
if not samples:
    print(f"ERROR {backend}: 0 samples — check {path}"); sys.exit(2)
samples.sort()
def pct(p):
    k = max(0, min(len(samples)-1, int(round(p/100*(len(samples)-1)))))
    return samples[k]
med, p90, p99 = statistics.median(samples), pct(90), pct(99)
status = "PASS" if (med <= tm and p99 <= tp) else "FAIL"
print(f"BENCH name=git-wezterm backend={backend} n={len(samples)} "
      f"min={samples[0]:.2f}ms median={med:.2f}ms p90={p90:.2f}ms "
      f"p99={p99:.2f}ms max={samples[-1]:.2f}ms "
      f"threshold_median={tm:g}ms threshold_p99={tp:g}ms status={status}")
sys.exit(0 if status == "PASS" else 1)
PY
}

# ── Main ──────────────────────────────────────────────────────────────────
printf "\n  \033[1mGit signs end-to-end latency (real wezterm pane)\033[0m\n"
printf "  ─────────────────────────────────────────────────────\n"
printf "  fixture:        %s (5000 lines, 1 commit)\n" "$FIXTURE/big.txt"
printf "  debounce:       %s ms\n" "$DEBOUNCE"
printf "  iterations:     %s edits per backend\n" "$ITERS"
printf "  thresholds:     median ≤ %s ms, p99 ≤ %s ms\n\n" "$THRESH_MEDIAN" "$THRESH_P99"

exit_code=0
for backend in $BACKENDS; do
  case "$backend" in
    beast|gitsigns) ;;
    *) echo "ERROR: unknown backend '$backend' (use: beast, gitsigns)" >&2; exit 2 ;;
  esac
  run_one "$backend" || { echo "FAIL: $backend run aborted" >&2; exit_code=1; continue; }
  summarise "$backend" "$THRESH_MEDIAN" "$THRESH_P99" || exit_code=1
done

printf "\n"
exit "$exit_code"
