#!/bin/sh
# scripts/bench-startup.sh — Startup time benchmark for Neovim configs
# Usage: ./scripts/bench-startup.sh [RUNS] [MODE] [APPNAME]
#   RUNS     — number of measurements (default: 10)
#   MODE     — warm | cold | mixed (default: mixed)
#     warm   — primes OS cache first, then measures (steady-state)
#     cold   — runs `sudo purge` before each run (true cold start)
#     mixed  — no cache control, first run may be cold (default)
#   APPNAME  — NVIM_APPNAME to benchmark (default: BeastVim)
#
# What this measures (and what it does NOT):
#   The headline numbers in this script come from Neovim's `--startuptime`,
#   which only timestamps events AFTER the nvim binary + libluajit are loaded.
#   That means dyld/exec, shared-library cold reads, and process teardown are
#   INVISIBLE to it — on a true cold start, these can be 300–400 ms on macOS
#   that this script will not show. Use this for per-file diagnosis.
#
#   For wall-clock truth ("how long does the user wait?"), prefer hyperfine.
#   If installed, a hyperfine section is appended at the end and results are
#   exported as JSON for tracking over time.

set -eu

RUNS="${1:-10}"
MODE="${2:-mixed}"
APP="${3:-BeastVim}"
TMP=$(mktemp)
: > "$TMP"
trap 'rm -f "$TMP" "$TMP.run"' EXIT

# ── Validate mode ────────────────────────────────────────────────────────
case "$MODE" in
  warm|cold|mixed) ;;
  *) echo "ERROR: mode must be warm, cold, or mixed (got: $MODE)" >&2; exit 2 ;;
esac

# ── Cache control helpers ────────────────────────────────────────────────
# Run a command with a 10-second watchdog (POSIX-compatible, no `timeout`)
# Usage: run_with_timeout <command> [args...]
# Streams inherit from caller; add redirects at the call site.
run_with_timeout() {
  "$@" &
  _pid=$!
  ( sleep 10; kill "$_pid" 2>/dev/null ) &
  _wd=$!
  wait "$_pid" 2>/dev/null || true
  kill "$_wd" 2>/dev/null || true
  wait "$_wd" 2>/dev/null || true
}

prime_cache() {
  run_with_timeout \
    env NVIM_APPNAME="$APP" nvim --headless \
    -c 'call timer_start(0, {-> execute("qa!")})'
}

purge_cache() {
  if [ "$(uname)" = "Darwin" ]; then
    sudo purge 2>/dev/null
  elif [ -f /proc/sys/vm/drop_caches ]; then
    sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null
  fi
}

# ── Collect ──────────────────────────────────────────────────────────────
printf "Running %d starts (%s)…\n" "$RUNS" "$MODE"

if [ "$MODE" = "warm" ]; then
  printf "  priming OS cache…"
  prime_cache
  printf " done\n"
elif [ "$MODE" = "cold" ]; then
  printf "  (sudo purge before each run — may prompt for password)\n"
  purge_cache  # first purge, also validates sudo early
fi

i=1; while [ "$i" -le "$RUNS" ]; do
  if [ "$MODE" = "cold" ]; then
    purge_cache
  fi
  : > "$TMP.run"
  run_with_timeout \
    env NVIM_APPNAME="$APP" nvim --startuptime "$TMP.run" --headless \
    -c 'call timer_start(0, {-> execute("qa!")})'
  cat "$TMP.run" >> "$TMP"
  i=$((i + 1))
done
rm -f "$TMP.run"

# ── Parse startup totals ────────────────────────────────────────────────
# Each run produces one session in --headless mode (STARTING → STARTED).
# Grab the last timestamp before each STARTED marker.
TIMES_RAW=$(awk '
  /--- N?VIM STARTING ---/ { last="" }
  /^[0-9]/                 { last=$1 }
  /--- N?VIM STARTED ---/  { if (last != "") print last }
' "$TMP")

if [ -z "$TIMES_RAW" ]; then
  echo "ERROR: no startup times captured" >&2
  exit 2
fi

# ── Parse slowest sourcing event ────────────────────────────────────────
SLOW_LINE=$(awk '/^[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+:/ {
  printf "%s %s\n", $2, substr($0, index($0,": ")+2)
}' "$TMP" | sort -nr | head -1)
SLOW_MS=$(echo "$SLOW_LINE" | awk '{printf "%.2f", $1}')
SLOW_FILE=$(echo "$SLOW_LINE" | cut -d' ' -f2-)

# ── Compute stats ───────────────────────────────────────────────────────
MEAN=$(echo "$TIMES_RAW" | awk '{ s+=$1; n++ } END { printf "%.2f", s/n }')
STD=$(echo "$TIMES_RAW" | awk -v m="$MEAN" '{ d=$1-m; s+=d*d; n++ } END { printf "%.2f", sqrt(s/n) }')
MIN=$(echo "$TIMES_RAW" | sort -n | head -1 | awk '{printf "%.2f", $1}')
MAX=$(echo "$TIMES_RAW" | sort -nr | head -1 | awk '{printf "%.2f", $1}')
MEDIAN=$(echo "$TIMES_RAW" | sort -n | awk '{ v[NR]=$1 } END {
  mid=int(NR/2)
  if (NR%2==1) printf "%.2f", v[mid+1]
  else printf "%.2f", (v[mid]+v[mid+1])/2
}')

# Steady-state stats: skip run 1 (priming artifact — cache/loader state
# written by prime or first measured run makes it unrepresentative)
COUNT=$(echo "$TIMES_RAW" | wc -l | tr -d ' ')
if [ "$COUNT" -gt 1 ]; then
  STEADY_RAW=$(echo "$TIMES_RAW" | tail -n +2)
  WARM_MEAN=$(echo "$STEADY_RAW" | awk '{ s+=$1; n++ } END { printf "%.2f", s/n }')
  WARM_STD=$(echo "$STEADY_RAW" | awk -v m="$WARM_MEAN" '{ d=$1-m; s+=d*d; n++ } END { printf "%.2f", sqrt(s/n) }')
else
  WARM_MEAN="$MEAN"
  WARM_STD="$STD"
fi

# ── Threshold checks ────────────────────────────────────────────────────
status() {
  val=$1; warn=$2; action=$3
  if [ "$(awk "BEGIN { print ($val > $action) }")" = "1" ]; then
    echo "🔴"
  elif [ "$(awk "BEGIN { print ($val > $warn) }")" = "1" ]; then
    echo "🟡"
  else
    echo "🟢"
  fi
}

S_MEAN=$(status "$MEAN" 150 200)
S_STD=$(status "$STD" 20 40)
S_SLOW=$(status "$SLOW_MS" 30 60)

# ── Quality rating ───────────────────────────────────────────────────────
quality() {
  ms=$1
  if [ "$(awk "BEGIN { print ($ms < 20) }")" = "1" ]; then
    echo "⚡ Exceptional"
  elif [ "$(awk "BEGIN { print ($ms < 50) }")" = "1" ]; then
    echo "🟢 Excellent"
  elif [ "$(awk "BEGIN { print ($ms < 80) }")" = "1" ]; then
    echo "🟢 Very good"
  elif [ "$(awk "BEGIN { print ($ms < 150) }")" = "1" ]; then
    echo "🟡 Acceptable"
  elif [ "$(awk "BEGIN { print ($ms < 300) }")" = "1" ]; then
    echo "🔴 Getting slow"
  else
    echo "💀 Plugin/config problems"
  fi
}

warm_quality() {
  ms=$1
  if [ "$(awk "BEGIN { print ($ms < 20) }")" = "1" ]; then
    echo "⚡ Exceptional"
  elif [ "$(awk "BEGIN { print ($ms < 35) }")" = "1" ]; then
    echo "🟢 Excellent"
  elif [ "$(awk "BEGIN { print ($ms < 50) }")" = "1" ]; then
    echo "🟢 Very good"
  elif [ "$(awk "BEGIN { print ($ms < 100) }")" = "1" ]; then
    echo "🟡 Acceptable"
  elif [ "$(awk "BEGIN { print ($ms < 200) }")" = "1" ]; then
    echo "🔴 Getting slow"
  else
    echo "💀 Plugin/config problems"
  fi
}

QUALITY=$(quality "$MEAN")
WARM_QUALITY=$(warm_quality "$WARM_MEAN")
# In warm mode, all runs are warm — rate the mean against warm scale
if [ "$MODE" = "warm" ]; then
  WARM_QUALITY=$(warm_quality "$MEAN")
fi

# ── Output ──────────────────────────────────────────────────────────────
hline() { printf "  \033[2m"; printf '─%.0s' $(seq 1 44); printf "\033[0m\n"; }
row()   { printf "  %-24s %s\n" "$1" "$2"; }
hint()  { printf "  %-24s \033[2m%s\033[0m\n" "" "$1"; }
head()  { printf "\n  \033[1m%s\033[0m\n" "$1"; hline; }
dim()   { printf "\033[2m%s\033[0m" "$1"; }

head "$APP Startup Benchmark ($RUNS runs, $MODE) — nvim-internal time only"
case "$MODE" in
  warm)  hint "All runs measured after OS cache is primed (steady-state performance)" ;;
  cold)  hint "Each run preceded by cache purge — but dyld/exec cost NOT measured" ;;
  mixed) hint "No cache control — run 1 may be cold, the rest benefit from warm cache" ;;
esac
row "Mean"                      "${MEAN} ms $(dim '· avg across all runs')"
row "Std"                       "${STD} ms $(dim '· lower = more consistent')"
row "Min / Max"                 "${MIN} / ${MAX} ms"
row "Median"                    "${MEDIAN} ms $(dim '· less affected by outliers')"
if [ "$MODE" != "cold" ] && [ "$RUNS" -gt 1 ]; then
  row "Steady mean"               "${WARM_MEAN} ms $(dim "· runs 2–${RUNS}, skip run 1 (priming artifact)")"
  row "Steady std"                "${WARM_STD} ms"
fi

head "Quality (nvim-internal — excludes dyld/exec; use hyperfine row below for wall-clock)"
case "$MODE" in
  warm)
    row "Steady (${WARM_MEAN} ms)"  "$WARM_QUALITY $(dim "· runs 2–${RUNS}; target <50 ms")"
    ;;
  cold)
    row "Cold internal (${MEAN} ms)" "$QUALITY $(dim '· nvim-internal only; target <80 ms')"
    ;;
  mixed)
    row "Cold internal (${MEAN} ms)" "$QUALITY $(dim '· nvim-internal only; target <80 ms')"
    if [ "$RUNS" -gt 1 ]; then
      row "Steady (${WARM_MEAN} ms)" "$WARM_QUALITY $(dim "· runs 2–${RUNS}; target <50 ms")"
    fi
    ;;
esac

head "Slowest sourcing event"
row "$(basename "$SLOW_FILE")"  "${SLOW_MS} ms $(dim '· most expensive file load')"

head "Thresholds"
row "$S_MEAN Mean < 150 / 200 ms"       "${MEAN} ms"
hint "warn if avg startup exceeds 150 ms, critical above 200 ms"
row "$S_STD Std  < 20 / 40 ms"          "${STD} ms"
hint "high variance means inconsistent runs, likely cold-cache outliers"
row "$S_SLOW Sourcing < 30 / 60 ms"     "${SLOW_MS} ms"
hint "single file load time from --startuptime sourcing events"

head "Raw (ms)"
printf "  "; echo "$TIMES_RAW" | awk '{printf "%.1f  ", $1}' | sed 's/  $//'
echo ""
hline

# ── Wall-clock truth via hyperfine ──────────────────────────────────────
# Hyperfine measures full process wall-time (including dyld/exec/teardown),
# which is what the user actually waits for. Trust this number over the
# nvim-internal stats above.
if command -v hyperfine >/dev/null 2>&1; then
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/beast-bench"
  mkdir -p "$CACHE_DIR"
  TS=$(date +%Y%m%d-%H%M%S)
  JSON_PATH="$CACHE_DIR/startup-${APP}-${MODE}-${TS}.json"

  head "Wall-clock (hyperfine, $RUNS runs) — trust this over the above"
  case "$MODE" in
    warm)
      HF_PREPARE=""
      HF_WARMUP="--warmup 3"
      hint "Warmup runs prime OS cache; reports steady-state wall-clock"
      ;;
    cold)
      # Reuse cached sudo timestamp from earlier purge_cache calls. If it
      # has expired, the prepare command will fail and hyperfine will skip.
      HF_PREPARE="--prepare 'sudo -n purge 2>/dev/null || sudo purge'"
      HF_WARMUP="--warmup 0"
      hint "Cache purged before each run; includes dyld/exec cost (true cold)"
      ;;
    mixed)
      HF_PREPARE=""
      HF_WARMUP="--warmup 0"
      hint "No cache control; matches real first-launch experience after warmup"
      ;;
  esac

  HF_CMD="env NVIM_APPNAME=\"$APP\" nvim --headless -c 'qa!'"
  # shellcheck disable=SC2086
  HF_OUT=$(eval hyperfine --shell=none --runs "$RUNS" $HF_WARMUP $HF_PREPARE \
    --export-json "\"$JSON_PATH\"" \
    "\"$HF_CMD\"" 2>&1)

  HF_MEAN=$(echo "$HF_OUT" | awk '/Time \(mean/ { for(i=1;i<=NF;i++) if($i=="ms"){print $(i-1); exit} }')
  HF_STD=$(echo "$HF_OUT"  | awk '/Time \(mean/ { c=0; for(i=1;i<=NF;i++) if($i=="ms"){c++; if(c==2){print $(i-1); exit}} }')
  HF_RANGE=$(echo "$HF_OUT" | awk '/Range \(min/ { sub(/.*: */,""); sub(/  *[0-9]+ runs.*/,""); print }')

  if [ -n "$HF_MEAN" ]; then
    row "Wall-clock mean"          "${HF_MEAN} ms ± ${HF_STD} ms $(dim '· what the user waits for')"
    row "Range"                    "${HF_RANGE}"
    row "JSON"                     "$(dim "$JSON_PATH")"
  else
    row "hyperfine"                "(failed — see output below)"
    echo "$HF_OUT" | sed 's/^/    /'
  fi
  hline
else
  printf "\n  \033[2m(install hyperfine for wall-clock measurements: brew install hyperfine)\033[0m\n"
fi
