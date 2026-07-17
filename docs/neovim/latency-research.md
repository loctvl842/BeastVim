# Neovim Long-Session Latency — Research Report

<!-- Generated: 2026-06-03 from /Users/loctvl842/Documents/GitDepot/neovim -->

Research conducted against `/Users/loctvl842/Documents/GitDepot/neovim`. All citations are `path:line` into that tree.

**Goal:** Understand which Neovim internals can cause interactive latency to gradually increase during long editing sessions (hours of use, many buffers, many plugin interactions), and identify configuration and plugin patterns that avoid these costs.

---

## 1. Event Loop (executive summary)

```
                  ┌────────────────────────── MAIN THREAD ────────────────────────────┐
   tty/UI ──► input_read_cb() ──► input_buffer ──► input_get() ──► vgetc()            │
                                                       │                              │
                                                       ▼                              │
                                                 state_enter() ──► mode handlers      │
                                                       │                              │
                                                       ▼                              │
                                              must_redraw? → update_screen()          │
                                                       │                              │
                                                       ▼                              │
                                                   ui_flush()                         │
                                                                                      │
   libuv loop (main_loop.uv) ──┬─ fast_events (signal-safe / thread handoff)          │
                               ├─ events       (vim.schedule, RPC dispatch, timers)   │
                               └─ thread_events                                       │
                                                                                      │
   per-channel: channel->events,  per-proc: proc->events  (drained on main thread)    │
   msgpack parse + handler dispatch:  receive_msgpack() / parse_msgpack()  ← MAIN     │
                                                                                      │
   BACKGROUND THREADS: only libuv worker pool (DNS, fs ops), luv user threads,        │
                       process I/O readers. **No RPC parser thread.**                 │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

Key sources: `src/nvim/main.c:143-167`, `src/nvim/event/loop.c:15-83`, `src/nvim/state.c:49-105`, `src/nvim/os/input.c:97-545`, `src/nvim/msgpack_rpc/channel.c:140-348`, `src/nvim/lua/executor.c:340-573`.

**Implication for long sessions:** every Lua callback, autocmd, msgpack parse, redraw and RPC handler runs on the single main thread. There is no parallelism to absorb growing per-event work.

---

## 2. Top 20 Causes of Long-Session Latency (Ranked)

Ranked roughly by `frequency × per-event cost × growth-with-session-time`.

### Tier S — Almost always involved when sessions get slow

**1. Per-line decoration-provider callbacks (Treesitter + LSP semantic tokens)**
`on_line` fires *per visible row × per provider × per redraw* (`src/nvim/decoration_provider.c:170-196`). With Treesitter highlight + semantic tokens + diagnostics + inlay hints + custom plugins, amplification reaches `O(providers × rows × windows)` per keystroke. Treesitter's `on_range_impl` re-runs query cursors and sets ephemeral extmarks per visible capture (`runtime/lua/vim/treesitter/highlighter.lua:332-493`).

**2. Extmark growth in long-lived namespaces (semantic tokens, inlay hints, diagnostics)**
LSP semantic tokens emit roughly one extmark per token (`runtime/lua/vim/lsp/semantic_tokens.lua:597-725`); inlay hints emit one inline extmark per hint (`runtime/lua/vim/lsp/inlay_hint.lua:307-365`); diagnostics emit signs + virt_text extmarks (`runtime/lua/vim/lsp/_handlers.lua:186-388`). Storage is `O(log n)` per op (`src/nvim/marktree.c:486-773`) but `clear_namespace()` is `O(n)` over the range (`src/nvim/extmark.c:198-253`), so frequent namespace rebuilds become quadratic in practice.

**3. Custom `'statuscolumn'` evaluating Lua per visible row**
`draw_statuscol()` runs *every visible row of every window* on each redraw, and changing computed width can trigger an additional redraw (`src/nvim/drawline.c:689-760`). A Lua `%{}` callback here is the single most expensive per-row cost in the redraw pipeline.

**4. Synchronous RPC requests from the main thread**
`rpc_send_call()` enters `LOOP_PROCESS_EVENTS_UNTIL(... channel->events ...)` and blocks the editor entirely until the reply arrives (`src/nvim/msgpack_rpc/channel.c:140-201`). Any plugin using `nvim_call` / `jobwait` / `system()` from a hot path freezes input.

**5. Heavy work in `CursorMoved` / `CursorMovedI`**
Fired on *every* cursor-position change (`src/nvim/normal.c: normal_check_cursor_moved`, `src/nvim/edit.c: insert_handle_key_post`). Combined with `apply_autocmds_group()`'s linear scan over the event's `AutoCmdVec` (`src/nvim/autocmd.c: aucmd_next`), a long-running session that has accumulated dozens of `CursorMoved` autocmds pays them on every arrow press.

### Tier A — Common growing costs

**6. Unbounded `main_loop.events` / `channel->events` queues**
`event/multiqueue.c:153-250` will accept unbounded enqueues. If producers (notifications, decoration callbacks, vim.schedule) outpace the drain (because each scheduled item itself does work), the queue lengthens and latency to drain a keypress's worth of work grows over time.

**7. LSP semantic tokens delta processing**
Full/delta processing is `O(tokens)` and then redraw amplifies (`runtime/lua/vim/lsp/semantic_tokens.lua:285-727`). Each chatty file save triggers a delta request; without clearing, extmarks pile up.

**8. LSP diagnostics in insert mode (`update_in_insert=true`)**
Every `didChange` produces a publishDiagnostics that rebuilds sign + virt_text + underline extmarks (`runtime/lua/vim/diagnostic/_handlers.lua:186-388`, gated by `runtime/lua/vim/diagnostic.lua:99-103`). Default `false` is wise; flipping to `true` is the single most impactful "responsiveness" footgun.

**9. Treesitter parse on every `on_bytes`, on main thread**
Parsing is incremental but synchronous and main-thread only (`runtime/lua/vim/treesitter/languagetree.lua:558-613`). The 3 ms cooperative timeout (`languagetree.lua:48-50`) chunks work but each keystroke still pays for one slice plus the `_on_bytes` walk through the tree (`languagetree.lua:1269-1327`).

**10. Treesitter injections (nested LanguageTrees)**
Each injected grammar (markdown→code, vimdoc→lua, html→js→css) is a child `LanguageTree` parsed recursively in `_parse()` (`languagetree.lua:705-707`). Cost multiplies with nesting depth; injections in long-edited files re-evaluate as edits cross injection regions.

**11. Buffer-list scans (`FOR_ALL_BUFFERS`)**
Hidden buffers themselves are cheap, but commands and autocmds that scan all buffers (`autowrite_all` `ex_cmds2.c:127-145`, confirm-on-quit `ex_cmds2.c:149-258`, swap-check `memline.c:471-477`, all-buffer autocmd loop `autocmd.c:1188-1205`) become noticeable at hundreds of buffers and painful at thousands. `:bufdo`, `:wall`, and `:qa` scale linearly here.

**12. Lua registry / `lua_refcount` growth**
Every Lua callback registered with `nvim_create_autocmd`, `nvim_buf_attach`, `nvim_set_keymap`, `vim.api.nvim_create_user_command` increments a Lua ref. Leaked refs (e.g. plugins that re-register on `BufEnter` without dedup) accumulate forever — visible in `vim.api.nvim__stats().lua_refcount` (`src/nvim/api/vim.c:1880-1892`).

**13. Linear autocmd-pattern matching**
`apply_autocmds_group()` walks the entire `AutoCmdVec` for the event and runs `match_file_pat()` per entry (`src/nvim/autocmd.c: aucmd_next`). A session with many plugins, many filetypes, and a lot of `FileType *` / `BufEnter *` handlers pays `O(n_handlers)` per event fire — every keystroke if the handlers are on `CursorMovedI`.

**14. Decoration invalidation on every extmark write**
`decor_redraw()` (`src/nvim/decoration.c:92-117`) marks visible regions dirty whenever an extmark with decoration is set. Plugins that constantly set/clear marks (cursor highlight followers, indent guides on every move) cause redraw storms.

**15. Inlay hints re-rendered as inline virtual text**
One extmark per hint with `virt_text_pos='inline'` (`runtime/lua/vim/lsp/inlay_hint.lua:307-365`). Inline virt_text triggers per-cell layout work in `win_line()` (`src/nvim/drawline.c:374-440, 1615-1630`) — far more expensive than `eol` virt_text.

### Tier B — Configuration footguns

**16. Floating-window compositor cost**
`ui_compositor.c:134-213` re-composes overlap regions on every move/resize; many floats (popups, ghost text, signature help, copilot suggestion windows) plus a moving cursor produces continual `compose_area()` work and a second `ui_flush()` per frame (`src/nvim/ui.c:567-575`).

**17. Spell + conceal + cursorline**
`spell` runs `spell_move_to()`/`spell_check()` per visible line (`src/nvim/drawline.c:1374-1612`); `conceal` branches in `win_line()` (`drawline.c:1454-1659`); `cursorline` adds highlight passes (`drawline.c:1134-1143, 1332-1344`). Each individually small, but stacked they roughly double the per-line redraw cost.

**18. `os_breakcheck` polling inside tight loops**
`os_breakcheck()` runs a full libuv poll (`src/nvim/os/input.c:203-210`). Plugin Vimscript or Lua loops that call `getchar(0)`/`peek` or perform many short operations effectively pump the event loop every iteration, draining queued work in the wrong spot and starving redraws.

**19. `typebuf` / mapping churn**
Long sessions with many mappings (LSP attach adds dozens of buffer-local maps × N buffers) pay `getchar.c:128-149, 1070-1164` cost on every key. Mostly constant, but grows with `nvim_buf_set_keymap` leakage.

**20. CodeLens / autocmd-driven refreshes**
`vim.lsp.codelens` auto-refresh debounced at 200 ms on edits and reload (`runtime/lua/vim/lsp/codelens.lua:48-63, 181-189`), per-client namespace. With multiple clients (e.g. typescript + eslint + tailwind on one buffer) the multiplier hits redraw + RPC + extmark paths simultaneously.

---

## 3. Cost Model — Redraw

```
T_redraw ≈ Σ_windows [
    W_setup
  + Σ_visible_lines (
        line_text                                     // O(line_width)
      + statuscolumn_eval                             // Lua %{} dominant
      + signcolumn + foldcolumn + linenr
      + spell + conceal + cursorline
      + Σ_extmarks_on_line (decoration layout)        // inline virt_text expensive
      + Σ_providers (on_line callback)                // TS + LSP + plugins
    )
  + grid_diff
] + compositor (floats) + ui_flush
```

**Scales with:** visible_lines, providers, extmarks_in_view, windows, floats.
**Does NOT scale (directly) with:** total buffer size, total extmarks in buffer (marktree is `O(log n)`), hidden-buffer count.

### Redraw invalidation levels

`UPD_VALID` < `UPD_INVERTED` < `UPD_INVERTED_ALL` < `UPD_REDRAW_TOP` < `UPD_SOME_VALID` < `UPD_NOT_VALID` < `UPD_CLEAR` (`src/nvim/drawscreen.h:11-18`). Plugins forcing `UPD_NOT_VALID`/`UPD_CLEAR` via colorscheme reload, `:redraw!`, or option changes are expensive.

### Per-line cost ranking (high → low)

1. `statuscolumn` Lua %{}
2. `spell`
3. `conceal`
4. `inline` virtual text
5. `cursorline` / `cursorlineopt`
6. `signcolumn` / `relativenumber`
7. `foldcolumn`
8. plain syntax highlighting

---

## 4. Extmark Complexity Reference

The marktree is a B-tree with `MT_BRANCH_FACTOR = 10` (max 19 keys / 20 children per node, max depth 20). Positions stored relative to ancestors. See `src/nvim/marktree_defs.h:10-93`, `src/nvim/marktree.c:81-110`.

| Op | Complexity | Source |
|---|---|---|
| insert | `O(log n)` | `marktree.c:486-513` (`marktree_put_key`) |
| delete by id | `O(log n)` | `marktree.c:539-773` (`marktree_del_itr`) |
| point lookup | `O(log n)` avg | `marktree.c:2148-2210` (`marktree_lookup_ns`) |
| range query | `O(log n + k)` | `extmark.c:261-299` |
| clear namespace | **O(n) scan** | `extmark.c:198-253` ← frequent rebuild ≈ quadratic |
| splice on edit | `O(t log n)`, t=touched | `marktree.c:1913-2107` |
| redraw line lookup | amortized `O(log n + a)` | `decoration.c:469-530` |

**Memory per extmark (64-bit):**
- base `MTKey`: ~32 B (`marktree_defs.h:62-68`, `decoration_defs.h:123-135`)
- `hl_group` only: still ~32 B (decoration inline)
- `virt_text` / `virt_lines` / sign_text / URL: +32–56 B per heap node + chunk strings (`decoration_defs.h:71-115`, `decoration.c:253-315`)

**Practical limits:** 10k fine • 100k workable but clears hurt • 1M expensive.

**Lifetime:** extmarks freed via `extmark_free_all()` on buffer unload/wipe (`extmark.c:334-360`). They survive `:bunload`/`:bdelete` boundary only if buffer survives.

---

## 5. Buffer State Cost Matrix

| State | text (memline) | syntax | extmarks | LSP/TS attach | buf-local autocmds | buf-local opts |
|---|---|---|---|---|---|---|
| listed + loaded | kept | kept | kept | attached | kept | kept |
| listed + unloaded | **freed** | **cleared** | **kept** | survives (not auto-detached) | kept | kept |
| hidden (loaded, no window) | kept | kept | kept | kept | kept | kept |
| wiped | freed | cleared | freed | gone | freed | freed |

Sources: `buffer.c:555-1009`, `memline.c:568-585`, `buffer.c:2141-2205`.

- `:bunload` → unload, keep in list (`BufUnload` fires)
- `:bdelete` → unload + remove from list (`BufDelete`)
- `:bwipeout` → unload + remove + destroy (`BufWipeout`)
- `bufhidden=hide` → window closes, buffer fully loaded

**Verdict:** thousands of hidden buffers are fine *if* you avoid global scans (`:bufdo`, `:wall`, all-buffer autocmds).

---

## 6. Treesitter Lifecycle

```
edit ─► LanguageTree:_on_bytes()           (languagetree.lua:1269-1327)
        │  edits TS trees + fires on_bytes
        ▼
        highlighter clears conceal marks   (highlighter.lua:114-123)
        ▼
redraw ─► decoration provider on_start / on_win / on_line / on_range
        │                              (decoration_provider.c:112-247)
        ▼
        TSHighlighter._on_win()             (highlighter.lua:551-567)
        ▼
        on_range_impl() runs queries + sets EPHEMERAL extmarks
                                            (highlighter.lua:332-493, 458-463)
```

- **Parsing:** incremental, native tree-sitter `ts_parser_parse*` with `old_tree` (`src/nvim/lua/treesitter.c:509-568`).
- **Threading:** **none.** Async = coroutine + `vim.schedule`, still on main thread. Parse timeout: 3 ms cooperative slice (`languagetree.lua:48-50, 597-609`).
- **Extmarks:** ephemeral (lifetime = one redraw), so no persistent growth. This is the model plugins should imitate.
- **Injections:** child `LanguageTree`s parsed recursively (`languagetree.lua:705-707`). Cost multiplies with nesting.
- **No core size guards** — `max_filesize` is the *nvim-treesitter plugin's* job, not core.

---

## 7. LSP Cost Ranking (Neovim-side, not server)

1. **Semantic tokens** — `O(tokens)` processing + extmark-per-token (`semantic_tokens.lua:285-727`).
2. **Diagnostics display** — sign + virt_text + underline extmarks per diagnostic (`_handlers.lua:186-388`). `update_in_insert=false` is critical.
3. **Inlay hints** — one inline extmark per hint (`inlay_hint.lua:307-365`); inline virt_text is expensive in `win_line`.
4. **Code lenses** — 200 ms debounced per client (`codelens.lua:48-63, 181-189`).
5. **didChange / incremental sync** — `sync.compute_diff` in Lua per edit (`_changetracking.lua:86-128`); debounce honored.
6. **Completion** — request-driven, async, `vim.schedule_wrap` handlers. Not usually a hot-path blocker.
7. **Multiple clients per buffer** — multiplies all of the above (per-client namespaces).

RPC dispatch is `vim.schedule_wrap`'d (`rpc.lua:413-517`), so server replies don't block transport. They block when handlers do.

---

## 8. Autocmd Overhead Quick Reference

| Event | Trigger frequency | Blocking risk |
|---|---|---|
| CursorMoved | every position change | **high** |
| CursorMovedI | every insert-mode position change | **very high** |
| CursorHold | after `'updatetime'` idle | high if handler blocks |
| BufEnter | every buffer switch | medium-high |
| WinEnter | every window switch | medium-high |
| TextChanged(I) | every modification (gated by changedtick) | high |
| ModeChanged | mode transitions only | low-medium |

Pattern matching: `apply_autocmds_group()` linearly scans the event's `AutoCmdVec` and runs `match_file_pat()` per entry — **no per-event hash cache** (`src/nvim/autocmd.c: aucmd_next`).

Lua callback overhead: `nlua_call_ref_ctx()` marshals args through the Lua C API on every fire (`src/nvim/lua/executor.c`).

---

## 9. Rules of Thumb

**For plugin authors:**

- **Never** do RPC / IO / Lua-heavy work in `CursorMoved` / `CursorMovedI`. Debounce 100–300 ms.
- Prefer `nvim_buf_attach(on_lines)` over `TextChangedI`; cheaper and gives byte-level info.
- Use `on_win`-scoped *ephemeral* extmarks for highlights (like Treesitter does) instead of persistent ones.
- Scope extmark queries to the visible window range, not `(0, -1)`.
- Batch `nvim_buf_clear_namespace` calls; avoid per-event `clear+rebuild` cycles.
- Keep `'statuscolumn'` purely string-formatting; never call Lua functions that allocate.
- Prefer `eol` virt_text over `inline` when possible.
- Dedup autocmd registration — use `vim.api.nvim_create_augroup({ clear = true })`.
- Detach LSP/TS resources in `BufWipeout`, not just `BufDelete`.

**For config writers:**

- `vim.diagnostic.config({ update_in_insert = false })`.
- Disable LSP semantic tokens + inlay hints on huge files.
- Disable Treesitter highlight + folds on huge files (core has *no* size guard).
- Use `:bdelete` / `:bwipeout` for scratch / preview buffers; don't leave thousands hidden.
- Audit autocmd count periodically — a plugin re-registering on `BufEnter` is a common leak.

---

## 10. Diagnostic Workflow — "Why is Neovim slow after 4 hours?"

1. **Measure event-loop pressure:** sample `vim.uv.metrics_idle_time()` over 10–30 s (lower idle ratio ⇒ main thread saturated). Requires `vim.uv.loop_configure('metrics_idle_time')` enabled.
2. **Snapshot internal counters:** `vim.api.nvim__stats()` — note `redraw`, `lua_refcount`, `ts_query_parse_count`, `arena_alloc_count` deltas (`src/nvim/api/vim.c:1880-1892`).
3. **Snapshot growth:** `#vim.api.nvim_list_bufs()`, `#vim.api.nvim_get_autocmds({})`, and `#vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {})` per namespace.
4. **Check buffer health:** `vim.api.nvim__buf_stats(0)` — `flush_count`, `uhp_extmark_size`, `dirty_bytes` (`src/nvim/api/buffer.c:1235-1268`).
5. **Bisect plugins:** reproduce under `nvim --clean`, then `nvim --noplugin`, then add plugin groups back.
6. **Trace redraw churn:** `:set redrawdebug=compositor,nodelta,flush writedelay=20` (`runtime/doc/options.txt:4993-5025`).
7. **Vimscript hot paths:** `:profile start prof.log | :profile func * | :profile file *` (`src/nvim/profile.c:287-588`). Vimscript only — does *not* cover Lua.
8. **Lua hot paths:** `require('jit.p').start('vl', '/tmp/jit.txt')` (LuaJIT only).
9. **RPC tracing:** `NVIM_LOG_FILE=/tmp/nvim.log nvim …` (`src/nvim/log.c:59-108`).

### Snippet — quick growth check

```lua
:lua = {
  bufs       = #vim.api.nvim_list_bufs(),
  autocmds   = #vim.api.nvim_get_autocmds({}),
  stats      = vim.api.nvim__stats(),
  buf_stats  = vim.api.nvim__buf_stats(0),
  extmarks   = #vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}),
}
```

Run at session start and again after 4 hours. Anything growing unbounded is a leak.

---

## Source Map (quick index)

| Subsystem | Primary files |
|---|---|
| Event loop | `src/nvim/main.c`, `src/nvim/event/loop.c`, `src/nvim/event/multiqueue.c`, `src/nvim/state.c`, `src/nvim/os/input.c` |
| RPC | `src/nvim/msgpack_rpc/channel.c`, `src/nvim/channel.c` |
| Lua bridge | `src/nvim/lua/executor.c`, `src/nvim/lua/treesitter.c` |
| Redraw | `src/nvim/drawscreen.c`, `src/nvim/drawline.c`, `src/nvim/grid.c`, `src/nvim/ui.c`, `src/nvim/ui_compositor.c` |
| Decorations | `src/nvim/decoration.c`, `src/nvim/decoration_provider.c`, `src/nvim/extmark.c`, `src/nvim/marktree.c` |
| Autocmds | `src/nvim/autocmd.c`, `src/nvim/normal.c`, `src/nvim/edit.c` |
| Buffers | `src/nvim/buffer.c`, `src/nvim/memline.c`, `src/nvim/memfile.c`, `src/nvim/ex_cmds2.c` |
| Treesitter (Lua) | `runtime/lua/vim/treesitter.lua`, `runtime/lua/vim/treesitter/highlighter.lua`, `runtime/lua/vim/treesitter/languagetree.lua`, `runtime/lua/vim/treesitter/query.lua` |
| LSP (Lua) | `runtime/lua/vim/lsp.lua`, `runtime/lua/vim/lsp/semantic_tokens.lua`, `runtime/lua/vim/lsp/inlay_hint.lua`, `runtime/lua/vim/lsp/codelens.lua`, `runtime/lua/vim/lsp/_changetracking.lua`, `runtime/lua/vim/lsp/rpc.lua` |
| Diagnostics (Lua) | `runtime/lua/vim/diagnostic.lua`, `runtime/lua/vim/diagnostic/_handlers.lua`, `runtime/lua/vim/diagnostic/_display.lua`, `runtime/lua/vim/diagnostic/_store.lua` |
| Profiling | `src/nvim/profile.c`, `src/nvim/log.c`, `src/nvim/api/vim.c` (nvim__stats), `src/nvim/api/buffer.c` (nvim__buf_stats) |
