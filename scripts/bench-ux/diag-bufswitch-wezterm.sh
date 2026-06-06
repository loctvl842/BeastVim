#!/usr/bin/env bash
# scripts/bench-ux/diag-bufswitch-wezterm.sh
# Why bufswitch leaks per-buffer state. Spawns a wezterm pane with the full
# user config, generates N source files (optionally in a git repo with mixed
# states), cycles through them, and dumps a histogram of WHICH autocmd
# groups + events + extmark namespaces grew.
#
# Env knobs:
#   N           number of fixture files (default 30)
#   LANG_KIND   txt | lua | py (default lua)
#   USE_GIT     1 to init a git repo with mixed states (default 1)

set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE="$SCRIPT_DIR/probe.lua"
N="${N:-30}"
LANG_KIND="${LANG_KIND:-lua}"
USE_GIT="${USE_GIT:-1}"
# Same NVIM_APPNAME safety as bench-ux.sh: never silently load ~/.config/nvim
# when the user expects their named config.
if [ -z "${NVIM_APPNAME:-}" ]; then NVIM_APPNAME="BeastVim"; fi
export NVIM_APPNAME

WORK="${TMPDIR:-/tmp}/diag-bufswitch.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# generate fixtures
python3 - "$WORK/bufs" "$N" "$LANG_KIND" <<'PY'
import sys, os
d, n, lang = sys.argv[1], int(sys.argv[2]), sys.argv[3]
os.makedirs(d, exist_ok=True)
ext = {"lua": "lua", "py": "py"}.get(lang, "txt")
for i in range(n):
    p = f"{d}/mod_{i:03d}.{ext}"
    with open(p, "w") as f:
        if lang == "lua":
            f.write(f"local M = {{}}\nfunction M.f() return {i} end\n")
            for j in range(40): f.write(f"function M.h_{j}(x) return x + {j} end\n")
            f.write("return M\n")
        elif lang == "py":
            f.write(f'"""m{i}."""\n')
            for j in range(40): f.write(f"def h_{j}(x: int) -> int:\n    return x + {j}\n\n")
        else:
            for j in range(100): f.write(f"l{j}\n")
PY

if [ "$USE_GIT" = "1" ]; then
  (
    cd "$WORK/bufs"
    git init -q -b main
    git config user.email bench@local
    git config user.name bench
    git add -A
    git commit -q -m init
  )
  python3 - "$WORK/bufs" <<'PY'
import os, sys, glob, subprocess
d = sys.argv[1]; os.chdir(d)
files = sorted(f for f in glob.glob("*") if os.path.isfile(f))
ext = files[0].rsplit(".", 1)[-1]
# modify ~1/3
for p in files[::3]:
    with open(p, "a") as f: f.write("\n-- modified for bench\n-- second line\n")
# stage ~1/8 (with their own change)
staged = files[1::8]
for p in staged:
    with open(p, "a") as f: f.write("\n-- staged change\n")
subprocess.run(["git", "add", "--"] + staged, check=True)
for p in staged[:len(staged)//2 or 1]:
    with open(p, "a") as f: f.write("-- extra unstaged after stage\n")
# delete ~1/12
for p in files[::12]:
    if os.path.isfile(p) and p not in files[::3] and p not in staged:
        os.remove(p)
# add ~1/8 untracked
for i in range(max(1, len(files)//8)):
    with open(f"untracked_{i:03d}.{ext}", "w") as f:
        f.write(f"-- new {i}\n")
s = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
print(f"git status: {len(s.splitlines())} entries", file=sys.stderr)
PY
fi

LOG="$WORK/diag.log"

cat >"$WORK/diag.lua" <<LUA
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
vim.o.swapfile = false

local LOG = "$LOG"
local log = assert(io.open(LOG, "a"))
local function w(s) log:write(s); log:flush() end

local function snap(label)
  collectgarbage("collect")
  local acs = vim.api.nvim_get_autocmds({})
  local by_event, by_group = {}, {}
  for _, a in ipairs(acs) do
    by_event[a.event] = (by_event[a.event] or 0) + 1
    local g = a.group_name or "<no-group>"
    by_group[g] = (by_group[g] or 0) + 1
  end

  local ns_marks, total_marks = {}, 0
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    local sum = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local ok, m = pcall(vim.api.nvim_buf_get_extmarks, buf, id, 0, -1, {})
        if ok then sum = sum + #m end
      end
    end
    if sum > 0 then ns_marks[name] = sum end
    total_marks = total_marks + sum
  end

  local stats = vim.api.nvim__stats() or {}
  w(string.format("\n==== %s ====\n", label))
  w(string.format("total_autocmds=%d bufs=%d lua_refcount=%d total_extmarks=%d\n",
    #acs, #vim.api.nvim_list_bufs(), stats.lua_refcount or 0, total_marks))

  local function topn(t, n)
    local arr = {}
    for k, v in pairs(t) do arr[#arr+1] = { k = k, v = v } end
    table.sort(arr, function(a, b) return a.v > b.v end)
    for i = 1, math.min(n, #arr) do w(string.format("  %5d  %s\n", arr[i].v, arr[i].k)) end
  end
  w("by_event:\n");     topn(by_event, 15)
  w("by_group:\n");     topn(by_group, 20)
  w("by_namespace:\n"); topn(ns_marks, 20)
end

vim.defer_fn(function()
  snap("after_init")

  local files = vim.tbl_filter(function(f) return not f:match("/%.") end,
    vim.fn.glob("$WORK/bufs/*", false, true))
  table.sort(files)
  for _, f in ipairs(files) do vim.cmd("badd " .. vim.fn.fnameescape(f)) end
  vim.cmd("buffer " .. vim.fn.fnameescape(files[1]))

  vim.defer_fn(function()
    snap("after_first_buffer")
    local i = 0
    local function step()
      i = i + 1
      if i > #files * 2 then
        vim.defer_fn(function()
          snap("after_cycle")
          log:close()
          vim.cmd("qa!")
        end, 1500)
        return
      end
      vim.cmd("buffer " .. vim.fn.fnameescape(files[((i - 1) % #files) + 1]))
      vim.defer_fn(step, 90)
    end
    step()
  end, 3000)
end, 200)
LUA

if [ -n "${NVIM_APPNAME:-}" ]; then
  PANE=$(wezterm cli spawn --cwd "$WORK/bufs" -- \
    env BENCH_LOG="$LOG" NVIM_APPNAME="$NVIM_APPNAME" nvim -u "$WORK/diag.lua")
else
  PANE=$(wezterm cli spawn --cwd "$WORK/bufs" -- \
    env BENCH_LOG="$LOG" nvim -u "$WORK/diag.lua")
fi
echo "spawned pane=$PANE (N=$N lang=$LANG_KIND git=$USE_GIT NVIM_APPNAME=${NVIM_APPNAME:-<unset>}); waiting..."
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if grep -q "after_cycle" "$LOG" 2>/dev/null; then sleep 2; break; fi
  sleep 1
done

echo
echo "============================ DIAG REPORT ============================"
cat "$LOG"
echo "====================================================================="
