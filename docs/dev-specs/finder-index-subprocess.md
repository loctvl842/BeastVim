# Dev Spec: Finder Index Subprocess — Off-Main-Thread Build via Binary File Handoff

## Summary

Move the bigram content-index build out of the Neovim main loop entirely. Today
`engine/index.lua` scans the whole repo in time-budgeted `uv` timer ticks — even
at 3 ms slices it competes with the editor for ~167 s on a 90k-file / 2.1 GB repo.
Instead, spawn a **separate headless `nvim` process** that builds the bigram
matrix in a tight blocking loop, serializes it to a **custom binary file** (a near
memory-dump: header + `col_for` pairs + raw `uint32` matrix + NUL-separated
paths), and exits. The main process `uv.spawn`s the builder, and on exit loads the
file with a single `ffi.copy` (a ~56 MB memcpy, milliseconds), installs it as the
current index, and starts the existing `fs_event` watcher. The file is a
**per-session IPC handoff** — rebuilt every launch, never reused across sessions —
so the no-false-negative guarantee (index reflects current content; `rg` verifies)
holds without stale-cache revalidation.

## Requirements

- Index build runs in a separate OS process; the main loop is never blocked by it
  (no per-tick time budget on the main thread).
- Builder reuses the **same** `bigram.lua` / `extract.lua` modules → byte-identical
  bigram semantics vs the current in-process build (no divergence).
- Binary file format is a near-verbatim dump of the in-memory layout: fixed header,
  `col_for` as `uint16` key/col pairs, raw `uint32` matrix (`ffi.copy`), NUL-separated
  absolute paths. No JSON / MessagePack / SQLite.
- Header carries a fingerprint (magic + version + root-path hash) so the reader
  rejects a mismatched / wrong-version / wrong-root file instead of loading garbage.
- File is written atomically (temp + rename) so a partial write is never read.
- On builder failure / missing FFI / timeout, `live_grep` falls back to full `rg`
  scan — exactly today's behavior; the feature is best-effort.
- Existing `fs_event` freshness overlay, tombstones, `query`, and `stop` keep working
  unchanged on the loaded index.
- Engine stays opt-in (`config.engine.enabled`); off = current behavior.
- **Out of scope**: cross-session persistent cache / mtime revalidation (user chose
  IPC-handoff only); `mmap` of the matrix (format leaves room for it later but we
  read-then-copy for now); libuv-thread builder (we use a real subprocess); trigram
  index / selectivity work; compression; Windows (subprocess uses POSIX `nvim`, but
  the format itself is portable).

## Research

### Repo Search
- Searched for: `git grep -niE 'uv.spawn|vim.system|stdpath\("cache"\)|ffi.copy|systemlist|new_thread'`
  plus reads of `engine/index.lua`, `engine/bigram.lua`, `engine/extract.lua`,
  `source/live_grep.lua`, `config.lua`, `scripts/bench-grep.lua`, `util/init.lua`.
- Found:
  - `engine/index.lua` — current time-budget tick build (`BUILD_BUDGET_MS=3`,
    `uv.new_timer`), `scan_file`, `refresh`, `watch`, `query`, `stop`; `list_files`
    via `rg --files`. This is what we replace/rewire.
  - `engine/bigram.lua` — public fields `words/max_cols/ncols/nfiles/col_for/matrix`
    and the FFI matrix `uint32_t[max_cols*words]`. `M.new(max_files, max_cols)` is the
    only constructor. Needs a sibling `M.load(...)` that reconstructs from raw bytes.
  - `source/live_grep.lua` — `uv.spawn`ing `rg` per batch (direct-child pattern we
    mirror for the builder); already tracks `building` per cwd so build kicks off once.
  - `util/init.lua:17` — `debug.getinfo(1,"S").source` → resolve the `lua/` root. Same
    trick lets `index.lua` compute `BEAST_FINDER_LUA_ROOT` to pass to the `--clean`
    subprocess (which has no runtimepath).
  - `scripts/bench-grep.lua` — the exact "walk `rg --files` → read → `bigram:add`" loop
    the builder script needs; the builder is essentially this loop + serialize + exit code.
  - No existing binary serializer, subprocess builder, or cache-path helper.
- Reuse opportunity: **Adopt** the `rg --files` walk + `scan_file` read loop and the
  `uv.spawn` direct-child pattern; **Extract** serialization into a new shared
  `engine/serialize.lua` (needed by both writer and reader); **Build** the subprocess
  entry script.

### Package Search
- Searched: native `vim.uv` (`spawn`, `fs_open/read/write`, `fs_rename`), LuaJIT `ffi`
  (`copy`, `cast`, `string`), `bit`; `nvim --headless --clean -l <script>` as the builder.
- Found: `uv.spawn` runs a child with an exit callback on the main loop; a headless
  `nvim --clean -l` provides `vim.uv`, `require("ffi")`, `require("bit")` and populates
  `_G.arg` — **verified by probe** (ffi=true, bit=true, engine `require` OK with a
  custom `package.path`, FFI round-trip OK). `ffi.copy(dst, ffi.cast("const char*", str), n)`
  copies a Lua string's bytes into the matrix with no per-element loop.
- Decision: **Use native** `uv.spawn` + a headless `nvim -l` builder + `ffi.copy`. No
  plugin, no thread library. Same-machine writer/reader → native endianness is safe
  (header still stamps a version + magic to reject foreign files).

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/engine/serialize.lua` | Create | Binary format writer/reader: header + `col_for` pairs + raw matrix + NUL paths; atomic write; fingerprint validate. Shared by builder + main. |
| `lua/beast/libs/finder/engine/bigram.lua` | Modify | Add `M.load(fields)` (+ internal `alloc(words,max_cols)` shared with `M.new`) to reconstruct a `Bigram` from raw dumped bytes via `ffi.copy`. |
| `lua/beast/libs/finder/engine/builder.lua` | Create | Pure build routine: walk (`rg --files`) → read+`add` (tight loop, no time budget) → `serialize.write`. Reusable + unit-testable, no `arg`/env parsing. |
| `scripts/build-finder-index.lua` | Create | Thin subprocess entry: set `package.path` from env, read env params, call `builder.run`, set exit code. Run via `nvim --headless --clean -l`. |
| `lua/beast/libs/finder/engine/index.lua` | Modify | Replace timer-tick build with `uv.spawn` of the builder + `serialize.read` load on exit; keep `refresh`/`watch`/`query`/`stop`. Add cache-path + lua-root helpers. |
| `tests/test-bigram.lua` | Modify | Add serialize round-trip test: build → `write` temp → `read` → assert query results + `col_for`/matrix identical, and fingerprint-mismatch rejection. |
| `scripts/bench-grep.lua` | Modify (optional) | Time `serialize.write` + `read` round-trip alongside the existing build/query numbers. |

## Implementation Phases

### Phase 1: Binary serialization format — writer + reader round-trip, no integration
1. **`bigram.lua` — `alloc` + `M.load`** (File: `lua/beast/libs/finder/engine/bigram.lua`)
   - Action: Extract the FFI allocation in `M.new` into a private `alloc(words, max_cols)`
     returning a zeroed `Bigram`. Add `M.load({ words, max_cols, ncols, nfiles, col_for,
     matrix_ptr, matrix_words })`: `alloc(words, max_cols)`, `ffi.copy(bg.matrix,
     matrix_ptr, matrix_words*4)`, set `ncols/nfiles/col_for`. Keeps all FFI inside bigram.
   - Why: Reader must rebuild the exact matrix without re-scanning files (no false negatives).
   - Depends on: None. Risk: Medium (FFI copy sizing / column-major offset must match `add`).
2. **`serialize.lua` — write/read** (File: `lua/beast/libs/finder/engine/serialize.lua`)
   - Action: `M.write(index, path)` — pack header (`"BEASTIDX"`, version, words, max_cols,
     ncols, nfiles, matrix_words=`ncols*words`, file_count, root_hash), then `col_for`
     `uint16` key/col pairs, then first `ncols*words` `uint32` of the matrix (`ffi.string`),
     then `path\0…`; write to `path.tmp`, `fs_rename` to `path`. `M.read(path)` — read file,
     validate magic/version/root_hash, parse back into the fields table `M.load` wants
     (`matrix_ptr` = `ffi.cast` into the read buffer) + the file list; return `nil` on any
     mismatch/short read. FNV-1a helper for `root_hash`.
   - Why: The near-memory-dump format the whole feature hinges on; shared by both processes.
   - Depends on: Step 1. Risk: Medium (offset math, endianness note, atomic rename).
3. **Round-trip test** (File: `tests/test-bigram.lua`)
   - Action: Build a small in-memory index, `serialize.write` to a temp path, `serialize.read`,
     `bigram.load`, assert `query(keys)` ids identical for several queries and that a
     tampered magic/root_hash yields `nil`. Clean up temp file.
   - Why: Locks the no-divergence guarantee before anything depends on it.
   - Depends on: Steps 1–2. Risk: Low.

**Phase 1 acceptance**: `nvim --clean --headless -l tests/test-bigram.lua` exits 0
(existing 26 + new round-trip/rejection tests). `stylua --check lua/` clean. No behavior
change in the editor yet — the format exists and is proven; `index.lua` still builds in-process.

### Phase 2: Builder subprocess — produce a valid file from a separate process
1. **`builder.lua` — pure build routine** (File: `lua/beast/libs/finder/engine/builder.lua`)
   - Action: `M.run({ root, out, max_files, max_file_size, max_cols })` — `rg --files` walk
     (adopt `list_files`), `bigram.new`, tight read+`add` loop (no timer/budget — blocking is
     fine off-main-thread), wrap a minimal `Index`-shaped table (`root`, `files`, `bigram`),
     `serialize.write(that, out)`. Return ok/err. No `arg`/env in here (unit-testable).
   - Why: Requirement — build in a separate process, reusing identical bigram semantics.
   - Depends on: Phase 1. Risk: Medium (must match `scan_file` read/size-cap behavior).
2. **`scripts/build-finder-index.lua` — subprocess entry** (File: `scripts/build-finder-index.lua`)
   - Action: `package.path` prepend from `BEAST_FINDER_LUA_ROOT`; read `BEAST_FINDER_{ROOT,
     OUT,MAX_FILES,MAX_FILE_SIZE,MAX_COLS}` env; call `builder.run`; `vim.cmd("qall!")` on
     success / `cquit 1` on failure. Header comment documents the `nvim --headless --clean -l`
     invocation + env contract (mirrors bench-script header convention).
   - Why: The actual off-main-thread executable.
   - Depends on: Step 1. Risk: Low.

**Phase 2 acceptance**: Manually
`BEAST_FINDER_LUA_ROOT=$PWD/lua BEAST_FINDER_ROOT=$PWD BEAST_FINDER_OUT=/tmp/beast.idx
nvim --headless --clean -l scripts/build-finder-index.lua` exits 0 and writes `/tmp/beast.idx`;
a small headless reader (`serialize.read` + `bigram.load` + a query) returns non-empty survivors.
`index.lua` still unchanged (in-process build) — Phase 2 lands without touching editor behavior.

### Phase 3: Rewire index.lua — spawn builder, load on exit, keep freshness
1. **Cache path + lua-root helpers** (File: `lua/beast/libs/finder/engine/index.lua`)
   - Action: `cache_path(root)` = `stdpath("cache").."/beast/finder/"..fnv1a(root)..".idx"`
     (`mkdir -p` the dir); `lua_root()` via `debug.getinfo(1,"S").source` → `:h:h:h:h:h`
     (engine → finder → libs → beast → lua). Risk: Low.
2. **Replace tick build with subprocess spawn + load** (File: `lua/beast/libs/finder/engine/index.lua`)
   - Action: `M.build(root, opts, on_done)` — compute `out=cache_path(root)`, `uv.spawn`
     `nvim` with `--headless --clean -l scripts/build-finder-index.lua`, env carrying root/out/
     lua_root/max_* + `builder script abs path`; in the exit callback: if `code==0`,
     `serialize.read(out)` → on success build the `Index` (files, `id_of`, loaded `bigram`,
     `ready=true`), set `current`, `self:watch()`, `Toast` "index ready", `on_done(self)`; else
     `on_done(nil)`. Remove `scan_file` from the build path (builder owns it) but keep it for
     `refresh`. Delete the timer/tick code.
   - Why: The core requirement — build off the main loop; main only does a fast `ffi.copy` load.
   - Depends on: Phase 2. Risk: High (spawn env/argv correctness, exit-race, load-then-install).
3. **Preserve freshness + fallback** (File: `lua/beast/libs/finder/engine/index.lua`)
   - Action: Keep `refresh`/`watch`/`stop`/`query`/`report` operating on the loaded index. Ensure
     `refresh` capacity check still uses `bigram.words*32`. Guard `Toast` for the not-yet-`setup`
     case if needed. On any load failure, `current` stays nil → `live_grep` full-scan fallback.
   - Why: No regression to freshness overlay or the best-effort contract.
   - Depends on: Step 2. Risk: Medium.

**Phase 3 acceptance**: Open `live_grep` on the repo — editor never stalls during build;
`ps` shows a transient `nvim --headless … build-finder-index.lua` child; after it exits, a
query returns survivors (not a full-tree scan) and results are byte-identical to plain `rg`.
`stylua --check lua/` clean, `tests/test-bigram.lua` exits 0, `scripts/bench-grep.lua` passes.

## Testing Strategy
- Unit tests: extend `tests/test-bigram.lua` — serialize write→read→`load` round-trip yields
  identical `query` ids and `col_for`; fingerprint/magic/version mismatch → `read` returns `nil`;
  empty/short file → `nil`. (Run: `nvim --clean --headless -l tests/test-bigram.lua`, exit 0.)
- Bench: optionally extend `scripts/bench-grep.lua` to print `serialize.write`/`read` ms so the
  handoff cost stays visible (target: load ≪ build; ~ tens of ms for 56 MB memcpy).
- Manual verification: (1) `enable` engine, open `live_grep` on the 90k repo; type immediately —
  no freeze (build is now a child process). (2) Confirm the child via `ps aux | rg build-finder-index`.
  (3) After the "index ready" toast, grep a common token → survivor-scan (fast), results match `rg`.
  (4) Close the finder mid-build, reopen after the toast → the completed build warms the reopen
  (no rebuild); starting a grep in a *different* cwd mid-build supersede-kills the prior child
  (`kill_inflight`), leaving no stale builder racing the new index.

## Risks & Mitigations
- **Spawn/env/argv wrong under `--clean`** (no rtp) → pass `package.path` root + builder script
  path explicitly via env; probe already proved `-l` + custom `package.path` requires the engine.
- **Partial/torn file read** → write to `.tmp` then `fs_rename` (atomic on same fs); reader
  validates magic+version+root_hash+sizes and returns `nil` on any mismatch → full-scan fallback.
- **Endianness / ABI** → same-machine writer/reader (native), magic+version stamp rejects foreign
  files; documented as a same-host format (portable-by-rebuild since it's per-session).
- **Edits during the build/handoff window are missed** (file changed after builder snapshot,
  before `watch` starts) → pre-existing class (today's build has the same gap); `rg` verifies
  every survivor it returns, and the window is bounded; `fs_event` covers everything post-load.
- **Orphaned builder if finder closes mid-build** → the index is session-scoped
  and reused across finder opens (`index.get` returns `current`), so a build that
  finishes after the finder closed just **warms the next open** — killing it would
  waste the work. The only cancellation is a *supersede-kill*: `M.build` calls
  `kill_inflight()` when a new build starts (e.g. a cwd switch) so a stale child
  can't race the new index. On nvim exit mid-build the (non-detached) child simply
  finishes writing its per-session cache and exits — harmless, since the next
  session rebuilds (IPC-handoff, never reused across sessions).
- **`nvim` not on PATH for the child** → use `vim.v.progpath` (absolute current nvim binary), not
  a bare `"nvim"`.

## Success Criteria
- [x] Editor stays responsive during a full 90k-file build (build cost moved to a child process;
      no main-loop time-budget loop remains in `index.lua`).
- [x] Loaded-index `query` results are byte-identical to the previous in-process build and to plain
      `rg` (round-trip unit test + manual grep parity — no false negatives).
- [x] `nvim --clean --headless -l tests/test-bigram.lua` exits 0 (existing + new round-trip/rejection tests).
- [x] `stylua --check lua/` clean; `scripts/bench-grep.lua` passes.
- [x] `engine.enabled=false` = current behavior; builder failure falls back to full `rg` scan.
- [x] Codemap regenerated (finder engine gains `serialize.lua` + `builder.lua`; build is subprocess)
      and ADR-036 written.

## ADR Required

This dev spec involves architectural decision(s) to document as ADR(s) during `/tec-implement` wrap-up:

- Build the content index in a **separate `nvim` subprocess** with a **custom binary file handoff**
  (near memory-dump: header + `col_for` pairs + raw `uint32` matrix + NUL paths) instead of an
  in-process time-budgeted timer build. Supersedes the build mechanism in **ADR-035**
  (pure-Lua bigram + rg verify) — the bigram/rg-verify decision stands; only *where/how* the index
  is built and materialized changes.
- Per-session IPC-handoff semantics (rebuild each launch, no cross-session cache) as the chosen
  point on the correctness/complexity tradeoff (avoids stale-cache mtime revalidation).

## Completed
2026-07-01 — All 3 phases implemented and committed (`e5b4048` serialize format,
`4263d5c` builder subprocess, `d5c5bf6` index.lua rewire). 39/39 unit tests pass
(round-trip + rejection + real subprocess build), `bench-grep.lua` PASS, stylua
clean. Smoke build on this repo: callback in 155 ms with 26 main-loop spins DURING
the build (non-blocking); invalid root → clean full-scan fallback. ADR-036 accepted.
Deviation from Risks: no "kill on finder close" — the index is session-scoped, so a
mid-close build warms the next open; cancellation is supersede-kill only.
