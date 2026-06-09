#!/usr/bin/env bash
# scripts/bench-ux.sh — UX latency benchmark suite (key-to-paint in a real wezterm pane).
#
# What this measures
# ------------------
#   The single most important UX metric: **key-to-paint latency** — the time
#   from a key arriving at Neovim to the next redraw cycle finishing.
#   Captured inside Neovim via `vim.on_key` (key arrival) + a decoration
#   provider's `on_end` (redraw done). See scripts/bench-ux/probe.lua.
#
#   Targets the bottlenecks identified in docs/neovim/latency-research.md:
#     • per-line decoration callbacks (TS + LSP + plugins)
#     • extmark scaling / namespace clears
#     • redraw amplification (statuscolumn, providers, virt_text)
#     • long-session growth (extmark / autocmd / Lua ref leaks)
#
# Scenarios
# ---------
#   keypress    Baseline j/k/gg/G on a small file. Sanity floor.
#   scroll      <C-d>/<C-u> through a 100k-line file. Tests TS + redraw cost.
#   bufswitch   :bnext through N pre-loaded buffers. Tests BufEnter/WinEnter
#               handlers and FOR_ALL_BUFFERS-style autocmds.
#   extmarks    Movement with N pre-placed extmarks (sign + inline virt_text).
#               Tests marktree lookup + decoration redraw amplification.
#   longsession Mixed workload for $LONG_MINUTES minutes, snapshot every
#               $LONG_INTERVAL seconds. Plots latency/memory growth.
#   keymaps     Drive every user-facing keymap from lua/beast/init.lua
#               (finder, explorer, git, packer UI, tabline, window, …).
#               Forces LOAD_USER_CONFIG=1 + FIXTURE_GIT=1 (real hunks for
#               []c / <leader>g*). Prints aggregate p50/p99 plus a
#               per-keymap latency table so cold loads stand out.
#   all         Runs keypress + scroll + bufswitch + extmarks + keymaps
#               (skips longsession).
#
# Usage
# -----
#   ./scripts/bench-ux.sh keypress
#   ./scripts/bench-ux.sh scroll
#   ./scripts/bench-ux.sh bufswitch
#   EXTMARKS_N=10000 ./scripts/bench-ux.sh extmarks
#   LONG_MINUTES=10 LONG_INTERVAL=30 ./scripts/bench-ux.sh longsession
#   ./scripts/bench-ux.sh keymaps
#   ./scripts/bench-ux.sh all
#
# Environment knobs
# -----------------
#   ITERS              keys to feed per scenario (default 60)
#   KEY_DELAY          seconds between keys (default 0.08; smaller = more pressure)
#   BUFSWITCH_N        buffers to preload (default 100)
#   EXTMARKS_N         extmarks to seed (default 10000)
#   EXTMARK_VIRT       1 to add inline virt_text per mark (worst-case redraw cost)
#   SCROLL_LINES       lines in the scroll-test fixture (default 100000)
#   LONG_MINUTES       longsession duration (default 5)
#   LONG_INTERVAL      longsession snapshot cadence in seconds (default 30)
#   BEAST_PATH         repo root (default: parent of this script)
#   LOAD_USER_CONFIG   1 to load $NVIM_APPNAME config instead of bare; tests YOUR
#                      full plugin stack. Default 0 (bare nvim = baseline).
#   NVIM_APPNAME       Explicitly pick which config to load. Inherited from the
#                      calling shell if set; otherwise defaults to "BeastVim"
#                      when LOAD_USER_CONFIG=1 so we never silently fall through
#                      to ~/.config/nvim. Override with NVIM_APPNAME=nvim to
#                      bench the default config dir.
#   FIXTURE_LANG       txt | lua | py — controls fixture file content for the
#                      scroll/bufswitch/longsession scenarios. txt is cheap
#                      (no LSP/TS); lua and py trigger your real plugin stack
#                      (LSP attach, Treesitter parse, ftplugin). Default txt.
#   FIXTURE_GIT        1 to turn fixture dirs into git repos with mixed states
#                      (modified / staged / untracked / deleted). Stresses
#                      gitsigns / beast.libs.git per-buffer attach + diff cost.
#                      Default 0.
#   KEEP_LOGS          1 to leave logs in $TMPDIR for inspection
#
# Exit codes
# ----------
#   0 PASS  1 FAIL (threshold tripped)  2 setup error
#
# Requirements: wezterm (running, accessible via `wezterm cli`), nvim ≥ 0.10,
# python3. Must run from a host already inside wezterm.

set -eu

# ── config ────────────────────────────────────────────────────────────────
ITERS="${ITERS:-60}"
KEY_DELAY="${KEY_DELAY:-0.08}"
BUFSWITCH_N="${BUFSWITCH_N:-100}"
EXTMARKS_N="${EXTMARKS_N:-10000}"
EXTMARK_VIRT="${EXTMARK_VIRT:-0}"
SCROLL_LINES="${SCROLL_LINES:-100000}"
LONG_MINUTES="${LONG_MINUTES:-5}"
LONG_INTERVAL="${LONG_INTERVAL:-30}"
LOAD_USER_CONFIG="${LOAD_USER_CONFIG:-0}"
# When loading user config, never silently fall through to ~/.config/nvim.
# Default to BeastVim (the dir this script lives in) unless overridden.
if [ "$LOAD_USER_CONFIG" = "1" ] && [ -z "${NVIM_APPNAME:-}" ]; then
  NVIM_APPNAME="BeastVim"
fi
export NVIM_APPNAME
FIXTURE_LANG="${FIXTURE_LANG:-txt}"
FIXTURE_GIT="${FIXTURE_GIT:-0}"
KEEP_LOGS="${KEEP_LOGS:-0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BEAST_PATH="${BEAST_PATH:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PROBE="$SCRIPT_DIR/bench-ux/probe.lua"
SUMMARISE="$SCRIPT_DIR/bench-ux/summarise.py"

# Per-scenario thresholds (median / p99 ms). Tuned for bare nvim on Apple
# Silicon. If LOAD_USER_CONFIG=1 these will likely trip — that IS the signal.
TH_KEYPRESS_P50=8    ; TH_KEYPRESS_P99=25
TH_SCROLL_P50=20     ; TH_SCROLL_P99=80
TH_BUFSWITCH_P50=25  ; TH_BUFSWITCH_P99=120
TH_EXTMARKS_P50=20   ; TH_EXTMARKS_P99=100
TH_LONG_P50=30       ; TH_LONG_P99=150
# keymaps mixes cold plugin loads (finder/packer/explorer open) with cheap
# motions ([]c, <leader>n) so the aggregate p99 is intentionally loose; the
# real signal is the per-keymap breakdown printed by summarise.py.
TH_KEYMAPS_P50=40    ; TH_KEYMAPS_P99=500

# ── working dir ───────────────────────────────────────────────────────────
WORK="${TMPDIR:-/tmp}/bench-ux.$$"
mkdir -p "$WORK"
if [ "$KEEP_LOGS" = "1" ]; then
  trap 'echo "  (logs kept in $WORK)"' EXIT
else
  trap 'rm -rf "$WORK"' EXIT
fi

# ── prereqs ───────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'" >&2; exit 2; }; }
need wezterm; need nvim; need python3; need git
wezterm cli list >/dev/null 2>&1 || {
  echo "ERROR: 'wezterm cli list' failed — must run from inside wezterm" >&2; exit 2
}
[ -f "$PROBE" ] || { echo "ERROR: probe missing: $PROBE" >&2; exit 2; }
[ -f "$SUMMARISE" ] || { echo "ERROR: summariser missing: $SUMMARISE" >&2; exit 2; }

# ── wezterm key plumbing ─────────────────────────────────────────────────
# wezterm cli send-text takes literal bytes. Control characters must be piped.
PANE=""
ctl_bytes() {
  case "$1" in
    esc) printf '\x1b' ;;
    cr)  printf '\r'   ;;
    cd)  printf '\x04' ;;   # Ctrl-D
    cu)  printf '\x15' ;;   # Ctrl-U
    cf)  printf '\x06' ;;   # Ctrl-F
    cb)  printf '\x02' ;;   # Ctrl-B
    ce)  printf '\x05' ;;   # Ctrl-E
    cy)  printf '\x19' ;;   # Ctrl-Y
    *) echo "unknown ctl: $1" >&2; return 1 ;;
  esac
}
send_text() { wezterm cli send-text --no-paste --pane-id "$PANE" -- "$1"; }
send_ctl()  { ctl_bytes "$1" | wezterm cli send-text --no-paste --pane-id "$PANE"; }
send_cmd()  { send_text ":$1"; send_ctl cr; }
sleep_key() { sleep "$KEY_DELAY"; }

# ── git fixture helper ───────────────────────────────────────────────────
# Turn a directory full of files into a git repo with a realistic mix of
# states. Called by fixture builders when FIXTURE_GIT=1. Produces:
#   ~1/3 modified (unstaged)        → gitsigns shows "~"
#   ~1/8 staged modifications       → "±" / "M" (index ≠ HEAD)
#   ~1/12 deleted (unstaged)        → "_"
#   ~1/8 untracked new files        → "?"
# Plus the rest unchanged (clean).
maybe_git_init() {
  [ "${FIXTURE_GIT:-0}" = "1" ] || return 0
  dir=$1
  ( cd "$dir" && git init -q -b main && \
      git config user.email bench@local && \
      git config user.name bench >/dev/null
  ) || return 1

  python3 - "$dir" <<'PY'
import os, sys, glob, subprocess
d = sys.argv[1]
os.chdir(d)

# Commit baseline
subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(["git", "commit", "-q", "-m", "init"], check=True)

files = sorted(f for f in glob.glob("*") if os.path.isfile(f))
if not files:
    sys.exit(0)
ext = files[0].rsplit(".", 1)[-1] if "." in files[0] else "txt"

# 1. Modify ~1/3 of files (unstaged changes)
modified = files[::3]
for p in modified:
    with open(p, "a") as f:
        f.write(f"\n-- modified line for bench\n-- second modified line\n")

# 2. Stage ~1/8 of files with their own change (staged modifications)
staged = files[1::8]
for p in staged:
    with open(p, "a") as f:
        f.write("\n-- staged-only change\n")
subprocess.run(["git", "add", "--"] + staged, check=True)

# Re-modify the staged files so they're "staged + unstaged" (the worst
# case — gitsigns has to diff index-vs-HEAD AND buffer-vs-index).
for p in staged[:max(1, len(staged) // 2)]:
    with open(p, "a") as f:
        f.write("-- additional unstaged after stage\n")

# 3. Delete ~1/12 of files (unstaged deletions)
for p in files[::12][:max(1, len(files) // 12)]:
    if os.path.isfile(p) and p not in modified and p not in staged:
        os.remove(p)

# 4. Add ~1/8 untracked new files
for i in range(max(1, len(files) // 8)):
    with open(f"untracked_{i:03d}.{ext}", "w") as f:
        f.write(f"-- new untracked {i}\n-- line 2\n-- line 3\n")

# Confirm states for our own sanity in the log
status = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
print(f"git status: {len(status.splitlines())} entries", file=sys.stderr)
PY
}

# ── scenario-specific init.lua generators ────────────────────────────────
# Each generator emits an init that:
#   1. (optionally) loads the user's full nvim config
#   2. sources $PROBE
#   3. does scenario-specific setup (open files, seed extmarks, ...)

base_init_head() {
  cat <<LUA
-- generated by bench-ux.sh
vim.o.swapfile = false
vim.o.shada = ""
vim.o.termguicolors = true
vim.o.lazyredraw = false
LUA
  if [ "$LOAD_USER_CONFIG" = "1" ]; then
    cat <<LUA
-- Load full user config (whatever \$NVIM_APPNAME points at). Write the
-- resolved config dir directly to the bench log so it's self-describing
-- even before the probe loads.
do
  local f = io.open(vim.env.BENCH_LOG or "/dev/null", "a")
  if f then
    f:write(string.format("# nvim_appname=%s loaded_config=%s\n",
      vim.env.NVIM_APPNAME or "<unset>", vim.fn.stdpath("config") .. "/init.lua"))
    f:close()
  end
end
local cfg = vim.fn.stdpath("config") .. "/init.lua"
if vim.uv.fs_stat(cfg) then dofile(cfg) end
LUA
  fi
  echo "dofile([[${PROBE}]])"
}

write_init_keypress() {
  base_init_head >"$WORK/init-keypress.lua"
  cat >>"$WORK/init-keypress.lua" <<LUA
-- Small file, just exercise motion.
local lines = {}
for i = 1, 200 do lines[i] = string.format("line %03d  hello world the quick brown fox", i) end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
LUA
}

write_init_scroll() {
  # Language-aware scroll fixture so we exercise TS / LSP / ftplugin for real.
  ext="$FIXTURE_LANG"
  big="$WORK/scroll/big.${ext}"
  mkdir -p "$WORK/scroll"
  python3 - "$big" "$SCROLL_LINES" "$FIXTURE_LANG" <<'PY'
import sys
path, n, lang = sys.argv[1], int(sys.argv[2]), sys.argv[3]
with open(path, "w") as f:
    if lang == "lua":
        f.write("local M = {}\nM.items = {\n")
        for i in range(1, n + 1):
            f.write(f'  {{ id = {i}, name = "item_{i:07d}", tag = "alpha-bravo-charlie" }},\n')
        f.write("}\nreturn M\n")
    elif lang == "py":
        f.write("from dataclasses import dataclass\n\n@dataclass\nclass Item:\n    id: int\n    name: str\n    tag: str\n\nITEMS = [\n")
        for i in range(1, n + 1):
            f.write(f'    Item(id={i}, name="item_{i:07d}", tag="alpha-bravo-charlie"),\n')
        f.write("]\n")
    else:
        for i in range(1, n + 1):
            f.write(f"line {i:07d}  alpha bravo charlie delta echo foxtrot golf hotel india juliet\n")
PY
  maybe_git_init "$WORK/scroll"
  base_init_head >"$WORK/init-scroll.lua"
  cat >>"$WORK/init-scroll.lua" <<LUA
vim.cmd("edit ${big}")
LUA
}

write_init_bufswitch() {
  ext="$FIXTURE_LANG"
  python3 - "$WORK/bufs" "$BUFSWITCH_N" "$FIXTURE_LANG" <<'PY'
import sys, os
d, n, lang = sys.argv[1], int(sys.argv[2]), sys.argv[3]
os.makedirs(d, exist_ok=True)
for i in range(n):
    if lang == "lua":
        p = f"{d}/mod_{i:04d}.lua"
        with open(p, "w") as f:
            f.write(f"local M = {{}}\n\nfunction M.hello_{i}()\n  return 'hello from module {i}'\nend\n\n")
            for j in range(1, 80):
                f.write(f"function M.helper_{j}(x)\n  return x + {j} + {i}\nend\n\n")
            f.write("return M\n")
    elif lang == "py":
        p = f"{d}/mod_{i:04d}.py"
        with open(p, "w") as f:
            f.write(f'"""Module {i}."""\nfrom typing import Any\n\n')
            for j in range(1, 80):
                f.write(f"def helper_{j}(x: int) -> int:\n    return x + {j} + {i}\n\n")
            f.write(f"def hello_{i}() -> str:\n    return 'hello from module {i}'\n")
    else:
        p = f"{d}/file_{i:04d}.txt"
        with open(p, "w") as f:
            for j in range(1, 401):
                f.write(f"buffer {i} line {j} lorem ipsum dolor sit amet consectetur\n")
PY
  maybe_git_init "$WORK/bufs"
  base_init_head >"$WORK/init-bufswitch.lua"
  cat >>"$WORK/init-bufswitch.lua" <<LUA
local dir = "${WORK}/bufs"
-- Skip dotfiles (.git/) so we don't try to badd repo internals.
local files = vim.tbl_filter(function(f) return not f:match("/%.") end,
  vim.fn.glob(dir .. "/*", false, true))
table.sort(files)
for _, f in ipairs(files) do vim.cmd("badd " .. vim.fn.fnameescape(f)) end
vim.cmd("buffer " .. vim.fn.fnameescape(files[1]))
_G.bench_log(string.format("# loaded_bufs=%d lang=${FIXTURE_LANG} git=${FIXTURE_GIT}\n", #files))
LUA
}

write_init_extmarks() {
  python3 - "$WORK/marks.txt" 5000 <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    for i in range(1, n + 1):
        f.write(f"line {i:06d}  the quick brown fox jumps over the lazy dog\n")
PY
  base_init_head >"$WORK/init-extmarks.lua"
  cat >>"$WORK/init-extmarks.lua" <<LUA
vim.cmd("edit ${WORK}/marks.txt")
local n_marks = ${EXTMARKS_N}
local with_virt = ${EXTMARK_VIRT} == 1
local ns = vim.api.nvim_create_namespace("bench_seed")
local line_count = vim.api.nvim_buf_line_count(0)
local buf = 0
-- Distribute n_marks across the buffer; if there are more marks than lines,
-- stack multiple per line (realistic for diagnostics-heavy buffers).
for i = 0, n_marks - 1 do
  local row = i % line_count
  local opts = { hl_group = (i % 3 == 0) and "DiffAdd" or (i % 3 == 1) and "DiffChange" or "DiffDelete" }
  if with_virt then
    opts.virt_text = { { "●", "WarningMsg" } }
    opts.virt_text_pos = "inline"
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, opts)
end
_G.bench_log(string.format("# seeded_extmarks=%d virt=%s\n", n_marks, tostring(with_virt)))
LUA
}

write_init_longsession() {
  # Mix of files for the long session.
  python3 - "$WORK/long" 20 2000 <<'PY'
import sys, os
d, n, lines = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
os.makedirs(d, exist_ok=True)
for i in range(n):
    with open(f"{d}/f_{i:03d}.txt", "w") as f:
        for j in range(1, lines + 1):
            f.write(f"f{i} line {j} sphinx of black quartz judge my vow\n")
PY
  maybe_git_init "$WORK/long"
  base_init_head >"$WORK/init-longsession.lua"
  cat >>"$WORK/init-longsession.lua" <<LUA
local dir = "${WORK}/long"
local files = vim.fn.glob(dir .. "/*.txt", false, true)
for _, f in ipairs(files) do vim.cmd("badd " .. vim.fn.fnameescape(f)) end
vim.cmd("buffer " .. vim.fn.fnameescape(files[1]))
-- Seed a diagnostics-like namespace we'll churn over the session.
_G.bench_churn_ns = vim.api.nvim_create_namespace("bench_churn")
function _G.bench_churn(buf, n)
  vim.api.nvim_buf_clear_namespace(buf, _G.bench_churn_ns, 0, -1)
  local lc = vim.api.nvim_buf_line_count(buf)
  for i = 0, n - 1 do
    pcall(vim.api.nvim_buf_set_extmark, buf, _G.bench_churn_ns, i % lc, 0,
      { virt_text = {{ "✱", "ErrorMsg" }}, virt_text_pos = "eol" })
  end
end
_G.bench_log(string.format("# longsession files=%d\n", #files))
LUA
}

# ── keymaps scenario ─────────────────────────────────────────────────────
# Exercises every user-facing keymap registered in lua/beast/init.lua:
#   <leader>n          dismiss notifications
#   <leader>p          packer UI            (Esc/q closes)
#   <leader>e          toggle explorer      (toggled twice)
#   <leader>f|b|/|h|c  finder pickers       (Esc closes)
#   <leader>zz|z=      window zoom/equalise (requires a vsplit)
#   [B / ]B            tabline move buffer
#   ]c / [c            git hunk nav         (needs FIXTURE_GIT=1)
#   <leader>gp         preview hunk         (Esc closes float)
#   <leader>gs|gu|gr   stage/unstage/reset hunk
#   <leader>g.         repeat last git action
#   <leader>d          close buffer         (destructive — runs last)
#
# Forces LOAD_USER_CONFIG=1 + a git-state lua fixture so the git+lazy keymaps
# have realistic targets to act on. The runner brackets each press with
# :BenchMark km_<name>, so summarise.py --per-keymap can split the paint
# stream into per-keymap latency rows.
write_init_keymaps() {
  rm -rf "$WORK/keymaps"
  mkdir -p "$WORK/keymaps"
  python3 - "$WORK/keymaps" 8 <<'PY'
import sys, os
d, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    p = f"{d}/mod_{i:04d}.lua"
    with open(p, "w") as f:
        f.write(f"local M = {{}}\n\nfunction M.hello_{i}()\n  return 'hello {i}'\nend\n\n")
        for j in range(1, 40):
            f.write(f"function M.helper_{j}(x)\n  return x + {j} + {i}\nend\n\n")
        f.write("return M\n")
PY
  # Force a git fixture (mixed-state) so hunk keymaps have hunks to navigate
  # — independent of the caller's FIXTURE_GIT setting.
  _saved_git=${FIXTURE_GIT:-0}; FIXTURE_GIT=1
  maybe_git_init "$WORK/keymaps"
  FIXTURE_GIT="$_saved_git"

  base_init_head >"$WORK/init-keymaps.lua"
  cat >>"$WORK/init-keymaps.lua" <<LUA
local dir = "${WORK}/keymaps"
local files = vim.tbl_filter(function(f) return not f:match("/%.") end,
  vim.fn.glob(dir .. "/*.lua", false, true))
table.sort(files)
-- Pre-load every file as a hidden buffer so tabline []B / bnext have targets.
for _, f in ipairs(files) do vim.cmd("badd " .. vim.fn.fnameescape(f)) end
-- Open mod_0000.lua (modified by maybe_git_init → has unstaged hunks).
vim.cmd("buffer " .. vim.fn.fnameescape(files[1]))
-- Give window keymaps something to operate on.
vim.cmd("vsplit " .. vim.fn.fnameescape(files[2]))
vim.cmd("wincmd p") -- back to the modified buffer
_G.bench_log(string.format("# keymaps fixture=%d files vsplit=1\n", #files))
LUA
}

run_keymaps() {
  echo
  echo "  ── keymaps (drive every lua/beast/init.lua binding) ──"
  if [ "$LOAD_USER_CONFIG" != "1" ]; then
    echo "  (forcing LOAD_USER_CONFIG=1 — bare nvim has no BeastVim keymaps)"
    LOAD_USER_CONFIG=1
    [ -z "${NVIM_APPNAME:-}" ] && NVIM_APPNAME="BeastVim"
    export NVIM_APPNAME
  fi
  # This scenario is BeastVim-specific: it drives bindings registered in
  # lua/beast/init.lua. Under any other config the keys fall through to
  # random normal/insert-mode behaviour, corrupting :BenchMark args and
  # producing meaningless latency numbers. Refuse rather than mislead.
  if [ "${NVIM_APPNAME:-BeastVim}" != "BeastVim" ]; then
    echo "  SKIP: 'keymaps' is BeastVim-specific (NVIM_APPNAME=$NVIM_APPNAME)."
    echo "        Use keypress/scroll/bufswitch/extmarks for cross-config comparisons."
    return 0
  fi
  write_init_keymaps
  spawn_pane "$WORK/init-keymaps.lua" "$WORK/keymaps.log" "$WORK/keymaps" || return $?
  # Extra settle time: lazy loaders register on first event/key.
  sleep 1.0

  # Helper: mark + send keys + optional recovery (esc by default) + settle.
  #   $1 name   $2 raw key string   $3 settle seconds (default 0.25)
  #   $4 recovery: "esc" (default), "none", "esc2", "q"
  km() {
    name=$1; keys=$2; settle=${3:-0.25}; recovery=${4:-esc}
    send_cmd "BenchMark km_${name}"
    send_text "$keys"
    sleep "$settle"
    case "$recovery" in
      none) ;;
      esc)  send_ctl esc ;;
      esc2) send_ctl esc; sleep 0.1; send_ctl esc ;;
      q)    send_text "q" ;;
    esac
    sleep 0.2
  }

  # Notification + simple no-UI keymaps first (cheapest, warm up).
  km notify_dismiss " n" 0.15 none

  # Tabline move (no UI). 'badd' gave us multiple buffers.
  km tabline_move_next "]B" 0.15 none
  km tabline_move_prev "[B" 0.15 none

  # Window keymaps (we vsplit in init).
  km window_zoom     " zz" 0.20 none
  km window_equalize " z=" 0.20 none

  # Git hunk navigation + actions. Buffer has unstaged hunks (added by
  # maybe_git_init). Nav first so a hunk is under the cursor for the actions.
  km git_next_hunk    "]c"  0.20 none
  km git_prev_hunk    "[c"  0.20 none
  km git_preview_hunk " gp" 0.40 esc
  km git_stage_hunk   " gs" 0.35 none
  km git_unstage_hunk " gu" 0.35 none
  km git_repeat       " g." 0.30 none
  km git_reset_hunk   " gr" 0.35 none

  # Finder pickers — each one is a cold lazy load on first press.
  km finder_files       " f"  0.60 esc
  km finder_buffers     " b"  0.40 esc
  km finder_live_grep   " /"  0.40 esc
  km finder_help_tags   " h"  0.40 esc
  # <leader>c previews colorschemes by swapping; Esc restores original.
  km finder_colorschemes " c" 0.50 esc

  # Packer UI (cold lazy load).
  km packer_ui " p" 0.60 q

  # Explorer toggle: open + close (two distinct paints).
  km explorer_open  " e" 0.50 none
  km explorer_close " e" 0.30 none

  # Destructive — must come last. Closes current buffer.
  km buffer_delete " d" 0.30 none

  quit_pane
  python3 "$SUMMARISE" "$WORK/keymaps.log" "keymaps" \
    "$TH_KEYMAPS_P50" "$TH_KEYMAPS_P99" --per-keymap
}

# ── pane lifecycle ───────────────────────────────────────────────────────
spawn_pane() {
  init=$1; log=$2; cwd=$3
  rm -f "$log"
  # Propagate NVIM_APPNAME explicitly so the spawned nvim resolves the
  # intended ~/.config/$NVIM_APPNAME, regardless of how the wezterm mux
  # was launched. Always set BENCH_LOG. Pass NVIM_APPNAME only when set
  # (empty would confuse nvim).
  if [ -n "${NVIM_APPNAME:-}" ]; then
    PANE=$(wezterm cli spawn --cwd "$cwd" -- \
      env BENCH_LOG="$log" NVIM_APPNAME="$NVIM_APPNAME" \
      nvim -u "$init" "${@:4}")
  else
    PANE=$(wezterm cli spawn --cwd "$cwd" -- \
      env BENCH_LOG="$log" nvim -u "$init" "${@:4}")
  fi
  [ -n "$PANE" ] || { echo "ERROR: spawn failed" >&2; return 2; }
  echo "  spawned pane=$PANE init=${init##*/} NVIM_APPNAME=${NVIM_APPNAME:-<unset>}"
  sleep 2.0  # let nvim start, run probe deferred snap
}

quit_pane() {
  send_cmd "BenchQuit"
  sleep 0.8
  # Force-close the pane: wezterm's `exit_behavior` defaults vary by user
  # config ("Hold" leaves the pane open after the child exits). kill-pane
  # is idempotent — silently no-ops if the pane already closed.
  [ -n "${PANE:-}" ] && wezterm cli kill-pane --pane-id "$PANE" 2>/dev/null || true
}

# ── scenarios ────────────────────────────────────────────────────────────
run_keypress() {
  echo
  echo "  ── keypress (motion on small file) ──"
  write_init_keypress
  spawn_pane "$WORK/init-keypress.lua" "$WORK/keypress.log" "$WORK" || return $?

  # Mix of j/k/G/gg/<C-d>/<C-u> — each should produce one paint.
  i=1; while [ "$i" -le "$ITERS" ]; do
    case $((i % 7)) in
      0) send_text "j" ;;
      1) send_text "k" ;;
      2) send_text "j" ;;
      3) send_text "gg" ;;
      4) send_text "G" ;;
      5) send_ctl  cd  ;;
      6) send_ctl  cu  ;;
    esac
    sleep_key
    i=$((i + 1))
  done

  quit_pane
  python3 "$SUMMARISE" "$WORK/keypress.log" "keypress" "$TH_KEYPRESS_P50" "$TH_KEYPRESS_P99"
}

run_scroll() {
  echo
  echo "  ── scroll ($SCROLL_LINES-line file, <C-d>/<C-u>) ──"
  write_init_scroll
  spawn_pane "$WORK/init-scroll.lua" "$WORK/scroll.log" "$WORK" || return $?

  i=1; while [ "$i" -le "$ITERS" ]; do
    if [ $((i % 2)) -eq 0 ]; then send_ctl cd; else send_ctl cu; fi
    sleep_key
    i=$((i + 1))
  done
  send_text "G"; sleep_key
  send_text "gg"; sleep_key

  quit_pane
  python3 "$SUMMARISE" "$WORK/scroll.log" "scroll" "$TH_SCROLL_P50" "$TH_SCROLL_P99"
}

run_bufswitch() {
  echo
  echo "  ── bufswitch ($BUFSWITCH_N buffers, :bnext) ──"
  write_init_bufswitch
  spawn_pane "$WORK/init-bufswitch.lua" "$WORK/bufswitch.log" "$WORK" || return $?

  i=1; while [ "$i" -le "$ITERS" ]; do
    send_cmd "bnext"
    sleep_key
    i=$((i + 1))
  done
  i=1; while [ "$i" -le 10 ]; do
    send_cmd "bprev"
    sleep_key
    i=$((i + 1))
  done

  quit_pane
  python3 "$SUMMARISE" "$WORK/bufswitch.log" "bufswitch" "$TH_BUFSWITCH_P50" "$TH_BUFSWITCH_P99"
}

run_extmarks() {
  echo
  echo "  ── extmarks ($EXTMARKS_N marks, virt=$EXTMARK_VIRT, scroll) ──"
  write_init_extmarks
  spawn_pane "$WORK/init-extmarks.lua" "$WORK/extmarks.log" "$WORK" || return $?

  i=1; while [ "$i" -le "$ITERS" ]; do
    case $((i % 4)) in
      0) send_ctl cd ;;
      1) send_ctl cu ;;
      2) send_text "j" ;;
      3) send_text "k" ;;
    esac
    sleep_key
    i=$((i + 1))
  done

  quit_pane
  python3 "$SUMMARISE" "$WORK/extmarks.log" "extmarks" "$TH_EXTMARKS_P50" "$TH_EXTMARKS_P99"
}

run_longsession() {
  echo
  echo "  ── longsession (${LONG_MINUTES}min, snap every ${LONG_INTERVAL}s) ──"
  write_init_longsession
  spawn_pane "$WORK/init-longsession.lua" "$WORK/longsession.log" "$WORK" || return $?

  end_ts=$(( $(date +%s) + LONG_MINUTES * 60 ))
  next_snap=$(( $(date +%s) + LONG_INTERVAL ))
  cycle=0

  while [ "$(date +%s)" -lt "$end_ts" ]; do
    # 1) scroll a bit
    j=1; while [ "$j" -le 10 ]; do send_ctl cd; sleep_key; j=$((j+1)); done

    # 2) switch buffer
    send_cmd "bnext"; sleep_key

    # 3) churn extmarks (simulates LSP diagnostics rebuild)
    send_cmd "lua bench_churn(0, 500)"
    sleep_key

    # 4) cursor movement
    send_text "ggG"; sleep_key

    # 5) periodic snapshot
    now=$(date +%s)
    if [ "$now" -ge "$next_snap" ]; then
      cycle=$((cycle + 1))
      send_cmd "BenchSnap cycle_${cycle}"
      sleep 0.3
      next_snap=$(( now + LONG_INTERVAL ))
      printf "    snap %d at t+%ds\n" "$cycle" "$(( now - (end_ts - LONG_MINUTES * 60) ))"
    fi
  done

  quit_pane
  python3 "$SUMMARISE" "$WORK/longsession.log" "longsession" \
    "$TH_LONG_P50" "$TH_LONG_P99" --longsession
}

# ── main ─────────────────────────────────────────────────────────────────
print_header() {
  cat <<EOF

  $(tput bold 2>/dev/null)Neovim UX latency benchmark$(tput sgr0 2>/dev/null)
  ─────────────────────────────────────────────────────
  metric:         key-to-paint (vim.on_key → decoration on_end)
  iterations:     $ITERS keys / scenario   key_delay: ${KEY_DELAY}s
  load_config:    $LOAD_USER_CONFIG (0 = bare nvim baseline, 1 = your full stack)
  NVIM_APPNAME:   ${NVIM_APPNAME:-<unset>} (resolved config dir = \$XDG_CONFIG_HOME/\$NVIM_APPNAME)
  fixture_lang:   $FIXTURE_LANG (txt = cheap, lua/py = LSP+TS+ftplugin)
  fixture_git:    $FIXTURE_GIT (1 = repo with modified/staged/untracked/deleted)
  work dir:       $WORK
  thresholds:     keypress p50≤${TH_KEYPRESS_P50}/p99≤${TH_KEYPRESS_P99}ms,
                  scroll   p50≤${TH_SCROLL_P50}/p99≤${TH_SCROLL_P99}ms,
                  bufsw    p50≤${TH_BUFSWITCH_P50}/p99≤${TH_BUFSWITCH_P99}ms,
                  extmark  p50≤${TH_EXTMARKS_P50}/p99≤${TH_EXTMARKS_P99}ms,
                  keymaps  p50≤${TH_KEYMAPS_P50}/p99≤${TH_KEYMAPS_P99}ms

EOF
}

usage() {
  sed -n '1,/^set -eu/p' "$0" | sed '$d'
  exit 2
}

cmd="${1:-help}"
case "$cmd" in
  keypress|scroll|bufswitch|extmarks|longsession|keymaps)
    print_header
    "run_${cmd}"
    ;;
  all)
    print_header
    rc=0
    run_keypress  || rc=$?
    run_scroll    || rc=$?
    run_bufswitch || rc=$?
    run_extmarks  || rc=$?
    run_keymaps   || rc=$?
    echo
    exit "$rc"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "ERROR: unknown scenario '$cmd'" >&2
    usage
    ;;
esac
