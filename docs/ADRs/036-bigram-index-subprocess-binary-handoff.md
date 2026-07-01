# ADR-036: Bigram Index Built in a Subprocess with a Binary File Handoff

**Status:** Accepted

**Date:** 2026-07-01

**Supersedes:** ADR-035 *build mechanism only* — the pure-Lua bigram + rg-verify + opt-in decision stands; only *where and how* the index is built and materialized changes.

**Evidence:** Dev spec `docs/dev-specs/finder-index-subprocess.md`; commits `e5b4048` (Phase 1 — binary serialize format), `4263d5c` (Phase 2 — builder subprocess), `d5c5bf6` (Phase 3 — index.lua rewire); files: `lua/beast/libs/finder/engine/serialize.lua`, `engine/builder.lua`, `scripts/build-finder-index.lua`, `engine/index.lua`, `engine/bigram.lua` (`M.load`); tests `tests/test-bigram.lua` (39 cases incl. round-trip + rejection); related: ADR-035 (bigram prefilter), ADR-027 (subprocess + buffered parse pattern), ADR-009/015 (native over vendored).

## Context

ADR-035 built the content index in-process, sliced into 3 ms `uv` timer ticks (`BUILD_BUDGET_MS`) so typing never stalled. That kept the editor *responsive* but not *free*: the build is a per-byte Lua loop over the whole repo (~2.1 GB / 90k files ≈ 167 s of CPU), so the index took minutes to become ready while competing with the loop for every input gap, and every session paid the full cost again. The goal was to move the heavy scan **off the editor's thread entirely** while keeping the ADR-035 no-false-negative guarantee (index reflects current content; `rg` verifies).

## Decision

Build the index in a **separate headless `nvim --headless --clean -l scripts/build-finder-index.lua` subprocess** and hand it back through a **custom binary file** that is a near memory-dump of the in-memory `Bigram`: a fixed little-endian header (magic `BEASTIDX`, version, words, max_cols, ncols, nfiles, matrix_words, file_count, FNV-1a `root_hash`), then `col_for` as uint16 key/col pairs, then the raw uint32 matrix, then NUL-separated absolute paths. `index.build` `uv.spawn`s the child (env-passed root/out/lua-root/max_*, full `vim.fn.environ()` so the child still finds `rg`), and on exit loads the file with one `serialize.read` → `bigram.load` (`ffi.copy`, a ~tens-of-ms memcpy), installs it as `current`, and starts the `fs_event` watcher. The builder reuses the **same** `bigram.lua`/`extract.lua`, so semantics are byte-identical to the old build. The child owns the walk (`list_files` moved out of `index.lua`); the time-budget tick loop is deleted. The file is a **per-session IPC handoff** — rebuilt every launch, never reused across sessions — so no stale-cache revalidation is needed and the guarantee holds trivially.

## Alternatives Considered

1. **Keep the in-process time-budget build (ADR-035)** — rejected: still minutes-to-ready and a per-byte Lua loop contending with the loop; responsive ≠ off-thread.
2. **libuv worker thread (`vim.uv.new_thread`)** — rejected: a thread has its own Lua state, and handing the 56 MB FFI matrix back to the main state still needs shared memory or a file; a process is simpler, fully isolated, and reuses the modules verbatim.
3. **Cross-session persistent cache (mtime revalidation)** — rejected (for now): a file that gained the query bigram after the build but before load would be pruned → false negative unless every changed file is re-read; per-session rebuild keeps the guarantee for free. Format leaves room to add this later.
4. **JSON / MessagePack / SQLite serialization** — rejected: the matrix is tens of MB of uint32; structured formats bloat it and force parse-time allocation. A raw `ffi.copy` of the native layout is transformation-free — the whole point of controlling both writer and reader.
5. **Compiled builder / vendored binary** — rejected, same as ADR-035: reintroduces build-hook fragility and leaves pure Lua; a headless `nvim` child is always present, ships nothing extra, and guarantees identical bigram semantics.

## Consequences

**Positive:** the main loop is fully free during the build — measured 26 main-loop spins during a 155 ms build on this repo (vs. the old build fighting for input gaps); the ~167 s cost on a 90k repo moves entirely to a child process; load is a fast memcpy; the index stays warm across finder opens within a session (a mid-close build warms the next open); the format is `mmap`-ready without changes. **Tradeoffs:** a child `nvim` per build (~50–100 ms startup) and a per-session cache file under `stdpath("cache")` (~62 MB on this repo); the environment must be passed through so the child finds `rg`; the format is same-host native-endian (magic + version + `root_hash` reject foreign/wrong-root/truncated files → full-scan fallback); build-time oversize-skip counts no longer surface in `M.report` (build happens in the child); the build-window edit gap is unchanged (pre-existing; `rg` verifies every survivor). **Cancellation:** a superseding build (cwd switch) supersede-kills the prior child (`kill_inflight`); an editor exit mid-build lets the non-detached child finish writing its per-session cache and exit — harmless since the next session rebuilds. **New shared modules:** `engine/serialize.lua` + `engine/builder.lua` and a `scripts/` entry other code may reuse.
