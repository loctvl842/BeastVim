# BeastVim UX Bottleneck Report

<!-- Generated: 2026-06-03 via scripts/bench-ux.sh (key-to-paint latency) -->

Methodology: `scripts/bench-ux.sh` measures key-to-paint latency in a real
wezterm pane using `vim.on_key` + a decoration-provider `on_end` hook
(see `scripts/bench-ux/probe.lua`). Diagnostic of per-buffer growth was
captured with `scripts/bench-ux/diag-bufswitch-wezterm.sh`.

All comparisons: 60 iterations, KEY_DELAY=0.08 s, Apple Silicon.

## Headline numbers

| Scenario | Bare nvim p50/p99/max | BeastVim + lua | BeastVim + lua + git |
|---|---|---|---|
| keypress | 0.57 / 0.84 / 0.84 ms | 0.22 / 1.22 / 2.99 ms | — |
| scroll | 0.69 / 0.86 / 0.89 ms | 9.87 / 18.78 / 106.61 ms | (similar to lua) |
| bufswitch | 3.78 / 4.89 / 15.39 ms | 16.18 / 32.50 / 34.49 ms | 16.84 / 43.76 / 43.76 ms |
| extmarks (10k) | 0.47 / 0.54 / 0.54 ms | 0.24 / 2.47 / 3.43 ms | — |

`extmarks` and `keypress` are clean. `scroll` and `bufswitch` regressed
significantly. Adding a git repo with mixed states (16 dirty entries over
30 files) costs an additional **~11 ms at p99** for bufswitch — small
compared to the navic/semantic-tokens overhead, but not free.

## Per-buffer leak (the smoking gun)

Cycling 20 Lua buffers twice (40 entries) in a git repo with mixed states:

| Indicator | Start | End | Delta | Per buffer |
|---|---|---|---|---|
| Total autocmds | 501 | **877** | +376 | +9 |
| **nvim.lsp.semantic_tokens:1 extmarks** | **248** | **3462** | **+3214** | **+80** |
| gitsigns_signs_ extmarks | 3 | 19 | +16 | +0.4 |
| gitsigns_signs_staged extmarks | 0 | 9 | +9 | +0.2 |
| Lua refcount | 602 | 2212 | +1610 | +40 |
| RSS (KB) | — | — | +89 488 | — |

Autocmd-group growth (top contributors):

| Group | Start | End | Delta |
|---|---|---|---|
| **navic** | **7** | **154** | **+147** |
| **gitsigns** | 16 | 35 | +19 |
| nvim.diagnostic.buf_wipeout | 0 | 22 | +22 |

## Root causes (mapped to research)

### 1. LSP semantic tokens — research §2.2 and §2.7
**~93 % of extmark growth is `nvim.lsp.semantic_tokens:1`** (3214 of
3462). lua_ls emits ~80 tokens per buffer visit; they persist for the
buffer's lifetime. In a 4-hour session opening 500 files this is
**~40 000 extmarks** holding decoration heap allocations. Every redraw
walks the marktree for these (`src/nvim/decoration.c:469-530`), and every
namespace clear is `O(n)` (`src/nvim/extmark.c:198-253`).

### 2. navic / barbecue — research §2.13 and §2.12
**Top autocmd leak by a wide margin.** Registers per-buffer
`CursorMoved`/`CursorMovedI`/`InsertLeave` handlers. After 40 buffer
entries you have 154 navic autocmds. The `apply_autocmds_group()` linear
scan (`src/nvim/autocmd.c: aucmd_next`) walks all of them on every
cursor motion. By 4 h / 500 buffers ≈ 3500 navic handlers fired every
arrow press.

### 3. Treesitter highlighter on scroll — research §2.1 and §2.9
On a real Lua file, scroll p50 jumps to ~10 ms (14× baseline). Each
`<C-d>` brings new lines into view, `on_range_impl` re-runs the highlight
query and writes ephemeral extmarks
(`runtime/lua/vim/treesitter/highlighter.lua:332-493`). Mostly unavoidable,
but caps how fast you can scroll a large file when many plugins also
have `on_line` callbacks (research §2.1 amplification).

### 4. gitsigns (modest, well-behaved)
Adds only **+19 autocmds** and **+25 extmarks** for 40 buffer entries on
a 16-dirty-file repo. Sign growth is bounded by the number of hunks per
file — exactly the design from `lua/beast/libs/git/`. Costs ~11 ms at
p99 for the extra index-vs-HEAD + buffer-vs-index diff per attach.
**Note:** `beast.libs.git` is keymap-lazy in current config (loads only
on `]c`/`[c`), so gitsigns is the actively-running provider for normal
scrolling/switching.

## Fixes — ranked by impact

### Tier 1 (do these now)

1. **Disable LSP semantic tokens** (eliminates the entire extmark leak):
   ```lua
   -- in your default LSP on_attach
   client.server_capabilities.semanticTokensProvider = nil
   ```
   Or selectively kill it for heavyweight servers:
   ```lua
   if client.name == "lua_ls" or client.name == "tsserver" then
     client.server_capabilities.semanticTokensProvider = nil
   end
   ```

2. **Audit navic / barbecue.** Confirm it's still pulling its weight as a
   breadcrumb provider. Options:
   - Disable barbecue and consume `vim.treesitter.get_node()` directly in
     your winbar/statusline (zero per-buffer autocmds).
   - File an upstream issue: register handlers once globally and dispatch
     on `nvim_get_current_buf()` instead of per-buffer.

3. **`vim.diagnostic.config({ update_in_insert = false })`** — research §2.8.

### Tier 2 (defensive)

4. **Big-file gate** (skip heavy attaches above N KB):
   ```lua
   vim.api.nvim_create_autocmd("BufReadPre", {
     group = vim.api.nvim_create_augroup("BeastVim-big-file", { clear = true }),
     callback = function(args)
       local ok, stat = pcall(vim.uv.fs_stat, args.file)
       if ok and stat and stat.size > 256 * 1024 then
         vim.b[args.buf].is_big_file = true
         vim.bo[args.buf].syntax = ""
         vim.cmd("TSBufDisable highlight")
       end
     end,
   })
   ```

5. **Periodic growth check** — wire `vim.api.nvim__stats().lua_refcount`
   and `#vim.api.nvim_get_autocmds({})` into your debug palette so you
   can spot drift during normal use.

## Re-test recipe

Bare baseline:
```sh
./scripts/bench-ux.sh all
```

Full BeastVim stack (real Lua fixtures in a git repo):
```sh
LOAD_USER_CONFIG=1 NVIM_APPNAME=BeastVim \
  FIXTURE_LANG=lua FIXTURE_GIT=1 ./scripts/bench-ux.sh all
```
The bench defaults `NVIM_APPNAME=BeastVim` when `LOAD_USER_CONFIG=1` is
set without an explicit appname, so it never silently falls through to
`~/.config/nvim`. Override with e.g. `NVIM_APPNAME=nvim` to bench the
default-named config dir instead.

Per-buffer leak histogram (which group / namespace is growing):
```sh
N=20 LANG_KIND=lua USE_GIT=1 NVIM_APPNAME=BeastVim \
  ./scripts/bench-ux/diag-bufswitch-wezterm.sh
```

After applying fixes, re-run and compare `bufswitch` p50 (should drop
below 10 ms) and the diag output's `nvim.lsp.semantic_tokens:1` row
(should approach zero) and `navic` row (should stay flat at 7).

Long-session leak verification:
```sh
LOAD_USER_CONFIG=1 FIXTURE_GIT=1 LONG_MINUTES=30 \
  ./scripts/bench-ux.sh longsession
```
The CSV output shows whether `extmarks` and `lua_refcount` grow linearly
with uptime.
